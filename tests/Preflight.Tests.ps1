BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function New-PlanItem([string]$Scope = 'user', [string]$Action = 'apply') {
        $tweak = $(if ($Scope -eq 'machine') { New-TestMachineTweak } else { New-TestTweak })
        [pscustomobject]@{ Id = $tweak.id; Tweak = $tweak; Action = $Action; Reason = $null }
    }
    function Get-PreflightId($Environment, $Plan, $ScriptRoot) {
        @(Get-TuneupPreflight -Environment $Environment -Plan $Plan -ScriptRoot $ScriptRoot | ForEach-Object { $_.id }) -join ','
    }
    function New-TestContext([switch]$Json, [object[]]$Answers = @()) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo -Answers $Answers)
        $context.StateRoot = $script:Root
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = New-TestEnvironment -IsAdmin $false
        $context.Environment.PendingReboot = $true
        $context
    }
}

Describe 'Get-TuneupPreflight' {
    BeforeEach {
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreState { 'enabled' }
        Mock -ModuleName Tuneup Test-TuneupTrustedLocation { $true }
    }

    It 'says nothing for a plan that changes nothing' {
        $environment = New-TestEnvironment -IsManaged $true
        $environment.PendingReboot = $true
        Get-PreflightId $environment @(New-PlanItem -Action 'skip') $null | Should -BeNullOrEmpty
    }

    It 'warns about a pending restart, a full disk and a managed machine' {
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 1.5 }
        $environment = New-TestEnvironment -IsManaged $true -IsAdmin $false
        $environment.PendingReboot = $true
        Get-PreflightId $environment @(New-PlanItem) $null | Should -Be 'pending-reboot,low-disk,managed-device'
        (Get-TuneupPreflight -Environment $environment -Plan @(New-PlanItem) | Where-Object { $_.id -eq 'low-disk' }).message | Should -Match '^1.5 GB are free on the system drive \(less than 2 GB\)'
    }

    It 'reads System Restore only for system changes made elevated' -TestCases @(
        @{ State = 'disabled'; Expected = 'restore-disabled' }
        @{ State = 'blocked'; Expected = 'restore-blocked' }
        @{ State = 'unknown'; Expected = '' }
        @{ State = 'enabled'; Expected = '' }
    ) {
        param($State, $Expected)
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreState { $State }
        Get-PreflightId (New-TestEnvironment -IsAdmin $true) @(New-PlanItem -Scope 'machine') $null | Should -Be $Expected
        Get-PreflightId (New-TestEnvironment -IsAdmin $true) @(New-PlanItem) $null | Should -BeNullOrEmpty
        Get-PreflightId (New-TestEnvironment -IsAdmin $false) @(New-PlanItem -Scope 'machine') $null | Should -BeNullOrEmpty
    }

    It 'warns when it runs elevated from a folder that others can change' {
        Mock -ModuleName Tuneup Test-TuneupTrustedLocation { $false }
        Get-PreflightId (New-TestEnvironment -IsAdmin $true) @(New-PlanItem) 'C:\Users\x\Downloads\windows-tuneup' | Should -Be 'untrusted-location'
        Get-PreflightId (New-TestEnvironment -IsAdmin $false) @(New-PlanItem) 'C:\Users\x\Downloads\windows-tuneup' | Should -BeNullOrEmpty
    }
}

Describe 'Get-TuneupSystemRestoreState' {
    BeforeEach {
        Mock -ModuleName Tuneup Get-TuneupSystemVolumeId { 'Volume{4474738e-ed83-4609-8f9a-d6862426c25e}' }
        Mock -ModuleName Tuneup Test-TuneupSystemRestorePolicy { $false }
    }

    It 'finds the system volume among the protected ones, whatever the case' {
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreEntry { '\\?\VOLUME{4474738E-ED83-4609-8F9A-D6862426C25E}\:(C%3A)' }
        Get-TuneupSystemRestoreState | Should -Be 'enabled'
    }

    It 'says disabled, or blocked by a policy, when the volume is not listed' {
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreEntry { '\\?\Volume{00000000-0000-0000-0000-000000000000}\:(D%3A)' }
        Get-TuneupSystemRestoreState | Should -Be 'disabled'
        Mock -ModuleName Tuneup Test-TuneupSystemRestorePolicy { $true }
        Get-TuneupSystemRestoreState | Should -Be 'blocked'
    }

    It 'says unknown when the list cannot be read' {
        Mock -ModuleName Tuneup Get-TuneupSystemRestoreEntry { throw 'Access denied' }
        Get-TuneupSystemRestoreState | Should -Be 'unknown'
    }
}

