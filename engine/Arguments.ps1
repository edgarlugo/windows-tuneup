# Commands exclude each other and the options of applying a plan.
$script:CliCommands = @('Status', 'Undo', 'Health', 'Measure', 'List', 'Suggest', 'ReadResult')
$script:CliApplyOptions = @('Profile', 'Include', 'Exclude', 'WhatIf', 'Yes')
# Options that only make sense with one command.
$script:CliDependentOptions = [ordered]@{ Tweak = 'Undo'; Repair = 'Health'; Compare = 'Measure'; IdleSeconds = 'Measure'; Reapply = 'Status' }
# Options of applying that an option of a command brings back: -Status -Reapply applies again what
# drifted, so it takes -Yes and -WhatIf (and still not -Profile, -Include or -Exclude).
$script:CliApplyingOptions = @{ Reapply = @('Yes', 'WhatIf') }

function Get-TuneupArgumentConflict {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Present)
    foreach ($option in $script:CliDependentOptions.Keys) {
        $parent = $script:CliDependentOptions[$option]
        if ($Present -contains $option -and $Present -notcontains $parent) { return "-$option (-$parent)" }
    }
    $commands = @($script:CliCommands | Where-Object { $Present -contains $_ })
    if ($commands.Count -gt 1) { return (($commands | ForEach-Object { "-$_" }) -join ' ') }
    if ($commands.Count -eq 1) {
        $allowed = @($script:CliApplyingOptions.Keys | Where-Object { $Present -contains $_ } | ForEach-Object { $script:CliApplyingOptions[$_] })
        $extra = @($script:CliApplyOptions | Where-Object { $Present -contains $_ -and $allowed -notcontains $_ })
        if ($extra.Count) { return ((@($commands[0]) + $extra | ForEach-Object { "-$_" }) -join ' ') }
    }
}

# The action scripts it loads run as the user, so elevated they run with administrator rights.
function Write-TuneupActionsPathWarning {
    [CmdletBinding()]
    param()
    if (Test-TuneupAdmin) { Write-Warning '-ActionsPath loads functions that run with administrator rights; use only for development and testing' }
}

# powershell.exe writes warnings to standard output, where they would break the JSON document, so
# with -Json they are collected (to go inside it) instead of shown. A warning that several steps
# raise (the -StateRoot one comes from each state read and write) is shown and collected once.
function Invoke-TuneupStepCollectingWarning {
    param(
        [Parameter(Mandatory)][scriptblock]$Step,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Warnings,
        [switch]$Json
    )
    & $Step 3>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) {
            if (-not $Warnings.Contains($_.Message)) {
                $Warnings.Add($_.Message)
                if (-not $Json) { Write-Warning $_.Message }
            }
        } else {
            $_
        }
    }
}
