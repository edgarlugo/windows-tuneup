function Get-TuneupScheduledTask {
    param([Parameter(Mandatory)]$Tweak)
    # Get-ScheduledTask treats names and paths as wildcards, so keep only the exact match.
    $found = @(Get-ScheduledTask -TaskPath $Tweak.set.path -TaskName $Tweak.set.name -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -eq $Tweak.set.name -and $_.TaskPath -eq $Tweak.set.path })
    if ($found.Count -eq 0) { return $null }
    $found[0]
}

function Get-TaskTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $task = Get-TuneupScheduledTask -Tweak $Tweak
    if ($null -eq $task) { return [pscustomobject]@{ present = $false; enabled = $null } }
    [pscustomobject]@{ present = $true; enabled = ([string]$task.State -ne 'Disabled') }
}

function Test-TaskTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-TaskTweakState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ($state.enabled -eq ($Tweak.set.state -eq 'Enabled')) { return 'applied' }
    'not-applied'
}

function Set-TuneupTaskEnabled {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)][bool]$Enabled)
    $task = Get-TuneupScheduledTask -Tweak $Tweak
    if ($null -eq $task) { throw "Scheduled task $($Tweak.set.path)$($Tweak.set.name) not found" }
    if ($Enabled) {
        Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
    } else {
        Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
    }
}

function Set-TaskTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    Set-TuneupTaskEnabled -Tweak $Tweak -Enabled ($Tweak.set.state -eq 'Enabled')
}

function Restore-TaskTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    Set-TuneupTaskEnabled -Tweak $Tweak -Enabled ([bool]$State.enabled)
}
