BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-TuneupActionLibrary -Path (Join-Path $Fixtures 'actions')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    $script:Contract = [System.IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\json-contract.md'))

    # Every field of a document as a path: a.b for objects, a[].b for the objects of an array.
    function Get-JsonPath($Value, [string]$Prefix = '') {
        if ($null -eq $Value) { return }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            foreach ($property in $Value.PSObject.Properties) {
                $path = $(if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name })
                $path
                Get-JsonPath $property.Value $path
            }
        } elseif ($Value -is [array]) {
            foreach ($item in $Value) { Get-JsonPath $item "$Prefix[]" }
        }
    }
    # The text of one section of the contract (from its ## heading to the next).
    function Get-ContractSection([string]$Name) {
        $match = [regex]::Match($Contract, '(?ms)^## `' + [regex]::Escape($Name) + '`\s*$(.*?)(?=^## |\z)')
        if (-not $match.Success) { throw "docs/json-contract.md has no section ## ``$Name``" }
        $match.Groups[1].Value
    }
    # The fields of a document that its section (or, for the shared ones, the shared section) does not name.
    function Get-UndocumentedPath([string]$Command, $Document) {
        $section = Get-ContractSection $Command
        $shared = Get-ContractSection 'shared'
        foreach ($path in @(Get-JsonPath $Document | Sort-Object -Unique)) {
            if (@('schemaVersion', 'command', 'toolVersion', 'warnings') -contains $path) { $text = $shared; $name = $path }
            elseif ($path -match '(^|\.)environment\.(?<field>\w+)$') { $text = $shared; $name = "environment.$($Matches.field)" }
            elseif ($path -match '(^|\.)preflight\[\]\.(?<field>\w+)$') { $text = $shared; $name = "preflight[].$($Matches.field)" }
            # A health report after a repair has the same fields as the check before it.
            elseif ($Command -eq 'health' -and $path -like 'after.*') { $text = $section; $name = 'before.' + $path.Substring('after.'.Length) }
            else { $text = $section; $name = $path }
            if (-not $text.Contains("``$name``")) { "$Command`: $name" }
        }
    }
    function New-TestContext {
        $context = New-TuneupContext -Json -Io (New-TestIo)
        $context.StateRoot = $script:Root
        $context.CatalogPath = Join-Path $Fixtures 'catalog'
        $context.ProfilesPath = Join-Path $Fixtures 'profiles'
        $context.Environment = New-TestEnvironment -IsAdmin $false
        $context
    }
}

