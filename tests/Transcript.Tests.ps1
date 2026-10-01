BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function New-TestContext([switch]$Json) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo)
        $context.StateRoot = $script:Root
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = New-TestEnvironment -IsAdmin $false
        $context
    }
    function Get-Transcript($Context) {
        [System.IO.File]::ReadAllText((Join-Path $Context.Result.runDir 'transcript.log'))
    }
}

Describe 'transcript.log' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'keeps with the run what was asked for, the plan and the report, in the language of the run' {
        $context = New-TestContext
        Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -Exclude @('test.two') -Yes 6>$null
        $text = Get-Transcript $context
        $text | Should -Match ("windows-tuneup $([regex]::Escape((Get-TuneupVersion))) - run $($context.Result.runId) - ")
        $text | Should -Match 'Asked for: profiles extra; included -; excluded test.two'
        $text | Should -Match 'Plan: 2 to apply, 1 skipped'
        $text | Should -Match '\[applied\] Test three: settings'
        $text | Should -Match 'Applied: 2 \| Partial: 0'
    }

    It 'writes the text for people also with -Json, and adds each undo of the run' {
        $context = New-TestContext -Json
        Invoke-TuneupApplyCommand -Context $context -Yes | Out-Null
        $runDir = $context.Result.runDir
        $text = Get-Transcript $context
        $text | Should -Not -Match '"schemaVersion"'
        $text | Should -Match 'Applied: 2'
        Invoke-TuneupUndoCommand -Context $context -RunId 'last' | Out-Null
        $after = [System.IO.File]::ReadAllText((Join-Path $runDir 'transcript.log'))
        $after.StartsWith($text) | Should -BeTrue
        $after | Should -Match 'Undo with windows-tuneup'
        $after | Should -Match 'Restored: 2 \| Failed: 0 \| Skipped: 0'
    }

    It 'never writes the names of the machine or the account, nor the environment' {
        $context = New-TestContext
        Invoke-TuneupApplyCommand -Context $context -Yes 6>$null
        $text = Get-Transcript $context
        $text | Should -Not -Match ([regex]::Escape($env:COMPUTERNAME))
        $text | Should -Not -Match ([regex]::Escape((Get-TestCurrentSid)))
        $text | Should -Not -Match '(?m)^(Username|RunAs User|Machine|Host Application|Process ID):'
    }

    It 'goes on with a warning when the transcript cannot be written' {
        $context = New-TestContext -Json
        Mock -ModuleName Tuneup Add-TuneupTranscript { throw 'disk full' }
        $json = Invoke-TuneupApplyCommand -Context $context -Yes | ConvertFrom-Json
        $context.ExitCode | Should -Be 0
        @($json.warnings) -join ' ' | Should -Match 'transcript of run .* could not be saved: disk full'
    }
}
