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

# What a handler's Set or Restore can report besides doing its work. The type name marks it, so
# anything else a handler or a cmdlet prints is never mistaken for it.
function New-TuneupOutcome {
    param([switch]$Partial, [string]$Detail, [switch]$RebootRequired, [string]$Reason)
    if ($Partial -and -not $Detail) { throw 'A partial outcome needs a detail' }
    [pscustomobject]@{
        PSTypeName     = 'Tuneup.Outcome'
        partial        = [bool]$Partial
        detail         = $(if ($Detail) { $Detail } else { $null })
        rebootRequired = [bool]$RebootRequired
        reason         = $(if ($Reason) { $Reason } else { $null })
    }
}

function Get-TuneupOutcome {
    param([AllowNull()][AllowEmptyCollection()][object[]]$Output = @())
    $merged = [pscustomobject]@{ partial = $false; detail = $null; rebootRequired = $false; reason = $null }
    foreach ($item in @($Output)) {
        if ($null -eq $item -or $item.PSObject.TypeNames -notcontains 'Tuneup.Outcome') { continue }
        if ($item.partial) { $merged.partial = $true }
        if ($item.rebootRequired) { $merged.rebootRequired = $true }
        if ($item.reason) { $merged.reason = $item.reason }
        if ($item.detail) {
            $merged.detail = $(if ($merged.detail) { "$($merged.detail); $($item.detail)" } else { $item.detail })
        }
    }
    $merged
}
