$script:Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:AdministratorsSid = 'S-1-5-32-544'
$script:TrustedOwnerSids = @('S-1-5-32-544', 'S-1-5-18')
$script:RunIdPattern = '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$'

function Get-TuneupStateRoot {
    param([string]$StateRoot, [switch]$Machine)
    if ($StateRoot) { return $StateRoot }
    $variable = $(if ($Machine) { 'ProgramData' } else { 'LOCALAPPDATA' })
    $base = [Environment]::GetEnvironmentVariable($variable)
    if (-not $base) { throw "Cannot find the state folder: $variable is not set" }
    Join-Path $base 'windows-tuneup'
}

function Get-TuneupRootKind {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    foreach ($kind in 'machine', 'user') {
        try { $root = Get-TuneupStateRoot -Machine:($kind -eq 'machine') } catch { continue }
        $prefix = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        if ($full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $kind }
    }
    'custom'
}

function Resolve-TuneupJournalRoot {
    param([Parameter(Mandatory)][string]$Path, [string]$Root)
    # A path inside a real state folder always gets that folder's rules, whatever the caller says.
    $kind = Get-TuneupRootKind -Path $Path
    if ($kind -ne 'custom') { return $kind }
    if ($Root) { return $Root }
    'custom'
}

function Get-TuneupUntrustedMessage {
    param([Parameter(Mandatory)][string]$Path)
    "State folder $Path is not trusted. Delete it as administrator and run again."
}

function New-TuneupStateSecurity {
    $security = New-Object System.Security.AccessControl.DirectorySecurity
    $security.SetOwner((New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $script:AdministratorsSid))
    $security.SetAccessRuleProtection($true, $false)
    $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $grants = @(
        @('S-1-5-18', 'FullControl'),
        @('S-1-5-32-544', 'FullControl'),
        @('S-1-5-32-545', 'ReadAndExecute')
    )
    foreach ($grant in $grants) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $grant[0]),
            [System.Security.AccessControl.FileSystemRights]$grant[1],
            $inheritance,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $security.AddAccessRule($rule)
    }
    $security
}

function Set-TuneupStateSecurity {
    param([Parameter(Mandatory)][string]$Path)
    $security = New-TuneupStateSecurity
    try {
        $current = Get-Acl -LiteralPath $Path -ErrorAction Stop
        # Windows PowerShell 5.1 Set-Acl also rewrites the SACL (needs SeSecurityPrivilege) when
        # AreAuditRulesProtected differs from the current DACL protection; matching it leaves the SACL alone.
        $security.SetAuditRuleProtection($current.AreAccessRulesProtected, $true)
        Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
    }
    catch {
        throw (Get-TuneupUntrustedMessage -Path $Path)
    }
}

function Set-TuneupTrustedOwner {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $security = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $security.SetOwner((New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $script:AdministratorsSid))
        Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
    }
    catch {
        throw (Get-TuneupUntrustedMessage -Path (Split-Path -Parent $Path))
    }
}

function Test-TuneupTrustedItem {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
        $owner = (Get-Acl -LiteralPath $Path -ErrorAction Stop).GetOwner([System.Security.Principal.SecurityIdentifier])
    }
    catch {
        return $false
    }
    ($null -ne $owner) -and ($script:TrustedOwnerSids -contains $owner.Value)
}

function Test-TuneupTrustedRun {
    param([Parameter(Mandatory)][string]$Dir)
    if (-not (Test-TuneupTrustedItem -Path $Dir)) { return $false }
    $journal = Join-Path $Dir 'snapshot.jsonl'
    (-not (Test-Path -LiteralPath $journal)) -or (Test-TuneupTrustedItem -Path $journal)
}

function Initialize-TuneupStateRoot {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($folder in @($Path, (Join-Path $Path 'runs'))) {
        $created = $false
        if (-not (Test-Path -LiteralPath $folder)) {
            try {
                New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
                $created = $true
            }
            catch {
                if (-not (Test-Path -LiteralPath $folder)) { throw }
            }
        }
        # Never take over a folder someone else made: its owner could swap it for a junction
        # between the check and Set-Acl, and the ACL would land on the junction target.
        if (-not $created -and -not (Test-TuneupTrustedItem -Path $folder)) {
            throw (Get-TuneupUntrustedMessage -Path $folder)
        }
        Set-TuneupStateSecurity -Path $folder
    }
}

