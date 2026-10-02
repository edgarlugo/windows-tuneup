BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'sandbox\E2E.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function New-Snapshot([hashtable]$Tweaks = @{}, [hashtable]$Services = @{}, [string[]]$Apps = @()) {
        $map = [ordered]@{}
        foreach ($name in $Tweaks.Keys) { $map[$name] = [pscustomobject]@{ type = $Tweaks[$name][0]; state = $Tweaks[$name][1] } }
        $serviceMap = [ordered]@{}
        foreach ($name in $Services.Keys) { $serviceMap[$name] = $Services[$name] }
        [pscustomobject]@{ takenAt = 'now'; tweaks = $map; services = $serviceMap; tasks = [ordered]@{}; apps = $Apps }
    }
}

Describe 'End-to-end snapshots' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'sees the change of an applied tweak and nothing once it is undone' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $Key; name = 'E2E'; kind = 'DWord'; value = 1 })
        $before = Get-E2ESnapshot -Catalog @($tweak) -Parts 'Tweaks'
        $run = New-TuneupRun -StateRoot (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -WarningAction SilentlyContinue
        $plan = @(New-TuneupPlan -Catalog @($tweak) -Profiles @(New-TestProfile -Id 'base' -Include @('test.sample')) `
            -Environment (New-TestEnvironment) -TestState { param($item) Test-TuneupState -Tweak $item })
        Invoke-TuneupPlan -Plan $plan -RunDir $run.Dir | Out-Null
        $changed = @(Compare-E2ESnapshot -Before $before -After (Get-E2ESnapshot -Catalog @($tweak) -Parts 'Tweaks'))
        ($changed | ForEach-Object { "$($_.kind) $($_.name) $($_.volatile)" }) -join ',' | Should -Be 'tweak test.sample False'
        Invoke-TuneupUndo -Run $run | Out-Null
        @(Compare-E2ESnapshot -Before $before -After (Get-E2ESnapshot -Catalog @($tweak) -Parts 'Tweaks')).Count | Should -Be 0
    }

    It 'reads the services and the scheduled tasks of the machine' {
        $snapshot = Get-E2ESnapshot -Catalog @() -Parts 'Services', 'Tasks'
        $snapshot.services.Count | Should -BeGreaterThan 50
        $snapshot.tasks.Count | Should -BeGreaterThan 10
        $snapshot.services['EventLog'] | Should -Match '^start=\d delayed=\d$'
    }

    It 'calls volatile a service that only started or stopped, and not a change of its start type' {
        $before = New-Snapshot -Tweaks @{ 's.one' = @('service', '{"present":true,"startType":"Manual","running":false}') }
        $started = New-Snapshot -Tweaks @{ 's.one' = @('service', '{"present":true,"startType":"Manual","running":true}') }
        $disabled = New-Snapshot -Tweaks @{ 's.one' = @('service', '{"present":true,"startType":"Disabled","running":false}') }
        @(Compare-E2ESnapshot -Before $before -After $started)[0].volatile | Should -BeTrue
        @(Compare-E2ESnapshot -Before $before -After $disabled)[0].volatile | Should -BeFalse
    }

    It 'reports services that changed and apps that went missing or appeared' {
        $before = New-Snapshot -Services @{ 'A' = 'start=3 delayed=0' } -Apps @('App.One', 'App.Two')
        $after = New-Snapshot -Services @{ 'A' = 'start=4 delayed=0' } -Apps @('App.Two', 'App.Three')
        $differences = @(Compare-E2ESnapshot -Before $before -After $after)
        ($differences | ForEach-Object { "$($_.kind):$($_.name):$($_.after)" }) -join ',' | Should -Be 'service:A:start=4 delayed=0,app:App.One:missing,app:App.Three:installed'
    }

    It 'fills the .wsb template with the folders escaped, as valid XML' {
        $template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'sandbox\e2e.wsb'))
        [xml]$xml = New-E2EConfiguration -Template $template -Repo 'C:\code & more\windows-tuneup' -Output 'C:\out' -Arguments '-Profiles base,lite -KeepOpen'
        $folders = @($xml.Configuration.MappedFolders.MappedFolder)
        $folders[0].HostFolder | Should -Be 'C:\code & more\windows-tuneup'
        $folders[0].ReadOnly | Should -Be 'true'
        $folders[1].HostFolder | Should -Be 'C:\out'
        $folders[1].ReadOnly | Should -Be 'false'
        $xml.Configuration.LogonCommand.Command | Should -Match 'Invoke-E2E\.ps1 -Repo C:\\windows-tuneup -Output C:\\e2e-out -Profiles base,lite -KeepOpen$'
    }
}
