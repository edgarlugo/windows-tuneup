function Get-TaskTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $task = Get-ScheduledTask -TaskPath $Tweak.set.path -TaskName $Tweak.set.name -ErrorAction SilentlyContinue
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
    if ($Enabled) {
        Enable-ScheduledTask -TaskPath $Tweak.set.path -TaskName $Tweak.set.name -ErrorAction Stop | Out-Null
    } else {
        Disable-ScheduledTask -TaskPath $Tweak.set.path -TaskName $Tweak.set.name -ErrorAction Stop | Out-Null
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
