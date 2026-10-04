# -Startup -Disable (design, section 15.7): each chosen entry becomes a tweak of a type that already exists
# (registry for StartupApproved and for the State of a Store task, task, service), built from what was
# found. The journal keeps the whole tweak with its state before the change, and -Undo and -Status work
# from the journal, so turning an entry off is undone, checked and reported by the same handlers as a
# catalog tweak. These tweaks are never in the catalog and never go through its checks.

$script:StartupTweakSources = [ordered]@{
    registry = 'https://learn.microsoft.com/windows/win32/setupapi/run-and-runonce-registry-keys'
    store    = 'https://learn.microsoft.com/uwp/api/windows.applicationmodel.startuptaskstate'
    task     = 'https://learn.microsoft.com/powershell/module/scheduledtasks/disable-scheduledtask'
    service  = 'https://learn.microsoft.com/windows-server/administration/windows-commands/sc-config'
}
# StartupTaskState.DisabledByUser: what Settings writes when a person turns a Store app off at startup; the
# app cannot turn itself on again.
$script:StoreTaskDisabledByUser = 1

# How an entry of a source is turned off: registry (StartupApproved), store, task or service; nothing for a
# source that is never turned off (run-once, policy, driver).
function Get-TuneupStartupKind {
    param([Parameter(Mandatory)][string]$Source)
    switch -Regex ($Source) {
        '^(run|run32)-' { return 'registry' }
        '^folder-' { return 'registry' }
        '^store-app$' { return 'store' }
        '^task$' { return 'task' }
        '^service$' { return 'service' }
    }
}

# 03 00 00 00 and the FILETIME (UTC) of when it was turned off: what Task Manager writes (design, 15.3).
function New-TuneupStartupApprovedValue {
    param([Parameter(Mandatory)][datetime]$DisabledAt)
    $bytes = New-Object byte[] 12
    $bytes[0] = 3
    [BitConverter]::GetBytes([int64]$DisabledAt.ToFileTimeUtc()).CopyTo($bytes, 4)
    , $bytes
}

# The problems of the set block of a startup tweak; nothing when it says where to turn the entry off. A
# registry value must be in the hive of the scope of its entry (the user's under HKCU, the machine's under
# HKLM), and a task and a service must pass the checks of their handlers.
function Test-TuneupStartupTweakSet {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    switch ($Tweak.type) {
        'registry' {
            $hive = $(if ($Tweak.scope -ceq 'user') { 'HKCU' } else { 'HKLM' })
            if ([string]$set.path -cnotmatch "^${hive}:\\.+") { "no registry key under $hive" }
            if ([string]::IsNullOrEmpty([string]$set.name)) { 'no registry value name' }
        }
        'task' { Test-TaskTweakDefinition -Tweak $Tweak }
        'service' { Test-ServiceTweakDefinition -Tweak $Tweak }
    }
}

# The tweak that turns one entry off. A StartupApproved value always gets a new date, as Task Manager
# writes, and compare = startupApproved: the check reads any odd first byte as off (an entry already off is
# left out as already applied, and one turned off again by Task Manager is not reverted), while the state
# keeps the exact bytes for -Undo. A Store task that is already off asks for the State it has. The texts
# are the name of the entry and why, in the language of the run (both fields: the journal keeps them, and
# the code of the tool cannot hold accents).
function ConvertTo-TuneupStartupTweak {
    param([Parameter(Mandatory)]$Entry, [datetime]$DisabledAt = [datetime]::UtcNow)
    $kind = Get-TuneupStartupKind -Source ([string]$Entry.source)
    if ((Get-TuneupStartupFixedReason -Entry $Entry) -or -not $kind) { throw "Startup entry $($Entry.id) cannot be turned off" }
    $target = $Entry.target
    switch ($kind) {
        'registry' {
            $type = 'registry'
            $value = New-TuneupStartupApprovedValue -DisabledAt $DisabledAt
            $set = [pscustomobject]@{
                path    = [string]$target.ApprovedPath
                name    = [string]$target.ApprovedName
                kind    = 'Binary'
                value   = [int[]]@($value)
                compare = 'startupApproved'
            }
        }
        'store' {
            $type = 'registry'
            $state = $(if ($Entry.enabled) { $script:StoreTaskDisabledByUser } else { [int]$target.StoreState })
            $set = [pscustomobject]@{ path = [string]$target.StoreKeyPath; name = 'State'; kind = 'DWord'; value = $state }
        }
        'task' {
            $type = 'task'
            $set = [pscustomobject]@{ path = [string]$target.TaskPath; name = [string]$target.TaskName; state = 'Disabled' }
        }
        'service' {
            $type = 'service'
            $set = [pscustomobject]@{ name = [string]$target.ServiceName; startType = 'Manual'; stop = $false }
        }
    }
    $why = Get-TuneupText -Key "startup.why.$kind" -Format (Get-TuneupText -Key "startup.source.$($Entry.source)")
    $tweak = [pscustomobject]@{
        id             = [string]$Entry.id
        title          = [pscustomobject]@{ es = [string]$Entry.name; en = [string]$Entry.name }
        why            = [pscustomobject]@{ es = $why; en = $why }
        risk           = 'low'
        ask            = $false
        os             = [pscustomobject]@{ families = @('10', '11'); minBuild = 19041; editions = @('Home', 'Pro', 'Enterprise', 'Education') }
        type           = $type
        scope          = [string]$Entry.scope
        set            = $set
        rebootRequired = $false
        sources        = @($script:StartupTweakSources[$kind])
        startup        = [pscustomobject]@{ source = [string]$Entry.source; key = [string]$Entry.key }
    }
    $problems = @(Test-TuneupStartupTweakSet -Tweak $tweak)
    if ($problems.Count) { throw "Startup entry $($Entry.id) cannot be turned off: $($problems -join '; ')" }
    $tweak
}
