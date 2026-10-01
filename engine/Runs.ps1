$script:RunIdPattern = '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$'
$script:RunSchemaVersion = 1

function Write-TuneupStateRootWarning {
    [CmdletBinding()]
    param()
    if (Test-TuneupAdmin) { Write-Warning '-StateRoot disables state-folder hardening; use only for testing' }
}

function New-TuneupRun {
    [CmdletBinding()]
    param([string]$StateRoot, [switch]$Machine, [string]$MachineRoot, [string]$UserRoot)
    if ($StateRoot) {
        Write-TuneupStateRootWarning
        $kind = 'custom'
        $root = $StateRoot
    }
    elseif ($Machine) {
        if (-not (Test-TuneupAdmin)) { throw 'The machine state folder can only be written by an elevated process' }
        $kind = 'machine'
        $root = $(if ($MachineRoot) { $MachineRoot } else { Get-TuneupStateRoot -Machine })
        Initialize-TuneupStateRoot -Path $root
    }
    else {
        $kind = 'user'
        $root = $(if ($UserRoot) { $UserRoot } else { Get-TuneupStateRoot })
    }
    $runsDir = Join-Path $root 'runs'
    if ($kind -ne 'machine') { New-Item -ItemType Directory -Path $runsDir -Force -ErrorAction Stop | Out-Null }
    $baseId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $id = $baseId
    $counter = 1
    while (Test-Path -LiteralPath (Join-Path $runsDir $id)) {
        $counter++
        $id = '{0}-{1:D2}' -f $baseId, $counter
    }
    $dir = Join-Path $runsDir $id
    if ($kind -eq 'machine') {
        New-TuneupSecureDirectory -Path $dir -Security (New-TuneupStateSecurity)
        if (-not (Test-TuneupTrustedItem -Path $dir)) { throw (Get-TuneupUntrustedMessage -Path $dir) }
        (New-TuneupSecureFile -Path (Join-Path $dir 'snapshot.jsonl') -Security (New-TuneupStateSecurity -File)).Dispose()
    }
    else {
        New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null
    }
    $userSid = Get-TuneupCurrentUserSid
    $info = [pscustomobject]@{
        schemaVersion = $script:RunSchemaVersion
        userSid       = $userSid
        machine       = ($kind -eq 'machine')
        createdAt     = (Get-Date).ToString('s')
    }
    Save-TuneupJson -Path (Join-Path $dir 'run.json') -Object $info -Root $kind
    [pscustomobject]@{ Id = $id; Dir = $dir; Root = $kind; UserSid = $userSid }
}

function Test-TuneupTrustedRun {
    param([Parameter(Mandatory)][string]$Dir)
    if (-not (Test-TuneupTrustedItem -Path $Dir)) { return $false }
    $journal = Join-Path $Dir 'snapshot.jsonl'
    (-not (Test-Path -LiteralPath $journal)) -or (Test-TuneupTrustedItem -Path $journal)
}

function Test-TuneupRunMarker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$Name, [string]$Root)
    $path = Join-Path $Dir $Name
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    if ((Resolve-TuneupFileRoot -Path $path -Root $Root) -ne 'machine') { return $true }
    if (Test-TuneupTrustedItem -Path $path) { return $true }
    Write-Warning "Ignoring untrusted state file $path"
    $false
}

function Test-TuneupAppxEntryOfOtherUser {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][AllowEmptyString()][string]$CurrentSid)
    if ([string]$Entry.tweak.type -cne 'appx' -or $null -eq $Entry.state) { return $false }
    # No SID saved means that nobody had the app for themselves (or the state is older than the field).
    $sid = $Entry.state.PSObject.Properties['currentUserSid']
    $null -ne $sid -and [bool]$sid.Value -and [string]$sid.Value -ne $CurrentSid
}

function Get-TuneupRunJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)
    $currentSid = Get-TuneupCurrentUserSid
    $entries = New-Object System.Collections.Generic.List[object]
    $skipped = New-Object System.Collections.Generic.List[string]
    $skippedEntries = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl') -Root $Run.Root)) {
        # A user-scope entry holds HKCU values of whoever made the run; restoring it would write them
        # into the current user's hive instead.
        $kind = $null
        if ([string]$entry.tweak.scope -ne 'machine' -and $Run.UserSid -ne $currentSid) {
            $kind = 'user-scope entry'
        } elseif (Test-TuneupAppxEntryOfOtherUser -Entry $entry -CurrentSid $currentSid) {
            # The copy of a Store app belongs to the account that had it: only that account can get it back.
            $kind = 'appx entry'
        }
        if ($null -ne $kind) {
            Write-Warning "Ignoring $kind '$($entry.id)' of run $($Run.Id): it belongs to another user"
            $skipped.Add([string]$entry.id)
            $skippedEntries.Add($entry)
            continue
        }
        $entries.Add($entry)
    }
    [pscustomobject]@{ Entries = $entries.ToArray(); Skipped = $skipped.ToArray(); SkippedEntries = $skippedEntries.ToArray() }
}

function Read-TuneupRunJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)
    (Get-TuneupRunJournal -Run $Run).Entries
}

function Get-TuneupUndoneTweakId {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)
    $text = Read-TuneupStateFile -Path (Join-Path $Run.Dir 'undone-tweaks.txt') -Root $Run.Root -IgnoreUntrusted
    if ($text) { $text -split "`r?`n" | Where-Object { $_ } }
}