Describe 'Preflight when applying' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        Mock -ModuleName Tuneup Enable-TuneupSystemRestore { }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'puts the warnings in the JSON plan, in the apply report and in result.json, without stopping' {
        $context = New-TestContext -Json
        $plan = Invoke-TuneupApplyCommand -Context $context -PlanOnly | ConvertFrom-Json
        @($plan.preflight | ForEach-Object { $_.id }) | Should -Be @('pending-reboot')
        $apply = Invoke-TuneupApplyCommand -Context $context -Yes | ConvertFrom-Json
        $context.ExitCode | Should -Be 0
        @($apply.preflight | ForEach-Object { $_.id }) | Should -Be @('pending-reboot')
        $saved = Get-Content -LiteralPath (Join-Path $apply.runDir 'result.json') -Raw | ConvertFrom-Json
        $saved.preflight[0].id | Should -Be 'pending-reboot'
        [System.IO.File]::ReadAllText((Join-Path $apply.runDir 'transcript.log')) | Should -Match 'Windows has a restart pending'
    }

    It 'shows the warnings next to the plan before asking' {
        $context = New-TestContext -Answers @('n')
        $text = (Invoke-TuneupApplyCommand -Context $context 6>&1 | Out-String)
        $text | Should -Match 'Before applying:'
        $text | Should -Match '! Windows has a restart pending'
        $context.ExitCode | Should -Be 1
    }

    It 'offers to turn System Restore on only after the apply is confirmed, and drops the warning once it is on' {
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'restore-disabled'; message = 'System Restore is turned off' } }
        $context = New-TestContext -Answers @('y', 'y')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 1 -Exactly
        $output = $context.Io.Output -join "`n"
        $output | Should -Match 'Changes to apply: 2\. Apply\? \(y/n\)[\s\S]*Turn on System Restore on .* before applying\? \(y/n\)'
        @($context.Result.preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count | Should -Be 0
        $saved = Get-Content -LiteralPath (Join-Path $context.Result.runDir 'result.json') -Raw | ConvertFrom-Json
        @($saved.preflight | Where-Object { $_.id -eq 'restore-disabled' }).Count | Should -Be 0
    }

    It 'keeps the warning when System Restore is not turned on' {
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'restore-disabled'; message = 'System Restore is turned off' } }
        $context = New-TestContext -Answers @('y', 'n')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 0 -Exactly
        @($context.Result.preflight | ForEach-Object { $_.id }) | Should -Be @('restore-disabled')
    }

    It 'never asks about System Restore when the apply is declined' {
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'restore-disabled'; message = 'System Restore is turned off' } }
        $context = New-TestContext -Answers @('n')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 0 -Exactly
        $context.Io.Output -join "`n" | Should -Not -Match 'Turn on System Restore'
        $context.ExitCode | Should -Be 1
    }

    It 'never asks nor turns System Restore on with -Yes' {
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'restore-disabled'; message = 'System Restore is turned off' } }
        $context = New-TestContext
        $text = (Invoke-TuneupApplyCommand -Context $context -Yes 6>&1 | Out-String)
        $text | Should -Match '! System Restore is turned off'
        $context.ExitCode | Should -Be 0
        Should -Invoke Enable-TuneupSystemRestore -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Test-TuneupTrustedLocation' {
    It 'does not trust a copy in a folder that the user owns' {
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $copy 'engine') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $copy 'tuneup.ps1'), '')
        [System.IO.File]::WriteAllText((Join-Path $copy 'engine\Tuneup.psm1'), '')
        Test-TuneupTrustedLocation -ScriptRoot $copy | Should -BeFalse
    }
}

