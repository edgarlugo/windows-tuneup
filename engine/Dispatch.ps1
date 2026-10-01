# Every tweak type, mapped to its handler. Adding a type takes one entry here plus
# engine/handlers/<Name>.ps1 with Get-<Name>TweakState, Test-<Name>TweakState,
# Set-<Name>TweakDesired, Restore-<Name>TweakState and Test-<Name>TweakDefinition (the catalog
# check of its set block). ReadNeedsAdmin: reading the state needs an elevated process.
$script:TuneupHandlers = [ordered]@{
    registry = [pscustomobject]@{ Name = 'Registry'; ReadNeedsAdmin = $false }
    service  = [pscustomobject]@{ Name = 'Service'; ReadNeedsAdmin = $false }
    task     = [pscustomobject]@{ Name = 'Task'; ReadNeedsAdmin = $false }
}

function Get-TuneupHandlerType {
    foreach ($type in $script:TuneupHandlers.Keys) { $type }
}

function Get-TuneupHandler {
    param([AllowNull()]$Type)
    # Exact, lowercase match: the user-folder rule and the journals compare types the same way.
    if ($Type -isnot [string] -or @(Get-TuneupHandlerType) -cnotcontains $Type) { return $null }
    $script:TuneupHandlers[$Type]
}

function Get-TuneupHandlerName {
    param([Parameter(Mandatory)]$Tweak)
    $handler = Get-TuneupHandler -Type $Tweak.type
    if ($null -eq $handler) { throw "Unsupported tweak type '$($Tweak.type)'" }
    $handler.Name
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