function Test-TuneupUserScopedTweak {
    param([AllowNull()]$Tweak)
    if ($null -eq $Tweak -or $null -eq $Tweak.set) { return $false }
    $path = $Tweak.set.path
    ($Tweak.scope -is [string]) -and ($Tweak.scope -ceq 'user') -and
    ($Tweak.type -is [string]) -and ($Tweak.type -ceq 'registry') -and
    ($path -is [string]) -and ($path -match '^HKCU:\\')
}

function New-TuneupRun {
    param([string]$StateRoot, [switch]$Machine, [string]$MachineRoot, [string]$UserRoot)
    if ($StateRoot) {
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
    New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null
    if ($kind -eq 'machine') {
        Set-TuneupStateSecurity -Path $dir
        $journal = Join-Path $dir 'snapshot.jsonl'
        [System.IO.File]::Open($journal, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write).Dispose()
        Set-TuneupTrustedOwner -Path $journal
    }
    [pscustomobject]@{ Id = $id; Dir = $dir; Root = $kind }
}

function Save-TuneupJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    [System.IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)
}

function Add-TuneupJournalEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Tweak,
        [Parameter(Mandatory)][AllowNull()]$State,
        [ValidateSet('machine', 'user', 'custom')][string]$Root
    )
    if ((Resolve-TuneupJournalRoot -Path $Path -Root $Root) -eq 'user' -and -not (Test-TuneupUserScopedTweak -Tweak $Tweak)) {
        throw "Cannot journal machine-scope tweak '$($Tweak.id)' in the user state folder"
    }
    $entry = [pscustomobject]@{ id = $Tweak.id; tweak = $Tweak; state = $State }
    $line = ConvertTo-Json -InputObject $entry -Depth 10 -Compress
    [System.IO.File]::AppendAllText($Path, $line + [Environment]::NewLine, $script:Utf8NoBom)
}

function Read-TuneupJournal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('machine', 'user', 'custom')][string]$Root
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $kind = Resolve-TuneupJournalRoot -Path $Path -Root $Root
    if ($kind -eq 'machine' -and -not (Test-TuneupTrustedRun -Dir (Split-Path -Parent $Path))) {
        throw "Journal $Path is not trusted"
    }
    $lines = [System.IO.File]::ReadAllLines($Path, $script:Utf8NoBom)
    $lastIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim()) { $lastIndex = $i }
    }
    for ($i = 0; $i -le $lastIndex; $i++) {
        if (-not $lines[$i].Trim()) { continue }
        try {
            $entry = $lines[$i] | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            if ($i -eq $lastIndex) {
                Write-Warning "Ignoring incomplete last journal line in $Path"
                return
            }
            throw "Journal $Path is corrupt at line $($i + 1)"
        }
        if ($kind -eq 'user' -and -not (Test-TuneupUserScopedTweak -Tweak $entry.tweak)) {
            Write-Warning "Ignoring machine-scope entry '$($entry.id)' in user journal $Path"
            continue
        }
        $entry
    }
}

function Get-TuneupRunList {
    [CmdletBinding()]
    param([string]$StateRoot, [string]$MachineRoot, [string]$UserRoot)
    if ($StateRoot) {
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
    $byKey = @{}
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in $roots) {
        $runsDir = Join-Path $root.Path 'runs'
        if (-not (Test-Path -LiteralPath $runsDir -PathType Container)) { continue }
        if ($root.Kind -eq 'machine') {
            $untrusted = @($root.Path, $runsDir) | Where-Object { -not (Test-TuneupTrustedItem -Path $_) } | Select-Object -First 1
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
            # A space sorts before '-', so '20250101-000000' stays ahead of '20250101-000000-02'.
            $key = $dir.Name + ' ' + $root.Kind
            $byKey[$key] = [pscustomobject]@{
                Id     = $dir.Name
                Dir    = $dir.FullName
                Undone = (Test-Path -LiteralPath (Join-Path $dir.FullName 'undone.json'))
                Root   = $root.Kind
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

function Resolve-TuneupRun {
    param(
        [string]$StateRoot,
        [string]$MachineRoot,
        [string]$UserRoot,
        [Parameter(Mandatory)][string]$RunId
    )
    $runs = @(Get-TuneupRunList -StateRoot $StateRoot -MachineRoot $MachineRoot -UserRoot $UserRoot |
        Where-Object { Test-TuneupRunHasJournal -Dir $_.Dir })
    if ($RunId -eq 'last') {
        return ($runs | Where-Object { -not $_.Undone } | Select-Object -Last 1)
    }
    $runs | Where-Object { $_.Id -eq $RunId } | Select-Object -First 1
}
