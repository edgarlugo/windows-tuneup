BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:I18nRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n'
    Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    # The fixture catalog has an action tweak, whose script comes from the fixture actions folder.
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')

    # A catalog with one tweak of each kind that matters to the list, and base listed last on purpose.
    function New-TestDefinition {
        $system = New-TestTweak -Id 'test.system' -Scope 'machine' -RebootRequired $true `
            -Set ([pscustomobject]@{ path = 'HKLM:\Software\windows-tuneup-test'; name = 'Sample'; kind = 'DWord'; value = 1 })
        $catalog = @(
            (New-TestTweak -Id 'test.user'),
            $system,
            (New-TestTweak -Id 'test.asked' -Ask $true),
            (New-TestTweak -Id 'test.risky' -Risk 'high'),
            (New-TestTweak -Id 'test.later' -MinBuild 99999),
            (New-TestTweak -Id 'test.portable' -Requires @('battery'))
        )
        $profiles = @(
            (New-TestProfile -Id 'work' -Include @('test.system', 'test.later') -Aliases @('trabajo')),
            (New-TestProfile -Id 'base' -Include @('test.user', 'test.asked', 'test.portable'))
        )
        [pscustomobject]@{ Catalog = $catalog; Profiles = $profiles; Problems = [string[]]@() }
    }

    # A context like the one tuneup.ps1 builds, on the fixture catalog, with a known environment.
    function New-TestContext([switch]$Json, $Environment = (New-TestEnvironment -IsAdmin $false)) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo)
        $context.StateRoot = Join-Path $TestDrive 'state'
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = $Environment
        $context
    }
}

Describe 'Get-TuneupListDocument' {
    It 'lists base first, then the other profiles, with their aliases and texts' {
        $document = Get-TuneupListDocument -Definition (New-TestDefinition) -Environment (New-TestEnvironment)
        $document.schemaVersion | Should -Be 1
        $document.command | Should -Be 'list'
        @($document.profiles | ForEach-Object { $_.id }) -join ',' | Should -Be 'base,work'
        @($document.profiles[1].aliases) -join ',' | Should -Be 'trabajo'
        @($document.profiles[0].aliases).Count | Should -Be 0
        $document.profiles[1].title | Should -Be 'work'
        $document.profiles[1].description | Should -Be 'Description'
    }

    It 'counts only the tweaks of a profile that suit this machine, and says when one needs administrator' {
        $document = Get-TuneupListDocument -Definition (New-TestDefinition) -Environment (New-TestEnvironment -HasBattery $false)
        $base = $document.profiles | Where-Object { $_.id -eq 'base' }
        $work = $document.profiles | Where-Object { $_.id -eq 'work' }
        $base.tweakCount | Should -Be 2
        $base.needsAdmin | Should -BeFalse
        $work.tweakCount | Should -Be 1
        $work.needsAdmin | Should -BeTrue
    }

    It 'gives each tweak that suits the machine with what is needed to choose it' {
        $document = Get-TuneupListDocument -Definition (New-TestDefinition) -Environment (New-TestEnvironment)
        $system = $document.tweaks | Where-Object { $_.id -eq 'test.system' }
        $system.title | Should -Be 'Title test.system'
        $system.why | Should -Be 'Reason'
        $system.risk | Should -Be 'low'
        $system.ask | Should -BeFalse
        $system.type | Should -Be 'registry'
        $system.scope | Should -Be 'machine'
        $system.needsAdmin | Should -BeTrue
        $system.rebootRequired | Should -BeTrue
        @($system.requires).Count | Should -Be 0
        @($system.profiles) -join ',' | Should -Be 'work'
        $asked = $document.tweaks | Where-Object { $_.id -eq 'test.asked' }
        $asked.ask | Should -BeTrue
        @($asked.profiles) -join ',' | Should -Be 'base'
        $risky = $document.tweaks | Where-Object { $_.id -eq 'test.risky' }
        $risky.risk | Should -Be 'high'
        @($risky.profiles).Count | Should -Be 0
    }

    It 'leaves out what does not suit this machine and says why' {
        $document = Get-TuneupListDocument -Definition (New-TestDefinition) -Environment (New-TestEnvironment -HasBattery $false)
        @($document.tweaks | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.user,test.system,test.asked,test.risky'
        @($document.incompatible | ForEach-Object { "$($_.id):$($_.reason)" }) -join ',' | Should -Be 'test.later:incompatible,test.portable:not-applicable-hardware'
    }

    It 'lists a tweak meant for laptops on a machine with a battery' {
        $document = Get-TuneupListDocument -Definition (New-TestDefinition) -Environment (New-TestEnvironment -HasBattery $true)
        ($document.profiles | Where-Object { $_.id -eq 'base' }).tweakCount | Should -Be 3
        @(($document.tweaks | Where-Object { $_.id -eq 'test.portable' }).requires) -join ',' | Should -Be 'battery'
        @($document.incompatible | ForEach-Object { $_.id }) -join ',' | Should -Be 'test.later'
    }

    It 'writes the texts in the language of the run' {
        Initialize-TuneupI18n -Root $I18nRoot -Lang 'es'
        try {
            $document = Get-TuneupListDocument -Definition (New-TestDefinition) -Environment (New-TestEnvironment)
            ($document.tweaks | Where-Object { $_.id -eq 'test.user' }).title | Should -Be 'Titulo test.user'
            ($document.tweaks | Where-Object { $_.id -eq 'test.user' }).why | Should -Be 'Motivo'
            $document.profiles[0].description | Should -Be 'Descripcion'
        } finally {
            Initialize-TuneupI18n -Root $I18nRoot -Lang 'en'
        }
    }
}

Describe 'Invoke-TuneupListCommand' {
    It 'writes one list document and exits with 0' {
        $context = New-TestContext -Json
        $documents = @(Invoke-TuneupListCommand -Context $context | ForEach-Object { $_ | ConvertFrom-Json })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'list'
        $documents[0].toolVersion | Should -Be (Get-TuneupVersion)
        $documents[0].PSObject.Properties.Name | Should -Contain 'warnings'
        @($documents[0].profiles | ForEach-Object { $_.id }) -join ',' | Should -Be 'base,extra,nested,system'
        ($documents[0].tweaks | Where-Object { $_.id -eq 'test.machine' }).needsAdmin | Should -BeTrue
        $context.ExitCode | Should -Be 0
    }

    It 'shows a list for people without -Json' {
        $context = New-TestContext
        $text = (Invoke-TuneupListCommand -Context $context 6>&1 | Out-String)
        $text | Should -Match 'Profiles:'
        $text | Should -Match 'system - System: 1 tweaks for this PC \(administrator\)'
        $text | Should -Match 'test\.one - Test one \[low risk\]'
        $context.ExitCode | Should -Be 0
    }

    It 'refuses a Windows version that is not supported, like every command that reads the catalog' {
        $context = New-TestContext -Json -Environment (New-TestEnvironment -Build 17763)
        $document = Invoke-TuneupListCommand -Context $context | ConvertFrom-Json
        $document.command | Should -Be 'error'
        $context.ExitCode | Should -Be 1
    }
}