function Get-TuneupRunList {
    [CmdletBinding()]
    param([string]$StateRoot, [string]$MachineRoot, [string]$UserRoot)
    if ($StateRoot) {
        Write-TuneupStateRootWarning
        $roots = @([pscustomobject]@{ Kind = 'custom'; Path = $StateRoot })
    }
    else {
        if (-not $MachineRoot) { $MachineRoot = Get-TuneupStateRoot -Machine }
        if (-not $UserRoot) { $UserRoot = Get-TuneupStateRoot }
        $roots = @(
            [pscustomobject]@{ Kind = 'machine'; Path = $MachineRoot },
            [pscustomobject]@{ Kind = 'user'; Path = $UserRoot }
        )
    }
    $currentSid = Get-TuneupCurrentUserSid
    $byKey = @{}
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in $roots) {
        $runsDir = Join-Path $root.Path 'runs'
        if (-not (Test-Path -LiteralPath $runsDir -PathType Container)) { continue }
        if ($root.Kind -eq 'machine') {
            $base = Split-Path -Parent $root.Path
            $untrusted = $null
            if (-not (Test-TuneupBaseFolder -Path $base)) { $untrusted = $base }
            else { $untrusted = @($root.Path, $runsDir) | Where-Object { -not (Test-TuneupTrustedItem -Path $_) } | Select-Object -First 1 }
            if ($untrusted) {
                Write-Warning "Ignoring untrusted state folder $untrusted"
                continue
            }
        }
        foreach ($dir in Get-ChildItem -LiteralPath $runsDir -Directory) {
            if ($dir.Name -cnotmatch $script:RunIdPattern) { continue }
            if ($root.Kind -eq 'machine' -and -not (Test-TuneupTrustedRun -Dir $dir.FullName)) {
                Write-Warning "Ignoring untrusted run $($dir.FullName)"
                continue
            }
            $info = Read-TuneupTrustedJson -Path (Join-Path $dir.FullName 'run.json') -Root $root.Kind
            $userSid = $null
            if ($null -ne $info -and $info.userSid -is [string]) { $userSid = $info.userSid }
            # The user folder only ever holds runs of its own user.
            if ($null -eq $userSid -and $root.Kind -eq 'user') { $userSid = $currentSid }
            # A space sorts before '-', so '20250101-000000' stays ahead of '20250101-000000-02'.
            $key = $dir.Name + ' ' + $root.Kind
            $byKey[$key] = [pscustomobject]@{
                Id      = $dir.Name
                Dir     = $dir.FullName
                Undone  = (Test-TuneupRunMarker -Dir $dir.FullName -Name 'undone.json' -Root $root.Kind)
                Root    = $root.Kind
                UserSid = $userSid
            }
            $keys.Add($key)
        }
    }
    $keys.Sort([System.StringComparer]::Ordinal)
    foreach ($key in $keys) { $byKey[$key] }
}

function Test-TuneupRunHasJournal {
    param([Parameter(Mandatory)][string]$Dir)
    $journal = Join-Path $Dir 'snapshot.jsonl'
    (Test-Path -LiteralPath $journal -PathType Leaf) -and ((Get-Item -LiteralPath $journal -Force).Length -gt 0)
}

function Test-TuneupRunSelectable {
    param([Parameter(Mandatory)]$Run, [switch]$Elevated, [string]$CurrentSid = (Get-TuneupCurrentUserSid))
    if ($Run.Root -ne 'machine') { return ($Run.UserSid -eq $CurrentSid) }
    # Machine runs need elevation; an elevated user takes the ones that are theirs or hold
    # nothing of another user's HKCU.
    if (-not $Elevated) { return $false }
    if ($Run.UserSid -eq $CurrentSid) { return $true }
    try {
        $journal = Get-TuneupRunJournal -Run $Run -WarningAction SilentlyContinue
    }
    catch {
        return $false
    }
    @($journal.Skipped).Count -eq 0
}

function Assert-TuneupRunUndoable {
    param([Parameter(Mandatory)]$Run)
    if ($Run.Root -eq 'machine' -and -not (Test-TuneupAdmin)) {
        throw "Run $($Run.Id) is in the machine state folder; undoing it needs an elevated process"
    }
}

function Resolve-TuneupRun {
    [CmdletBinding()]
    param(
        [string]$StateRoot,
        [string]$MachineRoot,
        [string]$UserRoot,
        [Parameter(Mandatory)][string]$RunId
    )
    $runs = @(Get-TuneupRunList -StateRoot $StateRoot -MachineRoot $MachineRoot -UserRoot $UserRoot |
        Where-Object { Test-TuneupRunHasJournal -Dir $_.Dir })
    if ($RunId -ne 'last') {
        return ($runs | Where-Object { $_.Id -eq $RunId } | Select-Object -First 1)
    }
    $elevated = [bool](Test-TuneupAdmin)
    $currentSid = Get-TuneupCurrentUserSid
    $pending = @($runs | Where-Object { -not $_.Undone })
    for ($i = $pending.Count - 1; $i -ge 0; $i--) {
        if (Test-TuneupRunSelectable -Run $pending[$i] -Elevated:$elevated -CurrentSid $currentSid) { return $pending[$i] }
    }
}
