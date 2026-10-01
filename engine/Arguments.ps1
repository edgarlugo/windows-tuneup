# Commands exclude each other and the options of applying a plan.
$script:CliCommands = @('Status', 'Undo', 'Health', 'Measure')
$script:CliApplyOptions = @('Profile', 'Include', 'Exclude', 'WhatIf', 'Yes')
# Options that only make sense with one command.
$script:CliDependentOptions = [ordered]@{ Tweak = 'Undo'; Repair = 'Health'; Compare = 'Measure'; IdleSeconds = 'Measure' }

function Get-TuneupArgumentConflict {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Present)
    foreach ($option in $script:CliDependentOptions.Keys) {
        $parent = $script:CliDependentOptions[$option]
        if ($Present -contains $option -and $Present -notcontains $parent) { return "-$option (-$parent)" }
    }
    $commands = @($script:CliCommands | Where-Object { $Present -contains $_ })
    if ($commands.Count -gt 1) { return (($commands | ForEach-Object { "-$_" }) -join ' ') }
    if ($commands.Count -eq 1) {
        $extra = @($script:CliApplyOptions | Where-Object { $Present -contains $_ })
        if ($extra.Count) { return ((@($commands[0]) + $extra | ForEach-Object { "-$_" }) -join ' ') }
    }
}
