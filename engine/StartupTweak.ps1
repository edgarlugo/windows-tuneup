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

# The StartupApproved key that keeps the choice of Task Manager for the entries of a source.
$script:StartupApprovedSubkeys = @{ 'run-user' = 'Run'; 'run-machine' = 'Run'; 'run32-machine' = 'Run32'; 'folder-user' = 'StartupFolder'; 'folder-machine' = 'StartupFolder' }

# The problems of the set block of a startup tweak; nothing when it says where to turn the entry off. What a
# registry tweak writes is pinned: the value of the entry (its key) in the StartupApproved key of its source
# and scope, or the State of its task in SystemAppData (<package family>\<task>, its key); a task and a
# service must pass the checks of their handlers.
function Test-TuneupStartupTweakSet {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    $source = [string]$Tweak.startup.source
    $key = [string]$Tweak.startup.key
    switch ($Tweak.type) {
        'registry' {
            if ($source -ceq 'store-app') {
                $expected = "$($script:StoreTaskRoot)\$key"
                $name = 'State'
            } else {
                $subkey = $script:StartupApprovedSubkeys[$source]
                $expected = $(if ($subkey) { "$($script:StartupApprovedRoot[[string]$Tweak.scope])\$subkey" } else { $null })
                $name = $key
            }
            if (-not $expected -or -not [string]::Equals([string]$set.path, $expected, [System.StringComparison]::OrdinalIgnoreCase)) { "not the key $expected" }
            if (-not [string]::Equals([string]$set.name, $name, [System.StringComparison]::OrdinalIgnoreCase)) { "not the value $name" }
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

# Whether a tweak is one that -Startup -Disable built: an id of -Startup and what it turns off.
function Test-TuneupStartupTweak {
    param([AllowNull()]$Tweak)
    $null -ne $Tweak -and $null -ne $Tweak.PSObject.Properties['startup'] -and (Test-TuneupStartupId -Id ([string]$Tweak.id))
}

# Whether the entry a startup tweak turned off is still there: the value of its Run key, the file of its
# startup folder, the key of its Store task (gone with the app), its scheduled task or its service. Once it
# was uninstalled there is nothing to check or to give back: -Status says not-present (never drift) and
# -Undo leaves it as it is, without making keys or values for something that no longer exists.
function Test-TuneupStartupTweakPresent {
    param([Parameter(Mandatory)]$Tweak)
    $source = [string]$Tweak.startup.source
    $key = [string]$Tweak.startup.key
    switch -Regex ($source) {
        '^(run|run32)-' {
            $run = @($script:StartupRunKeys | Where-Object { $_.Source -ceq $source })[0]
            if ($null -eq $run -or -not (Test-Path -LiteralPath $run.Path)) { return $false }
            $item = Get-Item -LiteralPath $run.Path -ErrorAction Stop
            try { return [bool](@($item.GetValueNames()) -contains $key) } finally { $item.Close() }
        }
        '^folder-' {
            $folder = @($script:StartupFolders | Where-Object { $_.Source -ceq $source })[0]
            $path = $(if ($null -ne $folder) { Get-TuneupStartupFolderPath -Name $folder.Folder } else { $null })
            return [bool]($path -and (Test-Path -LiteralPath (Join-Path $path $key) -PathType Leaf))
        }
        '^store-app$' { return [bool](Test-Path -LiteralPath ([string]$Tweak.set.path)) }
        '^task$' { return $null -ne (Get-TuneupScheduledTask -Tweak $Tweak) }
        '^service$' { return [bool](Get-ServiceTweakState -Tweak $Tweak).present }
    }
    $true
}