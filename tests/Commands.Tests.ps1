BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    # The fixture catalog has an action tweak, whose script comes from the fixture actions folder.
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    # A context like the one tuneup.ps1 builds, on the fixture catalog, with a known environment.
    function New-TestContext([switch]$Json, [object[]]$Answers = @()) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo -Answers $Answers)
        $context.StateRoot = $script:Root
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = New-TestEnvironment -IsAdmin $false
        $context
    }
    # Runs a command and gives the JSON documents it wrote, parsed.
    function Get-JsonOutput([scriptblock]$Command) {
        @(& $Command 6>$null | ForEach-Object { $_ | ConvertFrom-Json })
    }
}

Describe 'Commands' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'shows the plan as one JSON document and changes nothing' {
        $context = New-TestContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -PlanOnly })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'plan'
        $documents[0].summary.apply | Should -Be 2
        $context.ExitCode | Should -Be 0
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'applies with -Yes, keeps the report as the result and sets the exit code' {
        $context = New-TestContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Yes })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'apply'
        $context.Result.summary.applied | Should -Be 2
        $context.ExitCode | Should -Be 0
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
    }

    It 'asks through the context and changes nothing when the answer is no' {
        $context = New-TestContext -Answers @('n')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        $context.ExitCode | Should -Be 1
        $context.Io.Output -join "`n" | Should -Match 'Apply 2 changes\? \(y/n\)'
        $context.Io.Output -join "`n" | Should -Match 'Cancelled'
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'applies when the answer is yes' {
        $context = New-TestContext -Answers @('y')
        Invoke-TuneupApplyCommand -Context $context 6>$null
        $context.ExitCode | Should -Be 0
        (Get-ItemProperty -LiteralPath $Key).Two | Should -Be 'x'
    }

    It 'writes one error document, and nothing else, when the catalog has problems' {
        $context = New-TestContext -Json
        $context.CatalogPath = Join-Path $TestDrive 'broken-catalog'
        New-Item -ItemType Directory -Path $context.CatalogPath -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $context.CatalogPath 'bad.json'), '{ "tweaks": "no" }')
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -PlanOnly })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'error'
        @($documents[0].details) -join ' ' | Should -Match 'no tweaks array'
        $context.ExitCode | Should -Be 1
    }

    It 'refuses Windows Server without -Force and plans it like Enterprise with it' {
        $context = New-TestContext -Json
        $context.Environment.IsServer = $true
        $context.Environment.Edition = 'Server'
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -PlanOnly })
        $documents[0].message | Should -Match 'Windows Server'
        $context.ExitCode | Should -Be 1
        $context.Force = $true
        $documents = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -PlanOnly })
        $documents[0].command | Should -Be 'plan'
        $context.Environment.Edition | Should -Be 'Enterprise'
    }

    It 'reports status, undoes the last run and says when there is nothing left' {
        $context = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Yes } | Out-Null
        $status = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context })
        $status[0].command | Should -Be 'status'
        @($context.Result).Count | Should -Be 2
        $undo = @(Get-JsonOutput { Invoke-TuneupUndoCommand -Context $context -RunId 'last' })
        $undo[0].summary.restored | Should -Be 2
        $context.ExitCode | Should -Be 0
        $again = @(Get-JsonOutput { Invoke-TuneupUndoCommand -Context $context -RunId 'last' })
        $again[0].message | Should -Be 'There are no runs to undo.'
        $context.ExitCode | Should -Be 1
    }

    It 'refuses -Health without elevation' {
        $context = New-TestContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupHealthCommand -Context $context })
        $documents[0].message | Should -Be '-Health needs PowerShell as administrator.'
        $context.ExitCode | Should -Be 1
    }

    It 'measures and compares against the measurement before it' {
        $context = New-TestContext -Json
        $first = @(Get-JsonOutput { Invoke-TuneupMeasureCommand -Context $context })
        $first[0].command | Should -Be 'measure'
        $second = @(Get-JsonOutput { Invoke-TuneupMeasureCommand -Context $context -Compare 'last' })
        $second[0].comparison.againstId | Should -Be $first[0].id
        $context.ExitCode | Should -Be 0
    }

    It 'starts with exit code 1, so a command that fails to report never looks successful' {
        (New-TuneupContext).ExitCode | Should -Be 1
        $context = New-TestContext -Json
        Mock -ModuleName Tuneup Write-TuneupJson { throw 'disk full' }
        { Invoke-TuneupStatusCommand -Context $context } | Should -Throw 'disk full'
        $context.ExitCode | Should -Be 1
    }

    It 'turns what a command throws into an error document and exit code 1' {
        $context = New-TestContext -Json
        $context.ExitCode = 0
        $documents = @(Get-JsonOutput { Invoke-TuneupGuarded -Context $context -Command { throw 'boom' } })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'error'
        $documents[0].message | Should -Be 'boom'
        $context.ExitCode | Should -Be 1
    }

    It 'leaves exit code 1 when the error report cannot be written either' {
        $context = New-TestContext -Json
        $context.ExitCode = 0
        Mock -ModuleName Tuneup Write-TuneupJson { throw 'disk full' }
        { Invoke-TuneupGuarded -Context $context -Command { throw 'boom' } } | Should -Throw 'disk full'
        $context.ExitCode | Should -Be 1
    }

    It 'leaves what a command wrote and its code alone when nothing is thrown' {
        $context = New-TestContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupGuarded -Context $context -Command { Invoke-TuneupStatusCommand -Context $context } })
        $documents[0].command | Should -Be 'status'
        $context.ExitCode | Should -Be 0
    }

    It 'shows the waiting line of a measurement through Io' {
        $context = New-TestContext
        Mock -ModuleName Tuneup Measure-TuneupSystem { [pscustomobject]@{ schemaVersion = 1 } }
        Mock -ModuleName Tuneup Save-TuneupMeasurement { [pscustomobject]@{ Id = 'm1' } }
        Mock -ModuleName Tuneup New-TuneupMeasureReport { [pscustomobject]@{ schemaVersion = 1; command = 'measure' } }
        Mock -ModuleName Tuneup Write-TuneupMeasureReport { }
        Invoke-TuneupMeasureCommand -Context $context -IdleSeconds 5
        $context.Io.Output -join "`n" | Should -Match 'Waiting 5 seconds idle'
        $context.ExitCode | Should -Be 0
    }

    It 'shows the health lines through Io' {
        $context = New-TestContext
        $context.Environment = New-TestEnvironment -IsAdmin $true
        Mock -ModuleName Tuneup Invoke-TuneupHealth { & $OnPhase 'sfc'; [pscustomobject]@{ recommendation = 'none' } }
        Mock -ModuleName Tuneup Write-TuneupHealthReport { }
        Invoke-TuneupHealthCommand -Context $context
        $text = $context.Io.Output -join "`n"
        $text | Should -Match 'Checking the health of Windows'
        $text | Should -Match 'Running SFC: it checks'
        $context.ExitCode | Should -Be 0
    }

    It 'carries the version of the tool in every JSON document' {
        $context = New-TestContext -Json
        @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context })[0].toolVersion | Should -Be (Get-TuneupVersion)
    }
}

Describe 'Invoke-TuneupCli' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    It 'rejects an invalid combination before reading anything' {
        $context = New-TuneupContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -Status -Yes -StateRoot $Root })
        $documents[0].message | Should -Match 'Invalid parameter combination: -Status -Yes'
        $context.ExitCode | Should -Be 1
        Test-Path -LiteralPath $Root | Should -BeFalse
    }

    It 'resolves the folders into the context and runs the command they name' {
        $context = New-TuneupContext -Json
        $documents = @(Get-JsonOutput {
            Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -Status -StateRoot $Root `
                -CatalogPath (Join-Path $Fixtures 'catalog') -ProfilesPath (Join-Path $Fixtures 'profiles')
        })
        $documents[0].command | Should -Be 'status'
        $context.StateRoot | Should -Be $Root
        $context.CatalogPath | Should -Be (Join-Path $Fixtures 'catalog')
    }
}