Describe 'Locations in what the run keeps' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        Mock -ModuleName Tuneup Test-TuneupTrustedLocation { $false }
        $script:Profile = $env:USERPROFILE.TrimEnd('\')
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'writes the untrusted folder with the profile folder as %USERPROFILE% and rewords the warning' {
        $items = @(Get-TuneupPreflight -Environment (New-TestEnvironment -IsAdmin $true) -Plan @(New-PlanItem) -ScriptRoot (Join-Path $Profile 'Downloads\windows-tuneup'))
        $items.Count | Should -Be 1
        $items[0].message | Should -Match '%USERPROFILE%\\Downloads\\windows-tuneup'
        $items[0].message | Should -Not -Match ([regex]::Escape($Profile))
        $items[0].message | Should -Match 'that non-elevated processes \(including your own\) can change'
    }

    It 'never writes the account name nor the profile folder in transcript.log or result.json, from a profile folder' {
        $context = New-TestContext -Json
        $context.Environment = New-TestEnvironment -IsAdmin $true
        $context.ScriptRoot = Join-Path $Profile "Downloads\$env:USERNAME\windows-tuneup"
        Invoke-TuneupApplyCommand -Context $context -Yes | Out-Null
        $context.ExitCode | Should -Be 0
        $runDir = $context.Result.runDir
        # The run folder of this test is under the profile too, so the paths in the files are real ones.
        $runDir | Should -Match ([regex]::Escape($Profile))
        foreach ($name in 'transcript.log', 'result.json') {
            $text = [System.IO.File]::ReadAllText((Join-Path $runDir $name))
            $text | Should -Match '%USERPROFILE%' -Because $name
            $text | Should -Not -Match ('(?i)' + [regex]::Escape($Profile)) -Because $name
            $text | Should -Not -Match ('(?i)' + [regex]::Escape($Profile.Replace('\', '\\'))) -Because $name
            $text | Should -Not -Match ('(?i)(?<![A-Za-z0-9])' + [regex]::Escape($env:USERNAME) + '(?![A-Za-z0-9])') -Because $name
        }
        [System.IO.File]::ReadAllText((Join-Path $runDir 'transcript.log')) | Should -Match 'non-elevated processes'
    }
}

Describe 'Hide-TuneupPersonalData' {
    It 'replaces the profile folder and the account name, whatever the case' {
        $text = "Folder $($env:USERPROFILE.ToLowerInvariant())\AppData of $($env:USERNAME.ToUpperInvariant())"
        Hide-TuneupPersonalData -Text $text | Should -Be 'Folder %USERPROFILE%\AppData of %USERNAME%'
    }

    It 'replaces the profile folder as it is written in JSON' {
        $json = ConvertTo-Json -InputObject ([pscustomobject]@{ dir = (Join-Path $env:USERPROFILE 'x') })
        $hidden = Hide-TuneupPersonalData -Text $json -JsonEscaped
        ($hidden | ConvertFrom-Json).dir | Should -Be '%USERPROFILE%\x'
    }

    It 'leaves a word that only contains the name alone' {
        Hide-TuneupPersonalData -Text "$($env:USERNAME)s and x$($env:USERNAME)" | Should -Be "$($env:USERNAME)s and x$($env:USERNAME)"
    }

    It 'gives back text without either of them untouched' {
        Hide-TuneupPersonalData -Text 'Applied: 2 | Partial: 0' | Should -Be 'Applied: 2 | Partial: 0'
        Hide-TuneupPersonalData -Text '' | Should -Be ''
    }
}

Describe 'Test-TuneupTrustedLocation and the folders the tool reads' {
    BeforeEach {
        $script:Copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $Copy -Force | Out-Null
        # The program files themselves are taken as trusted, so only the other folders decide.
        Mock -ModuleName Tuneup Test-TuneupTrustedExecutable { $true }
    }

    It 'trusts a location with nothing else to read' {
        Test-TuneupTrustedLocation -ScriptRoot $Copy | Should -BeTrue
    }

    It 'does not trust a location when <Folder> is a folder that the user owns' -TestCases @(
        @{ Folder = 'catalog' }
        @{ Folder = 'profiles' }
        @{ Folder = 'actions' }
        @{ Folder = 'i18n' }
        @{ Folder = 'engine' }
    ) {
        param($Folder)
        $path = Join-Path $Copy $Folder
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $path 'x.json'), '{}')
        Test-TuneupTrustedLocation -ScriptRoot $Copy | Should -BeFalse
    }
}