Describe 'docs/json-contract.md' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'state'
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
        Mock -ModuleName Tuneup Get-TuneupPreflight { [pscustomobject]@{ id = 'pending-reboot'; message = 'Windows has a restart pending.' } }
        $context = New-TestContext
        $script:Documents = [ordered]@{}
        $Documents.plan = Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -PlanOnly | ConvertFrom-Json
        $Documents.apply = Invoke-TuneupApplyCommand -Context $context -ProfileIds @('extra') -Yes | ConvertFrom-Json
        $Documents.status = Invoke-TuneupStatusCommand -Context $context | ConvertFrom-Json
        $Documents.undo = Invoke-TuneupUndoCommand -Context $context -RunId 'last' | ConvertFrom-Json
        Invoke-TuneupMeasureCommand -Context $context | Out-Null
        $Documents.measure = Invoke-TuneupMeasureCommand -Context $context -Compare 'last' | ConvertFrom-Json
        $Documents.error = Write-TuneupErrorReport -Message 'x' -Details @('y') -Reason 'result-missing' -Json | ConvertFrom-Json
        $cbs = Join-Path $Fixtures 'cbs'
        $lines = @(Get-Content -LiteralPath (Join-Path $cbs 'sfc-unrepaired.log') -Encoding UTF8) + @(Get-Content -LiteralPath (Join-Path $cbs 'scanhealth-corrupt.log') -Encoding UTF8)
        $scan = New-TuneupHealthScan -Lines $lines -SfcRun ([pscustomobject]@{ ExitCode = 1; Output = 'x' }) -DismRun ([pscustomobject]@{ ExitCode = 0; Output = '' })
        $health = [pscustomobject]@{ schemaVersion = 1; command = 'health'; startedAt = 's'; finishedAt = 'f'; repairRequested = $true; repairRan = $true
            before = $scan; after = $scan; recommendation = 'manual-repair'; rebootRecommended = $false }
        $Documents.health = Write-TuneupHealthReport -Report $health -Json | ConvertFrom-Json
        # One tweak that does not suit the machine, so incompatible has an entry to check.
        $listDefinition = [pscustomobject]@{
            Catalog  = @(Import-TuneupCatalog -Path (Join-Path $Fixtures 'catalog')) + @(New-TestTweak -Id 'test.later' -MinBuild 99999)
            Profiles = @(Import-TuneupProfileSet -Path (Join-Path $Fixtures 'profiles'))
            Problems = [string[]]@()
        }
        $Documents.list = Write-TuneupListReport -Document (Get-TuneupListDocument -Definition $listDefinition -Environment (New-TestEnvironment)) -Json | ConvertFrom-Json
        # Startup entries with every field filled, so every field of the document is checked.
        $startupEntry = New-TuneupStartupEntry -Source 'run-user' -Key 'Steam' -Name 'Steam' -Command '"C:\Games\Steam\steam.exe"' -Path 'C:\Games\Steam\steam.exe'
        $startupEntry.publisher = 'Valve Corp.'
        $startupEntry.running = $true
        $startupEntry.memoryMB = 220
        $startupEntry.cpuSeconds = 10
        $startupEntry.canDisable = $true
        $startupEntry.recommended = $true
        $startupEntry.recommendedReason = 'game-launcher'
        $startupEntry.uninstall = 'winget uninstall --id Valve.Steam --exact'
        $workEntry = New-TuneupStartupEntry -Source 'run-user' -Key 'OneDrive' -Name 'OneDrive'
        $workEntry.canDisable = $true
        $workEntry.notRecommendedReason = 'work-app'
        $protectedEntry = New-TuneupStartupEntry -Source 'service' -Key 'PanGPS' -Name 'PanGPS'
        $protectedEntry.protected = 'vpn'
        $startupDocument = Get-TuneupStartupDocument -Entry @($startupEntry, $workEntry, $protectedEntry) -IsAdmin $false -WorkPc $true
        $Documents.startup = Write-TuneupStartupReport -Document $startupDocument -Warnings @('w') -Json | ConvertFrom-Json
        # Every signal found, so every field of the document has a value.
        Mock -ModuleName Tuneup Get-TuneupInstalledProgramName { 'Steam', 'Git' }
        Mock -ModuleName Tuneup Get-TuneupUserAppxName { 'Microsoft.GamingServices' }
        Mock -ModuleName Tuneup Test-TuneupSuggestBattery { $true }
        Mock -ModuleName Tuneup Get-TuneupComputerSystem { [pscustomobject]@{ PartOfDomain = $true; TotalPhysicalMemory = [double]4GB } }
        Mock -ModuleName Tuneup Get-TuneupInstalledMemoryByte { [double]4GB }
        Mock -ModuleName Tuneup Test-TuneupEntraJoined { $true }
        Mock -ModuleName Tuneup Test-TuneupSuggestMdm { $true }
        Mock -ModuleName Tuneup Get-TuneupSystemDiskMediaType { 'HDD' }
        Mock -ModuleName Tuneup Get-TuneupOsSupport { [pscustomobject]@{ Build = 26100; Edition = 'Pro'; IsServer = $false } }
        $Documents.suggest = Invoke-TuneupSuggestCommand -Context $context | ConvertFrom-Json
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'builds documents with the nested fields that matter, so the check is not empty' {
        $paths = @{}
        foreach ($name in $Documents.Keys) { $paths[$name] = @(Get-JsonPath $Documents[$name]) }
        $paths.plan | Should -Contain 'preflight[].id'
        $paths.plan | Should -Contain 'items[].signOutRequired'
        $paths.plan | Should -Contain 'items[].needsAdmin'
        $paths.apply | Should -Contain 'results[].refused'
        $paths.apply | Should -Contain 'summary.interrupted'
        $paths.apply | Should -Contain 'environment.pendingReboot'
        $paths.undo | Should -Contain 'results[].signOutRequired'
        $paths.undo | Should -Contain 'results[].manual'
        $paths.measure | Should -Contain 'comparison.items[].afterNote'
        $paths.measure | Should -Contain 'measurement.notes.bootDurationMs'
        $paths.health | Should -Contain 'after.componentStore.operationResult'
        $paths.health | Should -Contain 'before.corruptComponents[].files'
        $paths.error | Should -Contain 'details'
        $paths.error | Should -Contain 'reason'
        $Documents.error.reason | Should -Be 'result-missing'
        (Get-ContractSection 'error').Contains('`needs-admin`') | Should -BeTrue
        $paths.list | Should -Contain 'profiles[].needsAdmin'
        $paths.list | Should -Contain 'profiles[].offersStartup'
        $paths.list | Should -Contain 'tweaks[].profiles'
        $paths.list | Should -Contain 'incompatible[].reason'
        $paths.suggest | Should -Contain 'signals[].evidence'
        $paths.suggest | Should -Contain 'suggestions[].signals'
        $paths.suggest | Should -Contain 'questions[].text'
        $paths.startup | Should -Contain 'entries[].recommendedReason'
        $paths.startup | Should -Contain 'entries[].notRecommendedReason'
        $paths.startup | Should -Contain 'summary.protected'
        $paths.startup | Should -Contain 'workPc'
        $paths.startup | Should -Contain 'isAdmin'
    }

    It 'names the values of the startup document and the errors of -Startup' {
        $section = Get-ContractSection 'startup'
        foreach ($value in 'run-user', 'run32-machine', 'runonce-user', 'policy-machine', 'folder-user', 'store-app', 'task', 'service', 'driver',
            'policy', 'windows-component', 'unverified', 'security', 'vpn', 'device', 'updates',
            'updater', 'game-launcher', 'sync-client', 'chat-helper', 'companion-app', 'work-app',
            'run-once', 'unsupported-name', 'unreadable', 'ambiguous', 'session-user', 'needs-admin', 'not-present',
            'err.startupUnknown', 'err.startupFixed', 'err.startupNeedsAdmin', 'err.startupSessionUser', 'err.startupWow64') {
            $section.Contains("``$value``") | Should -BeTrue -Because $value
        }
        $errorSection = Get-ContractSection 'error'
        foreach ($reason in 'session-user', 'needs-admin') { $errorSection.Contains("``$reason``") | Should -BeTrue -Because $reason }
        foreach ($name in 'plan', 'apply') { (Get-ContractSection $name).Contains('`startup`') | Should -BeTrue -Because $name }
        foreach ($name in 'status', 'undo') { (Get-ContractSection $name).Contains('`not-present`') | Should -BeTrue -Because $name }
        foreach ($term in '`-Startup -Json`', '`-Startup -Disable', '`title`, `name`, `key` and `command`') { $Contract.Contains($term) | Should -BeTrue -Because $term }
    }

    It 'catches a field that the page does not name' {
        $document = [pscustomobject]@{ schemaVersion = 1; command = 'error'; toolVersion = '0'; warnings = @(); message = 'x'; details = @(); invented = 1 }
        @(Get-UndocumentedPath 'error' $document) -join ',' | Should -Be 'error: invented'
    }

    It 'names every field of the <Command> document' -TestCases @(
        @{ Command = 'plan' }
        @{ Command = 'apply' }
        @{ Command = 'status' }
        @{ Command = 'undo' }
        @{ Command = 'measure' }
        @{ Command = 'health' }
        @{ Command = 'list' }
        @{ Command = 'suggest' }
        @{ Command = 'startup' }
        @{ Command = 'error' }
    ) {
        param($Command)
        $Documents[$Command].command | Should -Be $Command
        @(Get-UndocumentedPath $Command $Documents[$Command]) -join "`n" | Should -BeNullOrEmpty
    }
}
