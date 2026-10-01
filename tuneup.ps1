<#
.SYNOPSIS
    windows-tuneup: goal-based, reversible and measurable Windows optimization.
.EXAMPLE
    .\tuneup.ps1 -Profile base,privacy -WhatIf
.EXAMPLE
    .\tuneup.ps1 -Undo last
.PARAMETER ActionsPath
    Development and testing only: loads action scripts from another folder. They run as the
    current user, with administrator rights when elevated, so use only a folder you trust.
.PARAMETER StateRoot
    Development and testing only: keeps runs and measurements in another folder. That folder
    is not hardened like the machine state folder.
#>
param(
    [Alias('Profile')][string[]]$ProfileName = @(),
    [string[]]$Include = @(),
    [string[]]$Exclude = @(),
    [switch]$WhatIf,
    [switch]$Yes,
    [switch]$Status,
    [string]$Undo,
    [string]$Tweak,
    [switch]$Json,
    [ValidateSet('es', 'en')][string]$Lang,
    [switch]$Force,
    [string]$StateRoot,
    [string]$CatalogPath,
    [string]$ProfilesPath,
    [string]$ActionsPath
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) { $argumentList += "-$($entry.Key)" }
        } else {
            $argumentList += "-$($entry.Key)"
            $argumentList += (@($entry.Value) -join ',')
        }
    }
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @argumentList
    exit $LASTEXITCODE
}

Import-Module (Join-Path $PSScriptRoot 'engine\Tuneup.psm1') -Force
Initialize-TuneupI18n -Root (Join-Path $PSScriptRoot 'i18n') -Lang $Lang

$script:Warnings = New-Object System.Collections.Generic.List[string]

# powershell.exe writes warnings to standard output, where they would break the JSON document,
# so with -Json they are collected and reported inside it instead.
function Invoke-TuneupStep {
    param([Parameter(Mandatory)][scriptblock]$Step)
    if (-not $Json) { return (& $Step) }
    & $Step 3>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) {
            if (-not $script:Warnings.Contains($_.Message)) { $script:Warnings.Add($_.Message) }
        } else {
            $_
        }
    }
}

function Stop-Tuneup {
    param([Parameter(Mandatory)][string]$Message, [string[]]$Details = @())
    Write-TuneupErrorReport -Message $Message -Details $Details -Warnings $script:Warnings.ToArray() -Json:$Json
    exit 1
}

$ProfileName = @(Get-TuneupCleanList ($ProfileName -split ','))
$Include = @(Get-TuneupCleanList ($Include -split ','))
$Exclude = @(Get-TuneupCleanList ($Exclude -split ','))

# A parameter counts as given when it was bound and carries a value (a switch only when it is on).
$present = @()
if ($PSBoundParameters.ContainsKey('ProfileName') -and $ProfileName.Count) { $present += 'Profile' }
if ($PSBoundParameters.ContainsKey('Include') -and $Include.Count) { $present += 'Include' }
if ($PSBoundParameters.ContainsKey('Exclude') -and $Exclude.Count) { $present += 'Exclude' }
if ($PSBoundParameters.ContainsKey('WhatIf') -and $WhatIf) { $present += 'WhatIf' }
if ($PSBoundParameters.ContainsKey('Yes') -and $Yes) { $present += 'Yes' }
if ($PSBoundParameters.ContainsKey('Status') -and $Status) { $present += 'Status' }
if ($PSBoundParameters.ContainsKey('Undo') -and $Undo) { $present += 'Undo' }
if ($PSBoundParameters.ContainsKey('Tweak') -and $Tweak) { $present += 'Tweak' }
$conflict = Get-TuneupArgumentConflict -Present $present
if ($conflict) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.badArgs' -Format $conflict) }

