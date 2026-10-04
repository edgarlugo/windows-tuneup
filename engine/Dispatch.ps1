# Every tweak type, mapped to its handler. Adding a type takes one entry here plus
# engine/handlers/<Name>.ps1 with Get-<Name>TweakState, Test-<Name>TweakState,
# Set-<Name>TweakDesired, Restore-<Name>TweakState and Test-<Name>TweakDefinition (the catalog
# check of its set block). ReadNeedsAdmin: reading the state needs an elevated process.
# The contract of Get (handlers and action scripts alike): its state holds everything that Restore
# gives back. -Undo skips Restore when Get reads the same state that was journaled before Set (the
# tweak is reported restored, reason unchanged), and the executor believes a refusal on the same
# comparison: a change that Get does not see would never be undone.
$script:TuneupHandlers = [ordered]@{
    registry   = [pscustomobject]@{ Name = 'Registry'; ReadNeedsAdmin = $false }
    service    = [pscustomobject]@{ Name = 'Service'; ReadNeedsAdmin = $false }
    task       = [pscustomobject]@{ Name = 'Task'; ReadNeedsAdmin = $false }
    appx       = [pscustomobject]@{ Name = 'Appx'; ReadNeedsAdmin = $true }
    capability = [pscustomobject]@{ Name = 'Capability'; ReadNeedsAdmin = $true }
    feature    = [pscustomobject]@{ Name = 'Feature'; ReadNeedsAdmin = $true }
    powercfg   = [pscustomobject]@{ Name = 'Powercfg'; ReadNeedsAdmin = $false }
    action     = [pscustomobject]@{ Name = 'Action'; ReadNeedsAdmin = $false }
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
# anything else a handler or a cmdlet prints is never mistaken for it. Refused: Set looked at the
# system and chose not to change anything (for example, files that only live in the cloud); the
# tweak is reported as skipped with that reason instead of failed. The contract: a refusal is only
# valid before anything was changed. The executor reads the state again and compares it with the
# journaled one; if it differs, the refusal is not believed (the tweak fails and stays undoable).
# That comparison, like the one -Undo makes before Restore, only sees what Get reads (see above).
function New-TuneupOutcome {
    param([switch]$Partial, [string]$Detail, [switch]$RebootRequired, [string]$Reason, [switch]$Refused)
    if ($Partial -and -not $Detail) { throw 'A partial outcome needs a detail' }
    if ($Refused -and (-not $Reason -or -not $Detail)) { throw 'A refused outcome needs a reason and a detail' }
    if ($Refused -and $Partial) { throw 'An outcome cannot be refused and partial: a refusal changes nothing' }
    [pscustomobject]@{
        PSTypeName     = 'Tuneup.Outcome'
        partial        = [bool]$Partial
        detail         = $(if ($Detail) { $Detail } else { $null })
        rebootRequired = [bool]$RebootRequired
        reason         = $(if ($Reason) { $Reason } else { $null })
        refused        = [bool]$Refused
    }
}

function Get-TuneupOutcome {
    param([AllowNull()][AllowEmptyCollection()][object[]]$Output = @())
    $merged = [pscustomobject]@{ partial = $false; detail = $null; rebootRequired = $false; reason = $null; refused = $false }
    foreach ($item in @($Output)) {
        if ($null -eq $item -or $item.PSObject.TypeNames -notcontains 'Tuneup.Outcome') { continue }
        if ($item.partial) { $merged.partial = $true }
        if ($item.PSObject.Properties['refused'] -and $item.refused) { $merged.refused = $true }
        if ($item.rebootRequired) { $merged.rebootRequired = $true }
        if ($item.reason) { $merged.reason = $item.reason }
        if ($item.detail) {
            $merged.detail = $(if ($merged.detail) { "$($merged.detail); $($item.detail)" } else { $item.detail })
        }
    }
    $merged
}

function Test-TuneupHandlerReadNeedsAdmin {
    param([Parameter(Mandatory)]$Tweak)
    $handler = Get-TuneupHandler -Type $Tweak.type
    ($null -ne $handler) -and [bool]$handler.ReadNeedsAdmin
}
