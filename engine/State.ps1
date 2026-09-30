$script:Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:StateOwnerSid = 'S-1-5-32-544'
$script:TrustedSids = @('S-1-5-18', 'S-1-5-32-544')
$script:UsersSid = 'S-1-5-32-545'
$script:OwnerRightsSid = 'S-1-3-4'
$script:RunIdPattern = '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$'
$script:RunSchemaVersion = 1
# Any of these granted to an untrusted SID lets it change or replace a state file.
$script:WriteRights = [int][System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, DeleteSubdirectoriesAndFiles, WriteAttributes, Delete, ChangePermissions, TakeOwnership'
$script:WriteRights = $script:WriteRights -bor 0x10000000 -bor 0x40000000
$script:NativeFileSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace WindowsTuneup {
    public static class NativeFile {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileInformation {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation information);

        public static uint GetLinkCount(SafeFileHandle handle) {
            FileInformation information;
            if (!GetFileInformationByHandle(handle, out information)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return information.NumberOfLinks;
        }
    }
}
'@

function Get-TuneupStateRoot {
    param([string]$StateRoot, [switch]$Machine)
    if ($StateRoot) { return $StateRoot }
    $folder = $(if ($Machine) { 'CommonApplicationData' } else { 'LocalApplicationData' })
    $base = [Environment]::GetFolderPath($folder)
    if (-not $base) { throw "Cannot find the state folder: $folder is not available" }
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

function Resolve-TuneupFileRoot {
    param([Parameter(Mandatory)][string]$Path, [string]$Root)
    if ($Root -and @('machine', 'user', 'custom') -notcontains $Root) { throw "Unknown state root '$Root'" }
    # A path inside a real state folder always gets that folder's rules, whatever the caller says.
    $kind = Get-TuneupRootKind -Path $Path
    if ($kind -ne 'custom') { return $kind }
    if ($Root) { return $Root }
    'custom'
}

function Get-TuneupCurrentUserSid {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Get-TuneupUntrustedMessage {
    param([Parameter(Mandatory)][string]$Path)
    "State folder $Path is not trusted. Delete it as administrator and run again."
}

function New-TuneupStateSecurity {
    param(
        [switch]$File,
        [string]$OwnerSid = $script:StateOwnerSid,
        [string[]]$TrustedSids = $script:TrustedSids
    )
    if ($File) {
        $security = New-Object System.Security.AccessControl.FileSecurity
        $inheritance = [System.Security.AccessControl.InheritanceFlags]::None
    }
    else {
        $security = New-Object System.Security.AccessControl.DirectorySecurity
        $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    }
    $security.SetOwner((New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $OwnerSid))
    $security.SetAccessRuleProtection($true, $false)
    $grants = New-Object System.Collections.Generic.List[object]
    foreach ($sid in $TrustedSids) { $grants.Add([pscustomobject]@{ Sid = $sid; Rights = 'FullControl' }) }
    $grants.Add([pscustomobject]@{ Sid = $script:UsersSid; Rights = 'ReadAndExecute' })
    # OWNER RIGHTS replaces the owner's implicit WRITE_DAC, so owning an item grants nothing extra.
    $grants.Add([pscustomobject]@{ Sid = $script:OwnerRightsSid; Rights = 'ReadAndExecute' })
    foreach ($grant in $grants) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $grant.Sid),
            [System.Security.AccessControl.FileSystemRights]$grant.Rights,
            $inheritance,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $security.AddAccessRule($rule)
    }
    $security
}

function Set-TuneupStateSecurity {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$OwnerSid = $script:StateOwnerSid,
        [string[]]$TrustedSids = $script:TrustedSids
    )
    $security = New-TuneupStateSecurity -OwnerSid $OwnerSid -TrustedSids $TrustedSids
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

function New-TuneupSecureDirectory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Security)
    [System.IO.Directory]::CreateDirectory($Path, $Security) | Out-Null
}

function New-TuneupSecureFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Security)
    New-Object System.IO.FileStream -ArgumentList @(
        $Path,
        [System.IO.FileMode]::CreateNew,
        [System.Security.AccessControl.FileSystemRights]::Write,
        [System.IO.FileShare]::None,
        4096,
        [System.IO.FileOptions]::None,
        $Security
    )
}