try {
    # Relative paths follow the current PowerShell location, not the process folder that .NET uses.
    $pathApi = $ExecutionContext.SessionState.Path
    if ($StateRoot) { $StateRoot = $pathApi.GetUnresolvedProviderPathFromPSPath($StateRoot) }
    $CatalogPath = $(if ($CatalogPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($CatalogPath) } else { Join-Path $PSScriptRoot 'catalog' })
    $ProfilesPath = $(if ($ProfilesPath) { $pathApi.GetUnresolvedProviderPathFromPSPath($ProfilesPath) } else { Join-Path $PSScriptRoot 'profiles' })
    if ($ActionsPath) {
        # Tests and development only, like -StateRoot: action scripts from another folder.
        $ActionsPath = $pathApi.GetUnresolvedProviderPathFromPSPath($ActionsPath)
        if (-not (Test-Path -LiteralPath $ActionsPath -PathType Container)) {
            $key = $(if (Test-Path -LiteralPath $ActionsPath -PathType Leaf) { 'err.actionsPathNotFolder' } else { 'err.actionsPathMissing' })
            Stop-Tuneup -Message (Get-TuneupText -Key $key -Format $ActionsPath)
        }
        Invoke-TuneupStep { Write-TuneupActionsPathWarning }
        Invoke-TuneupStep { Import-TuneupActionLibrary -Path $ActionsPath }
    }

    $environment = Invoke-TuneupStep { Get-TuneupEnvironment }

    if ($Status) {
        $items = @(Invoke-TuneupStep { Get-TuneupStatus -StateRoot $StateRoot })
        Write-TuneupStatusReport -Items $items -Warnings $script:Warnings.ToArray() -Json:$Json
        exit 0
    }

    if ($Undo) {
        $run = Invoke-TuneupStep { Resolve-TuneupRun -StateRoot $StateRoot -RunId $Undo }
        if (-not $run) {
            $missing = $(if ($Undo -eq 'last') { Get-TuneupText -Key 'undo.none' } else { Get-TuneupText -Key 'err.runNotFound' -Format $Undo })
            Stop-Tuneup -Message $missing
        }
        # Machine-folder runs always need elevation; a -StateRoot run only for its machine tweaks.
        $needsAdmin = ($run.Root -eq 'machine')
        if (-not $needsAdmin) {
            # Its warnings come again, once, from the undo itself.
            $needsAdmin = @(Invoke-TuneupStep { Read-TuneupRunJournal -Run $run -WarningAction SilentlyContinue } | Where-Object { $_.tweak.scope -eq 'machine' }).Count -gt 0
        }
        if ($needsAdmin -and -not $environment.IsAdmin) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.notAdmin') }
        $undoResults = @(Invoke-TuneupStep { Invoke-TuneupUndo -Run $run -TweakId $Tweak })
        Write-TuneupUndoReport -RunId $run.Id -Results $undoResults -Warnings $script:Warnings.ToArray() -Json:$Json
        exit (Get-TuneupUndoExitCode -Results $undoResults)
    }

    if ($environment.IsServer -and -not $Force) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.server') }
    if (($environment.Build -lt 19041 -or $environment.Edition -eq 'Unknown') -and -not $Force) {
        Stop-Tuneup -Message (Get-TuneupText -Key 'err.unsupported')
    }
    # Server supports every policy that Enterprise supports.
    if ($environment.IsServer) { $environment.Edition = 'Enterprise' }

    $catalog = @(Invoke-TuneupStep { Import-TuneupCatalog -Path $CatalogPath })
    $profileSet = @(Invoke-TuneupStep { Import-TuneupProfileSet -Path $ProfilesPath })
    $problems = @(Test-TuneupCatalog -Catalog $catalog) + @(Test-TuneupProfileSet -Profiles $profileSet -Catalog $catalog)
    if ($problems.Count) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.catalog') -Details $problems }

    $plan = @(Invoke-TuneupStep {
        New-TuneupPlan -Catalog $catalog -Profiles $profileSet -ProfileIds $ProfileName `
            -Include $Include -Exclude $Exclude -Environment $environment `
            -TestState { param($tweak) Test-TuneupState -Tweak $tweak }
    })
    $toApply = @($plan | Where-Object { $_.Action -eq 'apply' })

    if ($WhatIf -or -not $toApply.Count) {
        Write-TuneupPlanReport -Plan $plan -Environment $environment -Warnings $script:Warnings.ToArray() -Json:$Json
        exit 0
    }
    $machineChanges = @($toApply | Where-Object { $_.Tweak.scope -eq 'machine' }).Count
    if ($machineChanges -and -not $environment.IsAdmin) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.notAdmin') }
    if (-not $Yes) {
        if ($Json) { Stop-Tuneup -Message (Get-TuneupText -Key 'err.jsonNeedsYes') }
        Write-TuneupPlanReport -Plan $plan -Environment $environment
        $answer = Read-Host (Get-TuneupText -Key 'confirm' -Format $toApply.Count)
        if ($answer -notmatch (Get-TuneupText -Key 'confirm.pattern')) {
            Write-Host (Get-TuneupText -Key 'aborted')
            exit 1
        }
    }

    # Elevated runs go to the protected machine folder; the rest to the user folder (user-scope tweaks only).
    $run = Invoke-TuneupStep { New-TuneupRun -StateRoot $StateRoot -Machine:$environment.IsAdmin }
    Invoke-TuneupStep { Save-TuneupJson -Path (Join-Path $run.Dir 'plan.json') -Root $run.Root -Object @(ConvertTo-TuneupPlanView -Plan $plan) }
    $restorePoint = 'not-needed'
    if ($machineChanges) { $restorePoint = Invoke-TuneupStep { New-TuneupRestorePoint -Description "windows-tuneup $($run.Id)" } }
    $results = @(Invoke-TuneupStep { Invoke-TuneupPlan -Plan $plan -RunDir $run.Dir })
    $report = New-TuneupApplyReport -Run $run -Results $results -RestorePoint $restorePoint -Environment $environment
    $saved = Invoke-TuneupStep { Save-TuneupApplyReport -Run $run -Report $report }
    Write-TuneupApplyReport -Report $report -Warnings $script:Warnings.ToArray() -Json:$Json
    exit (Get-TuneupApplyExitCode -Report $report -ResultNotSaved:(-not $saved))
} catch {
    Stop-Tuneup -Message $_.Exception.Message
}
