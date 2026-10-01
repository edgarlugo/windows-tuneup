$script:StateOwnerSid = 'S-1-5-32-544'
$script:TrustedSids = @('S-1-5-18', 'S-1-5-32-544')
# Owners accepted for the folder that holds the machine state folder: SYSTEM, TrustedInstaller, Administrators.
$script:BaseTrustedSids = @('S-1-5-18', 'S-1-5-80-956008885-3425145150-2718476148-1766412592', 'S-1-5-32-544')
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
    param([Parameter(Mandatory)][string]$Path)
    $base = Split-Path -Parent $Path
    if (-not (Test-TuneupBaseFolder -Path $base)) {
        throw "Folder $base is not trusted to hold the machine state folder"
    }
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
