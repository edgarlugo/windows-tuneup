$script:StateOwnerSid = 'S-1-5-32-544'
$script:TrustedSids = @('S-1-5-18', 'S-1-5-32-544')
# NT SERVICE\TrustedInstaller, which owns the files of Windows and of the packages under WindowsApps.
$script:TrustedInstallerSid = 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
# Owners accepted for the folder that holds the machine state folder, and owners and writers accepted
# for a program that runs elevated: SYSTEM, TrustedInstaller, Administrators.
$script:BaseTrustedSids = @('S-1-5-18', $script:TrustedInstallerSid, 'S-1-5-32-544')
$script:UsersSid = 'S-1-5-32-545'
$script:OwnerRightsSid = 'S-1-3-4'
# Any of these granted to an untrusted SID lets it change or replace a state file.
$script:WriteRights = [int][System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, DeleteSubdirectoriesAndFiles, WriteAttributes, Delete, ChangePermissions, TakeOwnership'
$script:WriteRights = $script:WriteRights -bor 0x10000000 -bor 0x40000000
# On the base folder these would let someone replace the state folder or change who controls it;
# creating folders and appending (what Users get on C:\ProgramData) is fine.
$script:BaseWriteRights = [int][System.Security.AccessControl.FileSystemRights]'DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
$script:BaseWriteRights = $script:BaseWriteRights -bor 0x10000000
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

function Get-TuneupCurrentUserSid {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Get-TuneupUntrustedMessage {
    param([Parameter(Mandatory)][string]$Path)
    Get-TuneupText -Key 'err.stateFolderUntrusted' -Format $Path
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
    # CreateNew fails if the file exists; FileShare.None keeps it exclusive while it is written.
    [System.IO.FileStream]::new(
        $Path,
        [System.IO.FileMode]::CreateNew,
        [System.Security.AccessControl.FileSystemRights]::Write,
        [System.IO.FileShare]::None,
        4096,
        [System.IO.FileOptions]::None,
        $Security)
}

function Test-TuneupTrustedSecurity {
    param([Parameter(Mandatory)]$Security, [string[]]$TrustedSids = $script:TrustedSids, [switch]$SkipInheritOnly)
    $owner = $Security.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($null -eq $owner -or $TrustedSids -notcontains $owner.Value) { return $false }
    foreach ($rule in $Security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
        # An inherit-only entry (CREATOR OWNER on System32) only applies to what is created inside.
        if ($SkipInheritOnly -and ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly)) { continue }
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

# A program that an elevated process runs: the file and every folder above it, up to $StopAt (not
# included), must be owned by SYSTEM, TrustedInstaller or Administrators and give no one else a right
# to change them, so nobody else can replace the program or plant a library next to it. Hard links are
# fine here (the programs of System32 are hard links into WinSxS): the ACL belongs to the file, whatever
# its name. A junction or symbolic link on the way is not.
function Test-TuneupTrustedExecutable {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$StopAt)
    try {
        $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
        $stop = [System.IO.Path]::GetFullPath($StopAt).TrimEnd('\') + '\'
    }
    catch {
        return $false
    }
    if ($full.Length -le $stop.Length -or -not $full.StartsWith($stop, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $current = $full
    $isProgram = $true
    while ($current.Length -ge $stop.Length) {
        try {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
            if ($isProgram -and $item.PSIsContainer) { return $false }
            $security = Get-Acl -LiteralPath $current -ErrorAction Stop
        }
        catch {
            return $false
        }
        if (-not (Test-TuneupTrustedSecurity -Security $security -TrustedSids $script:BaseTrustedSids -SkipInheritOnly)) { return $false }
        $isProgram = $false
        $current = Split-Path -Path $current -Parent
        if (($current.TrimEnd('\') + '\') -ieq $stop) { break }
    }
    $true
}

# True only when Windows refuses to show the ACL (some files of the Store packages), not for any
# other failure.
function Test-TuneupAclDenied {
    param([Parameter(Mandatory)][string]$Path)
    try {
        Get-Acl -LiteralPath $Path -ErrorAction Stop | Out-Null
    }
    catch {
        $exception = $_.Exception
        while ($null -ne $exception) {
            if ($exception -is [System.UnauthorizedAccessException]) { return $true }
            $exception = $exception.InnerException
        }
        return ($_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::PermissionDenied)
    }
    $false
}

function Test-TuneupBaseFolder {
    param([Parameter(Mandatory)][string]$Path, [string[]]$TrustedSids = $script:BaseTrustedSids)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $false }
        $security = Get-Acl -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        return $false
    }
    $owner = $security.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($null -eq $owner -or $TrustedSids -notcontains $owner.Value) { return $false }
    foreach ($rule in $security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
        # Inherit-only entries (CREATOR OWNER on C:\ProgramData) apply to children, not to this folder.
        if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        if ($TrustedSids -contains $rule.IdentityReference.Value) { continue }
        if (([int]$rule.FileSystemRights -band $script:BaseWriteRights) -ne 0) { return $false }
    }
    $true
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
    # Owner, DACL and link count are checked on the handle that is then read or written.
    # Writers keep other writers out (FileShare.Read); readers share with a writer (FileShare.ReadWrite).
    # An IOException here (file in use) reaches the caller as it is, not as "untrusted".
    if ($Append) {
        $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    }
    else {
        $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
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

function Initialize-TuneupStateRoot {
    param([Parameter(Mandatory)][string]$Path, [string[]]$Children = @('runs'))
    $base = Split-Path -Parent $Path
    if (-not (Test-TuneupBaseFolder -Path $base)) {
        throw (Get-TuneupText -Key 'err.stateBaseUntrusted' -Format $base)
    }
    foreach ($folder in @($Path) + @($Children | ForEach-Object { Join-Path $Path $_ })) {
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

# Elevated, TEMP and TMP of this process go to tmp of the machine state folder, which only administrators
# can change. Add-Type compiles C# with csc.exe through files in TEMP, and DISM and winget work there:
# the TEMP of the account is a folder that its programs without elevation can change, so one could swap
# the compiled library or a downloaded installer between its writing and its use, and run it as
# administrator. Throws, changing nothing, when that folder cannot be trusted. Without elevation, and with
# -StateRoot (development only), nothing changes.
function Use-TuneupElevatedTemp {
    param([string]$StateRoot, [string]$MachineRoot)
    if ($StateRoot -or -not (Test-TuneupAdmin)) { return }
    if (-not $MachineRoot) { $MachineRoot = Get-TuneupStateRoot -Machine }
    Initialize-TuneupStateRoot -Path $MachineRoot -Children @('tmp')
    # A folder of its own inside tmp (it takes the access list of tmp), so that the end of one elevated run
    # never removes what another one, still running, has there. Gives its path; the caller empties and
    # removes it at the end (Clear-TuneupTempFolder -RemoveFolder).
    $folder = Join-Path (Join-Path $MachineRoot 'tmp') ([guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($folder)
    $env:TEMP = $folder
    $env:TMP = $folder
    $folder
}

# Empties a temporary folder (the one of an elevated run, at its end) and, with -RemoveFolder, removes
# it too. A link, file or folder, is removed as a name, never followed: Directory.Delete without
# recursion removes a junction itself, and File.Delete removes a link, not its target. Gives one text
# for each entry that could not be removed (or for a folder that could not be listed), and goes on.
function Clear-TuneupTempFolder {
    param([Parameter(Mandatory)][string]$Path, [switch]$RemoveFolder)
    if ($RemoveFolder) {
        $problems = @(Clear-TuneupTempFolder -Path $Path)
        if ($problems.Count) { return $problems }
        try { [System.IO.Directory]::Delete($Path, $false) } catch { "Could not remove ${Path}: $($_.Exception.Message)" }
        return
    }
    try {
        $entries = @([System.IO.Directory]::GetFileSystemEntries($Path))
    }
    catch {
        return "Could not list ${Path}: $($_.Exception.Message)"
    }
    foreach ($entry in $entries) {
        try {
            $attributes = [System.IO.File]::GetAttributes($entry)
            $isLink = [bool]($attributes -band [System.IO.FileAttributes]::ReparsePoint)
            if ($attributes -band [System.IO.FileAttributes]::Directory) {
                if (-not $isLink) {
                    $inside = @(Clear-TuneupTempFolder -Path $entry)
                    if ($inside.Count) { $inside; continue }
                }
                [System.IO.Directory]::Delete($entry, $false)
            }
            else {
                if (-not $isLink -and ($attributes -band [System.IO.FileAttributes]::ReadOnly)) {
                    [System.IO.File]::SetAttributes($entry, $attributes -band -bnot [System.IO.FileAttributes]::ReadOnly)
                }
                [System.IO.File]::Delete($entry)
            }
        }
        catch {
            "Could not remove ${entry}: $($_.Exception.Message)"
        }
    }
}
