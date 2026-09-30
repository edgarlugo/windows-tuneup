function Get-TuneupHandlerName {
    param([Parameter(Mandatory)]$Tweak)
    switch ($Tweak.type) {
        'registry' { 'Registry' }
        'service' { 'Service' }
        'task' { 'Task' }
        default { throw "Unsupported tweak type '$($Tweak.type)'" }
    }
}

function Get-TuneupState {
    param([Parameter(Mandatory)]$Tweak)
    & "Get-$(Get-TuneupHandlerName -Tweak $Tweak)TweakState" -Tweak $Tweak
}

function Test-TuneupState {
    param([Parameter(Mandatory)]$Tweak)
    & "Test-$(Get-TuneupHandlerName -Tweak $Tweak)TweakState" -Tweak $Tweak
}

function Set-TuneupDesired {
    param([Parameter(Mandatory)]$Tweak)
    & "Set-$(Get-TuneupHandlerName -Tweak $Tweak)TweakDesired" -Tweak $Tweak
}

function Restore-TuneupState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    & "Restore-$(Get-TuneupHandlerName -Tweak $Tweak)TweakState" -Tweak $Tweak -State $State
}
