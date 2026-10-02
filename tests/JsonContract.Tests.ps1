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
        $Documents.error = Write-TuneupErrorReport -Message 'x' -Details @('y') -Json | ConvertFrom-Json
        $cbs = Join-Path $Fixtures 'cbs'
        $lines = @(Get-Content -LiteralPath (Join-Path $cbs 'sfc-unrepaired.log') -Encoding UTF8) + @(Get-Content -LiteralPath (Join-Path $cbs 'scanhealth-corrupt.log') -Encoding UTF8)
        $scan = New-TuneupHealthScan -Lines $lines -SfcRun ([pscustomobject]@{ ExitCode = 1; Output = 'x' }) -DismRun ([pscustomobject]@{ ExitCode = 0; Output = '' })
        $health = [pscustomobject]@{ schemaVersion = 1; command = 'health'; startedAt = 's'; finishedAt = 'f'; repairRequested = $true; repairRan = $true
            before = $scan; after = $scan; recommendation = 'manual-repair'; rebootRecommended = $false }
        $Documents.health = Write-TuneupHealthReport -Report $health -Json | ConvertFrom-Json
    }

    AfterAll {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'builds documents with the nested fields that matter, so the check is not empty' {
        $paths = @{}
        foreach ($name in $Documents.Keys) { $paths[$name] = @(Get-JsonPath $Documents[$name]) }
        $paths.plan | Should -Contain 'preflight[].id'
        $paths.plan | Should -Contain 'items[].signOutRequired'
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
        @{ Command = 'error' }
    ) {
        param($Command)
        $Documents[$Command].command | Should -Be $Command
        @(Get-UndocumentedPath $Command $Documents[$Command]) -join "`n" | Should -BeNullOrEmpty
    }
}