function Test-TuneupTrustedSecurity {
    param([Parameter(Mandatory)]$Security, [string[]]$TrustedSids = $script:TrustedSids)
    $owner = $Security.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($null -eq $owner -or $TrustedSids -notcontains $owner.Value) { return $false }
    foreach ($rule in $Security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
        if ($TrustedSids -contains $rule.IdentityReference.Value) { continue }
        if (([int]$rule.FileSystemRights -band $script:WriteRights) -ne 0) { return $false }
    }
    $true
}

function Test-TuneupTrustedItem {
    param([Parameter(Mandatory)][string]$Path, [string[]]$TrustedSids = $script:TrustedSids)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
        if (-not $item.PSIsContainer -and $item.LinkType -eq 'HardLink') { return $false }
        $security = Get-Acl -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        return $false
    }
    Test-TuneupTrustedSecurity -Security $security -TrustedSids $TrustedSids
}

function Test-TuneupTrustedRun {
    param([Parameter(Mandatory)][string]$Dir)
    if (-not (Test-TuneupTrustedItem -Path $Dir)) { return $false }
    $journal = Join-Path $Dir 'snapshot.jsonl'
    (-not (Test-Path -LiteralPath $journal)) -or (Test-TuneupTrustedItem -Path $journal)
}

function Get-TuneupFileLinkCount {
    param([Parameter(Mandatory)]$Handle)
    if (-not ('WindowsTuneup.NativeFile' -as [type])) { Add-Type -TypeDefinition $script:NativeFileSource }
    [WindowsTuneup.NativeFile]::GetLinkCount($Handle)
}

function Open-TuneupTrustedStream {
    param([Parameter(Mandatory)][string]$Path, [switch]$Append)
    $untrusted = "State file $Path is not trusted"
    if (-not (Test-TuneupTrustedItem -Path (Split-Path -Parent $Path))) { throw $untrusted }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw $untrusted }
    # Owner, DACL and link count are checked on the handle that is then read or written, and
    # FileShare.Read keeps anyone else from writing while it is open.
    if ($Append) {
        $stream = New-Object System.IO.FileStream -ArgumentList $Path, ([System.IO.FileMode]::Append), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::Read)
    }
    else {
        $stream = New-Object System.IO.FileStream -ArgumentList $Path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::Read)
    }
    try {
        $trusted = (Test-TuneupTrustedSecurity -Security $stream.GetAccessControl()) -and
            ((Get-TuneupFileLinkCount -Handle $stream.SafeFileHandle) -eq 1)
    }
    catch {
        $trusted = $false
    }
    if (-not $trusted) {
        $stream.Dispose()
        throw $untrusted
    }
    $stream
}

function Read-TuneupStateFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Root, [switch]$IgnoreUntrusted)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    if ((Resolve-TuneupFileRoot -Path $Path -Root $Root) -ne 'machine') {
        return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
    }
    try {
        $stream = Open-TuneupTrustedStream -Path $Path
    }
    catch {
        if (-not $IgnoreUntrusted) { throw }
        Write-Warning "Ignoring untrusted state file $Path"
        return $null
    }
    $reader = New-Object System.IO.StreamReader -ArgumentList $stream, $script:Utf8NoBom, $true
    try { $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

function Write-TuneupStateFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$Append,
        [string]$Root
    )
    if ((Resolve-TuneupFileRoot -Path $Path -Root $Root) -ne 'machine') {
        if ($Append) { [System.IO.File]::AppendAllText($Path, $Text, $script:Utf8NoBom) }
        else { [System.IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom) }
        return
    }
    if ($Append -and (Test-Path -LiteralPath $Path)) {
        $stream = Open-TuneupTrustedStream -Path $Path -Append
    }
    else {
        $parent = Split-Path -Parent $Path
        if (-not (Test-TuneupTrustedItem -Path $parent)) { throw (Get-TuneupUntrustedMessage -Path $parent) }
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
        $stream = New-TuneupSecureFile -Path $Path -Security (New-TuneupStateSecurity -File)
    }
    try {
        $bytes = $script:Utf8NoBom.GetBytes($Text)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $stream.Dispose()
    }
}

