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
        $context.Io.Output -join "`n" | Should -Match 'Changes to apply: 2\. Apply\? \(y/n\)'
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
        $documents[0].reason | Should -Be 'needs-admin'
        $context.ExitCode | Should -Be 1
    }

    It 'refuses to undo a run with system changes without elevation, with the reason needs-admin' {
        $context = New-TestContext -Json
        $run = New-TuneupRun -StateRoot $Root -WarningAction SilentlyContinue
        Add-TuneupJournalEntry -Path (Join-Path $run.Dir 'snapshot.jsonl') -Tweak (New-TestMachineTweak) -State $null -Root 'custom'
        $documents = @(Get-JsonOutput { Invoke-TuneupUndoCommand -Context $context -RunId $run.Id })
        $documents[0].command | Should -Be 'error'
        $documents[0].reason | Should -Be 'needs-admin'
        $documents[0].message | Should -Match 'undoing it needs PowerShell as administrator'
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
        $context.Io.Output -join "`n" | Should -Match 'Waiting idle before measuring \(5 s\)'
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

Describe 'Re-applying what drifted' {
    BeforeAll {
        # The fixture catalog and profiles plus four tweaks of the re-apply: two plain ones (applied in the
        # order b, a, which is not the alphabetical one), one that asks first and one of high risk.
        function New-ReapplyDefinition {
            $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path (Join-Path $dir 'catalog'), (Join-Path $dir 'profiles') -Force | Out-Null
            Copy-Item -Path (Join-Path $Fixtures 'catalog\*.json') -Destination (Join-Path $dir 'catalog')
            Copy-Item -Path (Join-Path $Fixtures 'profiles\*.json') -Destination (Join-Path $dir 'profiles')
            $extra = @(
                (New-TestTweak -Id 'rea.b' -Set ([pscustomobject]@{ path = $Key; name = 'B'; kind = 'DWord'; value = 1 })),
                (New-TestTweak -Id 'rea.a' -Set ([pscustomobject]@{ path = $Key; name = 'A'; kind = 'DWord'; value = 1 })),
                (New-TestTweak -Id 'rea.ask' -Ask $true -Set ([pscustomobject]@{ path = $Key; name = 'Ask'; kind = 'DWord'; value = 1 })),
                (New-TestTweak -Id 'rea.high' -Risk 'high' -Set ([pscustomobject]@{ path = $Key; name = 'High'; kind = 'DWord'; value = 1 }))
            )
            [System.IO.File]::WriteAllText((Join-Path $dir 'catalog\rea.json'), (ConvertTo-Json -InputObject ([pscustomobject]@{ tweaks = $extra }) -Depth 10))
            $dir
        }

        # The four tweaks applied by name and then reverted by Windows.
        function Initialize-Reverted([string]$Dir) {
            $context = New-TestContext -Json
            $context.CatalogPath = Join-Path $Dir 'catalog'
            $context.ProfilesPath = Join-Path $Dir 'profiles'
            Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Include @('rea.b', 'rea.a', 'rea.ask', 'rea.high') -Yes } | Out-Null
            foreach ($name in 'B', 'A', 'Ask', 'High') { Set-ItemProperty -LiteralPath $Key -Name $name -Value 5 }
        }
    }

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'applies again, as a new run, only the tweaks that Windows reverted' {
        $context = New-TestContext -Json
        $first = @(Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -Yes })[0]
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $documents = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -Yes })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'apply'
        $documents[0].source | Should -Be 'reapply'
        $documents[0].runId | Should -Not -Be $first.runId
        ($documents[0].results | ForEach-Object { "$($_.id)=$($_.status)" }) -join ',' | Should -Be 'test.one=applied'
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
        $status = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context })[0]
        @($status.items | Where-Object { $_.status -ne 'ok' }).Count | Should -Be 0
    }

    It 'shows the plan of a re-apply with -PlanOnly and says when nothing drifted' {
        $context = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Yes } | Out-Null
        $plan = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -PlanOnly })[0]
        $plan.command | Should -Be 'plan'
        $plan.source | Should -Be 'reapply'
        @($plan.items).Count | Should -Be 0
        $human = New-TestContext
        $text = (Invoke-TuneupStatusCommand -Context $human -Reapply 6>&1 | Out-String)
        $text | Should -Match 'Tweaks applied by windows-tuneup:'
        $human.Io.Output -join "`n" | Should -Match 'Nothing to apply again: Windows reverted no tweak.'
        $human.ExitCode | Should -Be 0
    }

    It 'asks before re-applying and leaves out, with a warning, a tweak the catalog no longer has' {
        $context = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $context -Include @('test.three') -Yes } | Out-Null
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        Set-ItemProperty -LiteralPath $Key -Name 'Three' -Value 5
        $catalog = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $catalog | Out-Null
        $source = Get-Content -LiteralPath (Join-Path $Fixtures 'catalog\test.json') -Raw | ConvertFrom-Json
        $source.tweaks = @($source.tweaks | Where-Object { $_.id -ne 'test.three' })
        [System.IO.File]::WriteAllText((Join-Path $catalog 'test.json'), ($source | ConvertTo-Json -Depth 10))
        # The profile that names test.three goes too, or the catalog check would fail first.
        $profiles = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $profiles | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $Fixtures 'profiles') -Filter '*.json' | Where-Object { $_.Name -ne 'extra.json' } |
            Copy-Item -Destination $profiles
        $human = New-TestContext -Answers @('y')
        $human.CatalogPath = $catalog
        $human.ProfilesPath = $profiles
        $text = (Invoke-TuneupStatusCommand -Context $human -Reapply 3>&1 6>&1 | Out-String)
        $text | Should -Match 'Tweak test.three was reverted but is no longer in the catalog'
        $text | Should -Match 'Plan: 1 to apply'
        $human.Io.Output -join "`n" | Should -Match 'Changes to apply: 1\. Apply\? \(y/n\)'
        $human.ExitCode | Should -Be 0
        (Get-ItemProperty -LiteralPath $Key).One | Should -Be 1
        (Get-ItemProperty -LiteralPath $Key).Three | Should -Be 5
    }

    It 'leaves out a tweak that asks first or has high risk, in the order of the run, and says why' {
        $dir = New-ReapplyDefinition
        Initialize-Reverted $dir
        $context = New-TestContext -Json
        $context.CatalogPath = Join-Path $dir 'catalog'
        $context.ProfilesPath = Join-Path $dir 'profiles'
        $document = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -Yes })[0]
        ($document.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' |
            Should -Be 'rea.b=applied/,rea.a=applied/,rea.ask=skipped/needs-confirmation,rea.high=skipped/high-risk-not-requested'
        $values = Get-ItemProperty -LiteralPath $Key
        "$($values.B),$($values.A),$($values.Ask),$($values.High)" | Should -Be '1,1,5,5'
    }

    It 'gives the same plan, in the same order, with -PlanOnly' {
        $dir = New-ReapplyDefinition
        Initialize-Reverted $dir
        $context = New-TestContext -Json
        $context.CatalogPath = Join-Path $dir 'catalog'
        $context.ProfilesPath = Join-Path $dir 'profiles'
        $plan = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -PlanOnly })[0]
        ($plan.items | ForEach-Object { "$($_.id)=$($_.action)/$($_.reason)" }) -join ',' |
            Should -Be 'rea.b=apply/,rea.a=apply/,rea.ask=skip/needs-confirmation,rea.high=skip/high-risk-not-requested'
    }

    It 'lists what it left out when it runs with -Yes and no JSON' {
        $dir = New-ReapplyDefinition
        Initialize-Reverted $dir
        $human = New-TestContext
        $human.CatalogPath = Join-Path $dir 'catalog'
        $human.ProfilesPath = Join-Path $dir 'profiles'
        Invoke-TuneupStatusCommand -Context $human -Reapply -Yes 6>$null
        $text = $human.Io.Output -join "`n"
        $text | Should -Match 'Title rea\.ask: needs confirmation'
        $text | Should -Match 'Title rea\.high: high risk'
        $text | Should -Not -Match 'Title rea\.b'
        $human.ExitCode | Should -Be 0
    }

    It 'with -Include re-applies only the drifted tweaks it names, by name, without the base profile' {
        $dir = New-ReapplyDefinition
        Initialize-Reverted $dir
        $context = New-TestContext -Json
        $context.CatalogPath = Join-Path $dir 'catalog'
        $context.ProfilesPath = Join-Path $dir 'profiles'
        # A base tweak that drifted too, and that it does not name.
        Set-ItemProperty -LiteralPath $Key -Name 'One' -Value 5
        $document = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -Include @('rea.ask', 'rea.a') -Yes })[0]
        $document.source | Should -Be 'reapply'
        ($document.results | ForEach-Object { "$($_.id)=$($_.status)" }) -join ',' | Should -Be 'rea.a=applied,rea.ask=applied'
        $values = Get-ItemProperty -LiteralPath $Key
        "$($values.B),$($values.A),$($values.Ask),$($values.High)" | Should -Be '5,1,1,5'
        $values.One | Should -Be 5
    }

    It 'plans with -Include only the named drifted tweaks, a high-risk one too' {
        $dir = New-ReapplyDefinition
        Initialize-Reverted $dir
        $context = New-TestContext -Json
        $context.CatalogPath = Join-Path $dir 'catalog'
        $context.ProfilesPath = Join-Path $dir 'profiles'
        $plan = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -Include @('rea.high') -PlanOnly })[0]
        ($plan.items | ForEach-Object { "$($_.id)=$($_.action)" }) -join ',' | Should -Be 'rea.high=apply'
    }

    It 'leaves out with a warning a named tweak that did not drift, and refuses an unknown one' {
        $dir = New-ReapplyDefinition
        Initialize-Reverted $dir
        Set-ItemProperty -LiteralPath $Key -Name 'A' -Value 1
        $context = New-TestContext -Json
        $context.CatalogPath = Join-Path $dir 'catalog'
        $context.ProfilesPath = Join-Path $dir 'profiles'
        $document = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $context -Reapply -Include @('rea.b', 'rea.a', 'test.one') -Yes })[0]
        ($document.results | ForEach-Object { $_.id }) -join ',' | Should -Be 'rea.b'
        # Without administrator some tweaks cannot be checked: the warning says so.
        $unverified = 'Tweak {0} was not reverted by Windows, or it cannot be checked without administrator: it is not applied again.'
        @($document.warnings) | Should -Contain ($unverified -f 'rea.a')
        @($document.warnings) | Should -Contain ($unverified -f 'test.one')
        $elevated = New-TestContext -Json
        $elevated.CatalogPath = Join-Path $dir 'catalog'
        $elevated.ProfilesPath = Join-Path $dir 'profiles'
        $elevated.Environment = New-TestEnvironment -IsAdmin $true
        $plan = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $elevated -Reapply -Include @('rea.a') -PlanOnly })[0]
        @($plan.warnings) | Should -Contain 'Tweak rea.a was not reverted by Windows: it is not applied again.'
        $unknown = New-TestContext -Json
        $unknown.CatalogPath = Join-Path $dir 'catalog'
        $unknown.ProfilesPath = Join-Path $dir 'profiles'
        $refusal = @(Get-JsonOutput { Invoke-TuneupStatusCommand -Context $unknown -Reapply -Include @('rea.b', 'no.such') -Yes })[0]
        $refusal.command | Should -Be 'error'
        $refusal.message | Should -Be 'Unknown tweak: no.such'
        $unknown.ExitCode | Should -Be 1
        (Get-ItemProperty -LiteralPath $Key).B | Should -Be 1
        (Get-ItemProperty -LiteralPath $Key).Ask | Should -Be 5
    }

    It 'does not say there is nothing to apply again when some tweaks need administrator to be checked' {
        Mock -ModuleName Tuneup Get-TuneupStatus {
            @([pscustomobject]@{ id = 'x.one'; title = 'One'; status = 'ok'; runId = 'r' }, [pscustomobject]@{ id = 'x.two'; title = 'Two'; status = 'needs-admin'; runId = 'r' })
        }
        $human = New-TestContext
        Invoke-TuneupStatusCommand -Context $human -Reapply 6>$null
        $text = $human.Io.Output -join "`n"
        $text | Should -Match 'Nothing to apply again among what could be checked\. Tweaks that need administrator to be checked: 1'
        $text | Should -Not -Match 'Windows reverted no tweak'
        $human.ExitCode | Should -Be 0
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

    It 'opens the menu when no command is given and says why when it cannot ask' {
        Mock -ModuleName Tuneup Invoke-TuneupMenu { }
        Mock -ModuleName Tuneup Get-TuneupMenuBlockMessage { $null }
        $context = New-TuneupContext
        Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -StateRoot $Root 6>$null
        Should -Invoke Invoke-TuneupMenu -ModuleName Tuneup -Times 1 -Exactly
        Mock -ModuleName Tuneup Get-TuneupMenuBlockMessage { 'The menu cannot ask here' }
        $context = New-TuneupContext
        Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -StateRoot $Root 6>$null
        Should -Invoke Invoke-TuneupMenu -ModuleName Tuneup -Times 1 -Exactly
        $context.ExitCode | Should -Be 1
    }

    It 'runs -Suggest without reading the environment, so a broken system query does not turn it into an error' {
        Mock -ModuleName Tuneup Get-TuneupEnvironment { throw 'WMI is broken' }
        Mock -ModuleName Tuneup Get-TuneupInstalledProgramName { @() }
        Mock -ModuleName Tuneup Get-TuneupUserAppxName { @() }
        Mock -ModuleName Tuneup Test-TuneupSuggestBattery { $false }
        Mock -ModuleName Tuneup Get-TuneupComputerSystem { [pscustomobject]@{ PartOfDomain = $false; TotalPhysicalMemory = [double]16GB } }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $false }
        Mock -ModuleName Tuneup Test-TuneupSuggestMdm { $false }
        Mock -ModuleName Tuneup Get-TuneupSystemDiskMediaType { 'SSD' }
        Mock -ModuleName Tuneup Get-TuneupInstalledMemoryByte { $null }
        Mock -ModuleName Tuneup Get-TuneupOsSupport { [pscustomobject]@{ Build = 26100; Edition = 'Pro'; IsServer = $false } }
        $context = New-TuneupContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -Suggest -StateRoot $Root })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'suggest'
        $context.ExitCode | Should -Be 0
        Should -Invoke Get-TuneupEnvironment -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'prints a saved result as it was written with -ReadResult, without reading the environment' {
        Mock -ModuleName Tuneup Get-TuneupEnvironment { throw 'WMI is broken' }
        $id = [guid]::NewGuid().ToString()
        New-Item -ItemType Directory -Path (Join-Path $Root 'out') -Force | Out-Null
        $text = '{"schemaVersion":1,"command":"apply","toolVersion":"0.1.0","warnings":[],"runId":"20261002-120000"}'
        [System.IO.File]::WriteAllText((Join-Path $Root "out\$id.json"), $text)
        foreach ($json in $true, $false) {
            $context = New-TuneupContext -Json:$json
            $output = @(Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -ReadResult $id -StateRoot $Root 6>$null)
            $output -join "`n" | Should -Be $text
            $context.ExitCode | Should -Be 0
        }
        Should -Invoke Get-TuneupEnvironment -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'gives the reason with the message when a result cannot be read' {
        $id = [guid]::NewGuid().ToString()
        $context = New-TuneupContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -ReadResult $id -StateRoot $Root })
        $documents.Count | Should -Be 1
        $documents[0].command | Should -Be 'error'
        $documents[0].reason | Should -Be 'result-missing'
        $documents[0].message | Should -BeLike "*$id*"
        $context.ExitCode | Should -Be 1
        Test-Path -LiteralPath $Root | Should -BeFalse
    }

    It 'refuses a -ReadResult id that is not a result id' {
        $context = New-TuneupContext -Json
        $documents = @(Get-JsonOutput { Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -ReadResult '..\x-123456' -StateRoot $Root })
        $documents[0].message | Should -Be '-ReadResult takes 8 to 64 letters (A-Z), digits or hyphens, starting with a letter or a digit, such as a GUID. Nothing was read.'
        $documents[0].PSObject.Properties.Name | Should -Not -Contain 'reason'
        $context.ExitCode | Should -Be 1
    }

    It 'looks in the user folder only when not elevated (<Name>)' -TestCases @(
        @{ Name = 'elevated'; Admin = $true; IncludeUser = $false }
        @{ Name = 'not elevated'; Admin = $false; IncludeUser = $true }
    ) {
        param($Admin, $IncludeUser)
        $script:FakeAdmin = $Admin
        $script:ExpectedIncludeUser = $IncludeUser
        Mock -ModuleName Tuneup Test-TuneupAdmin { $script:FakeAdmin }
        Mock -ModuleName Tuneup Read-TuneupResultFile { [pscustomobject]@{ Code = $null; Key = $null; Text = '{}'; Path = 'x'; Folder = 'y' } }
        $context = New-TuneupContext -Json
        Invoke-TuneupCli -Context $context -ScriptRoot (Split-Path $PSScriptRoot -Parent) -ReadResult ([guid]::NewGuid().ToString()) | Should -Be '{}'
        Should -Invoke Read-TuneupResultFile -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { [bool]$IncludeUser -eq $script:ExpectedIncludeUser -and -not $StateRoot }
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

Describe 'An apply that stops before it ends' {
    BeforeAll {
        # What the run saves when the apply fails: test.one was applied, test.two was in progress.
        function Get-FailedResult([bool]$Journaled) {
            $script:stop.Journaled = $Journaled
            $context = New-TestContext
            { Invoke-TuneupApplyCommand -Context $context -Yes 6>$null } | Should -Throw
            $dir = @(Get-ChildItem -LiteralPath (Join-Path $Root 'runs') -Directory)[-1].FullName
            [pscustomobject]@{
                Context = $context
                Result  = (Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw | ConvertFrom-Json)
                Text    = ($context.Io.Output -join "`n")
            }
        }

        # What the run saves when Ctrl+C stops PowerShell itself. Stopping the pipeline of a test would
        # stop the test run, so the function that the apply calls from its finally block is called here.
        function Get-CtrlCResult([bool]$Journaled) {
            $context = New-TestContext
            $plan = @(New-TuneupContextPlan -Context $context -Definition (Import-TuneupContextDefinition -Context $context))
            $run = New-TuneupRun -StateRoot $Root
            $results = New-Object System.Collections.Generic.List[object]
            $results.Add((New-TuneupResult -Item $plan[0] -Status 'applied'))
            $progress = @{ Current = $plan[1].Id; Journaled = $Journaled }
            Save-TuneupStoppedApply -Context $context -Run $run -Plan $plan -Request (New-TuneupApplyRequest -Source 'profiles') `
                -Results $results -Progress $progress -RestorePoint 'not-needed'
            [pscustomobject]@{
                Context = $context
                Result  = (Get-Content -LiteralPath (Join-Path $run.Dir 'result.json') -Raw | ConvertFrom-Json)
                Text    = ($context.Io.Output -join "`n")
            }
        }
    }

    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        # No Ctrl+C trap and so no hint about it: where the tests run with a console of their own (the
        # standard-user job of CI), the hint would be in the text these tests read.
        Mock -ModuleName Tuneup Enable-TuneupInterruptTrap { $null }
        $script:stop = @{ Journaled = $true }
        $stop = $script:stop
        Mock -ModuleName Tuneup Invoke-TuneupPlan {
            $Results.Add((New-TuneupResult -Item $Plan[0] -Status 'applied'))
            $Progress.Current = $Plan[1].Id
            $Progress.Journaled = $stop.Journaled
            throw 'boom'
        }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'with Ctrl+C reports the tweak it cut as failed when it was journaled' {
        $stopped = Get-CtrlCResult $true
        ($stopped.Result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=failed/'
        $stopped.Result.results[1].error | Should -Match '-Undo can restore it'
        $stopped.Text | Should -Match 'Stopped with Ctrl\+C'
        $stopped.Context.ExitCode | Should -Be 2
    }

    It 'with Ctrl+C before the journal entry leaves the tweak out, as interrupted, with nothing to undo' {
        $stopped = Get-CtrlCResult $false
        ($stopped.Result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=skipped/interrupted'
        $stopped.Result.summary.interrupted | Should -Be 1
        $stopped.Result.interrupted | Should -BeTrue
    }

    It 'with any other error does not say it was Ctrl+C, and saves the error' {
        $stopped = Get-FailedResult $true
        ($stopped.Result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=failed/'
        $stopped.Result.results[1].error | Should -Be 'boom; -Undo can restore it'
        $stopped.Result.interrupted | Should -BeFalse
        $stopped.Text | Should -Not -Match 'Ctrl\+C'
        $stopped.Text | Should -Match 'The run stopped because of an error'
    }

    It 'with another error before the journal entry leaves the tweak out as aborted' {
        $stopped = Get-FailedResult $false
        ($stopped.Result.results | ForEach-Object { "$($_.id)=$($_.status)/$($_.reason)" }) -join ',' | Should -Be 'test.one=applied/,test.two=skipped/aborted'
        $stopped.Result.summary.interrupted | Should -Be 0
    }
}

Describe 'The Ctrl+C hint' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupSystemDriveFreeGB { 50 }
        Mock -ModuleName Tuneup Test-TuneupInterruptRequested { $false }
        Mock -ModuleName Tuneup Disable-TuneupInterruptTrap { }
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'says once, through Io, how Ctrl+C and Ctrl+Break work while the trap is on' {
        Mock -ModuleName Tuneup Enable-TuneupInterruptTrap { [pscustomobject]@{ Previous = $false } }
        $context = New-TestContext
        Invoke-TuneupApplyCommand -Context $context -Yes 6>$null
        @($context.Io.Output | Where-Object { $_ -match 'Ctrl\+C stops after the tweak in progress; Ctrl\+Break interrupts at once' }).Count | Should -Be 1
    }

    It 'says nothing without a console to trap, or with -Json' {
        Mock -ModuleName Tuneup Enable-TuneupInterruptTrap { $null }
        $context = New-TestContext
        Invoke-TuneupApplyCommand -Context $context -Yes 6>$null
        $context.Io.Output -join "`n" | Should -Not -Match 'Ctrl'
        Mock -ModuleName Tuneup Enable-TuneupInterruptTrap { [pscustomobject]@{ Previous = $false } }
        $json = New-TestContext -Json
        Get-JsonOutput { Invoke-TuneupApplyCommand -Context $json -Yes } | Out-Null
        $json.Io.Output -join "`n" | Should -Not -Match 'Ctrl'
    }
}