function Read-TuneupTrustedJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Root)
    $text = Read-TuneupStateFile -Path $Path -Root $Root -IgnoreUntrusted
    if (-not $text) { return $null }
    try {
        $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Ignoring unreadable state file $Path"
        $null
    }
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

function Initialize-TuneupStateRoot {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($folder in @($Path, (Join-Path $Path 'runs'))) {
        $existed = Test-Path -LiteralPath $folder
        if (-not $existed) {
            try {
                New-TuneupSecureDirectory -Path $folder -Security (New-TuneupStateSecurity)
            }
            catch {
                if (-not (Test-Path -LiteralPath $folder)) { throw }
                $existed = $true
            }
        }
        # Checked after creating it too: someone may have made it first, even as a junction.
        # A folder someone else made is never taken over: its owner could swap it for a junction
        # between the check and Set-Acl, and the ACL would land on the junction target.
        if (-not (Test-TuneupTrustedItem -Path $folder)) {
            throw (Get-TuneupUntrustedMessage -Path $folder)
        }
        if ($existed) { Set-TuneupStateSecurity -Path $folder }
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

function Save-TuneupJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object, [string]$Root)
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    Write-TuneupStateFile -Path $Path -Text $json -Root $Root
}

function Add-TuneupJournalEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Tweak,
        [Parameter(Mandatory)][AllowNull()]$State,
        [string]$Root
    )
    if ((Resolve-TuneupFileRoot -Path $Path -Root $Root) -eq 'user' -and -not (Test-TuneupUserScopedTweak -Tweak $Tweak)) {
        throw "Cannot journal machine-scope tweak '$($Tweak.id)' in the user state folder"
    }
    $entry = [pscustomobject]@{ id = $Tweak.id; tweak = $Tweak; state = $State }
    $line = ConvertTo-Json -InputObject $entry -Depth 10 -Compress
    Write-TuneupStateFile -Path $Path -Text ($line + [Environment]::NewLine) -Append -Root $Root
}

function Read-TuneupJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Root)
    $kind = Resolve-TuneupFileRoot -Path $Path -Root $Root
    $text = Read-TuneupStateFile -Path $Path -Root $kind
    if ($null -eq $text) { return }
    $lines = @($text -split "`r?`n")
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

function Read-TuneupRunJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)
    $currentSid = Get-TuneupCurrentUserSid
    foreach ($entry in @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl') -Root $Run.Root)) {
        # A user-scope entry holds HKCU values of whoever made the run; restoring it would write them
        # into the current user's hive instead.
        if ([string]$entry.tweak.scope -ne 'machine' -and $Run.UserSid -ne $currentSid) {
            Write-Warning "Ignoring user-scope entry '$($entry.id)' of run $($Run.Id): it belongs to another user"
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
            $info = Read-TuneupTrustedJson -Path (Join-Path $dir.FullName 'run.json') -Root $root.Kind
            $userSid = $null
            if ($null -ne $info -and $info.userSid -is [string]) { $userSid = $info.userSid }
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

function Test-TuneupRunCompletable {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)
    if ($Run.Root -eq 'user') { return $true }
    if ($Run.UserSid -ne (Get-TuneupCurrentUserSid)) { return $false }
    try {
        $entries = @(Read-TuneupJournal -Path (Join-Path $Run.Dir 'snapshot.jsonl') -Root $Run.Root)
    }
    catch {
        return $false
    }
    @($entries | Where-Object { -not (Test-TuneupUserScopedTweak -Tweak $_.tweak) }).Count -eq 0
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
    # Without elevation only runs this user can fully undo are candidates for 'last'.
    $isAdmin = [bool](Test-TuneupAdmin)
    $pending = @($runs | Where-Object { -not $_.Undone })
    for ($i = $pending.Count - 1; $i -ge 0; $i--) {
        if ($isAdmin -or (Test-TuneupRunCompletable -Run $pending[$i])) { return $pending[$i] }
    }
}
