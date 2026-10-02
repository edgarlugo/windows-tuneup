<#
.SYNOPSIS
    Downloads a release of windows-tuneup, checks its SHA256 and installs it.
.DESCRIPTION
    The install.ps1 attached to a release carries the version and the SHA256 of its zip, so
        irm https://github.com/edgarlugo/windows-tuneup/releases/download/v<version>/install.ps1 | iex
    installs exactly that release. The zip is downloaded into memory, never to a folder: its SHA256 is
    checked on those bytes and the same bytes are extracted, so nothing can be swapped in between.

    As administrator it installs in %ProgramFiles%\windows-tuneup. The release is extracted into a new
    folder next to the destination that has, from the moment it is created, an access list that only
    administrators can change (users can read and run it); then the earlier copy is moved aside, the new
    one takes its place and the earlier one is removed. If anything fails the earlier copy stays as it
    was. As administrator it refuses: a destination whose folders above can be renamed, deleted or
    re-permissioned by someone who is not an administrator, a network folder, and an earlier copy that
    does not belong to the administrators or that someone else can change (any file or folder in it):
    whoever can change those files could run code as administrator the next time they are used.

    Without elevation it installs in -Destination (by default windows-tuneup-<version> in the current
    folder); that copy is for the tweaks of your user only and must not be run as administrator, because
    other programs of your account can change it.

    Parameters: -Version and -Sha256 (the copy of install.ps1 in the repository has none: give the
    version and the line of the zip in SHA256SUMS of that release), -Destination, and -Source (a release
    URL base, HTTPS only, or a folder that holds windows-tuneup-<version>.zip, for offline installs).

    It needs Windows PowerShell 5.1 or PowerShell 7 in Full Language mode (Constrained Language Mode,
    under App Control or AppLocker, is not supported).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Destination D:\Tools\windows-tuneup
#>

# The parameters are declared in the script block, not in a param() of the script: through "irm | iex" a
# param() of the script would set $Version, $Destination... in the session of whoever runs it. With -File the
# arguments arrive in $args and @args passes them on by name. Everything runs in that block's own scope and
# errors are thrown, never "exit", which would close the session; the try makes a wrong argument fail too.
try {
    & {
        [CmdletBinding()]
        param(
            [string]$Version = '__TUNEUP_VERSION__',
            [string]$Sha256 = '__TUNEUP_ZIP_SHA256__',
            [string]$Destination,
            [string]$Source = 'https://github.com/edgarlugo/windows-tuneup/releases/download'
        )
        $ErrorActionPreference = 'Stop'
        $ProgressPreference = 'SilentlyContinue'

        # Gives the reason a file or folder cannot be trusted to hold code that runs as administrator, or
        # nothing. With -Recurse every file and folder in it is checked too (links are reported, never followed).
        function Get-InstallFolderProblem {
            param([Parameter(Mandatory)][string]$Path, [switch]$LinkOnly, [switch]$Recurse)
            # Administrators, SYSTEM and TrustedInstaller are the owners and writers a folder of programs may have.
            $trustedSid = @('S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
            $pending = New-Object System.Collections.Generic.Stack[string]
            $pending.Push($Path)
            while ($pending.Count) {
                $current = $pending.Pop()
                $item = Get-Item -LiteralPath $current -Force
                if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return "$current is a link" }
                if (-not $LinkOnly) {
                    $acl = Get-Acl -LiteralPath $current
                    $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
                    if ($trustedSid -notcontains $owner) { return "$current is owned by $($acl.Owner), not by Administrators" }
                    $writer = Get-InstallFolderWriter -Path $current
                    if ($writer) { return "$writer can change $current" }
                }
                if ($Recurse -and $item -is [System.IO.DirectoryInfo]) {
                    foreach ($child in [System.IO.Directory]::GetFileSystemEntries($current)) { $pending.Push($child) }
                }
            }
        }

        # Gives the first principal other than the administrators and the system that can change a file or
        # folder (or, through an inherited rule, what is created in it), or nothing.
        function Get-InstallFolderWriter {
            param([Parameter(Mandatory)][string]$Path)
            $trustedSid = @('S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
            # GENERIC_ALL (0x10000000) and GENERIC_WRITE (0x40000000) are kept as such in inherit-only rules.
            $write = [int64][System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
            $write = $write -bor 0x10000000 -bor 0x40000000
            foreach ($rule in (Get-Acl -LiteralPath $Path).GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
                if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
                if (([int64]$rule.FileSystemRights -band $write) -eq 0) { continue }
                # CREATOR OWNER only matters for what its owner could do, and the owner is checked apart.
                if ($trustedSid -contains $rule.IdentityReference.Value -or $rule.IdentityReference.Value -eq 'S-1-3-0') { continue }
                $who = $rule.IdentityReference.Value
                try { $who = $rule.IdentityReference.Translate([System.Security.Principal.NTAccount]).Value } catch { Write-Verbose "No name for $who" }
                return $who
            }
        }

        # Gives why the folders above a destination cannot be trusted, or nothing: one that does not exist or
        # is a link, or that someone besides the administrators and the system owns or can rename, delete or
        # re-permission (and so put another folder in its place). Creating new entries in them is not a
        # problem: Users may create folders in C:\, but not replace Program Files.
        function Get-InstallParentProblem {
            param([Parameter(Mandatory)][string]$Path)
            $trustedSid = @('S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
            $replace = [int64][System.Security.AccessControl.FileSystemRights]'Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
            $replace = $replace -bor 0x10000000
            $parent = [System.IO.Path]::GetDirectoryName($Path.TrimEnd('\'))
            if (-not $parent) { return "$Path is not a folder inside another" }
            while ($parent) {
                if (-not [System.IO.Directory]::Exists($parent)) { return "$parent does not exist" }
                if ((Get-Item -LiteralPath $parent -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return "$parent is a link" }
                $acl = Get-Acl -LiteralPath $parent
                $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
                if ($trustedSid -notcontains $owner) { return "$parent is owned by $($acl.Owner)" }
                foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
                    if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { continue }
                    # A rule only for what is created inside does not apply to the folder itself.
                    if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
                    if (([int64]$rule.FileSystemRights -band $replace) -eq 0) { continue }
                    if ($trustedSid -contains $rule.IdentityReference.Value -or $rule.IdentityReference.Value -eq 'S-1-3-0') { continue }
                    $who = $rule.IdentityReference.Value
                    try { $who = $rule.IdentityReference.Translate([System.Security.Principal.NTAccount]).Value } catch { Write-Verbose "No name for $who" }
                    return "$who can rename or delete $parent"
                }
                $parent = [System.IO.Path]::GetDirectoryName($parent)
            }
        }

        # Owner Administrators; no inherited rules; administrators and SYSTEM full control; users read and run.
        function New-InstallFolderSecurity {
            $administrators = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
            $system = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
            $users = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
            $security = New-Object System.Security.AccessControl.DirectorySecurity
            $security.SetOwner($administrators)
            $security.SetAccessRuleProtection($true, $false)
            $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
            $none = [System.Security.AccessControl.PropagationFlags]::None
            $allow = [System.Security.AccessControl.AccessControlType]::Allow
            foreach ($entry in @(@($system, 'FullControl'), @($administrators, 'FullControl'), @($users, 'ReadAndExecute'))) {
                $security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $entry[0], ([System.Security.AccessControl.FileSystemRights]$entry[1]), $inherit, $none, $allow))
            }
            $security
        }

        # Creates a folder that has -Security from the moment it exists, so nothing can be put in it first.
        # Windows PowerShell has Directory.CreateDirectory(path, security); PowerShell 7 (.NET) has
        # FileSystemAclExtensions.Create instead.
        function New-InstallFolder {
            param([Parameter(Mandatory)][string]$Path, [System.Security.AccessControl.DirectorySecurity]$Security)
            if (Test-Path -LiteralPath $Path) { throw "$Path already exists." }
            if (-not $Security) {
                [void][System.IO.Directory]::CreateDirectory($Path)
            } elseif ($PSVersionTable.PSEdition -eq 'Core') {
                [System.IO.FileSystemAclExtensions]::Create((New-Object System.IO.DirectoryInfo -ArgumentList $Path), $Security)
            } else {
                [void][System.IO.Directory]::CreateDirectory($Path, $Security)
            }
        }

        # Gives why a zip entry cannot be extracted, or nothing. Every entry is a plain relative path under
        # windows-tuneup-<version>/: no "..", no drive or stream (":", which PowerShell 7 would not reject),
        # no "\", no device name, no name ending in a dot or a space, and not the marker of the installer.
        function Get-InstallEntryProblem {
            param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version)
            $top = "windows-tuneup-$Version/"
            if (-not $Name.StartsWith($top, [StringComparison]::Ordinal)) { return "The zip has an entry outside its folder: $Name" }
            $relative = $Name.Substring($top.Length)
            if ($relative.EndsWith('/')) { $relative = $relative.Substring(0, $relative.Length - 1) }
            if (-not $relative) { return }
            if ($relative -eq '.windows-tuneup') { return "The zip has an entry whose name is not allowed: $Name" }
            $invalid = [System.IO.Path]::GetInvalidFileNameChars()
            foreach ($segment in $relative.Split('/')) {
                if ($segment -eq '' -or $segment -eq '.' -or $segment -eq '..') { return "The zip has an entry outside its folder: $Name" }
                if ($segment.IndexOfAny($invalid) -ge 0 -or $segment.Contains(':') -or $segment -match '[. ]$' -or
                    $segment -match '^(CON|PRN|AUX|NUL|COM\d|LPT\d)(\..*)?$') {
                    return "The zip has an entry whose name is not allowed: $Name"
                }
            }
        }

        # A folder is an earlier copy of windows-tuneup if it has the marker the installer writes, or (for a
        # copy that predates the marker) tuneup.ps1 and engine\Tuneup.psm1.
        function Test-InstallCopy {
            param([Parameter(Mandatory)][string]$Path)
            if ([System.IO.File]::Exists((Join-Path $Path '.windows-tuneup'))) { return $true }
            [System.IO.File]::Exists((Join-Path $Path 'tuneup.ps1')) -and [System.IO.File]::Exists((Join-Path $Path 'engine\Tuneup.psm1'))
        }

        # Every check comes before anything is downloaded, created or moved.
        if ($ExecutionContext.SessionState.LanguageMode -ne [System.Management.Automation.PSLanguageMode]::FullLanguage) {
            throw "This installer needs PowerShell in Full Language mode (this session is in $($ExecutionContext.SessionState.LanguageMode)). Nothing was installed."
        }
        if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $Sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            throw 'This install.ps1 has no release in it: use the one attached to a release, or give -Version and -Sha256 (the line of the zip in SHA256SUMS of that release).'
        }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $admin = (New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($admin -and $PSVersionTable.PSEdition -eq 'Core') {
            try { Add-Type -AssemblyName System.IO.FileSystem.AccessControl } catch { Write-Verbose "System.IO.FileSystem.AccessControl: $($_.Exception.Message)" }
            if (-not ('System.IO.FileSystemAclExtensions' -as [type])) {
                throw 'This PowerShell cannot create a folder with its access list: run the installer in Windows PowerShell (powershell.exe). Nothing was installed.'
            }
        }
        if (-not $Destination) {
            if ($admin) { $Destination = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'windows-tuneup' }
            else { $Destination = Join-Path (Get-Location).ProviderPath "windows-tuneup-$Version" }
        }
        $Destination = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)).TrimEnd('\')
        $parentFolder = [System.IO.Path]::GetDirectoryName($Destination)
        if (-not $parentFolder) { throw "$Destination is not a folder inside another: choose another -Destination. Nothing was installed." }
        $name = "windows-tuneup-$Version.zip"
        $fromFolder = Test-Path -LiteralPath $Source -PathType Container
        if (-not $fromFolder -and $Source -notmatch '^https://') { throw "This installer only downloads over HTTPS: -Source must start with https:// (or be a folder that holds $name)." }

        if ($admin) {
            if (([uri]$Destination).IsUnc) { throw "As administrator the installer does not install on a network folder ($Destination): its access list is not decided by this computer. Nothing was installed." }
            $problem = Get-InstallParentProblem -Path $Destination
            if ($problem) { throw "The folders above $Destination cannot be trusted ($problem): install in Program Files (without -Destination) or in a folder that only administrators can change. Nothing was installed." }
        }
        $replacing = Test-Path -LiteralPath $Destination
        if ($replacing) {
            $link = Get-InstallFolderProblem -Path $Destination -LinkOnly
            if ($link) { throw "${link}: choose another -Destination. Nothing was installed." }
            if (-not (Test-InstallCopy -Path $Destination)) { throw "$Destination exists and is not a copy of windows-tuneup: choose another -Destination. Nothing was installed." }
            if ($admin) {
                # The earlier copy must be one that only administrators could have changed, file by file.
                $problem = Get-InstallFolderProblem -Path $Destination -Recurse
                if ($problem) { throw "$Destination cannot be trusted ($problem): remove it yourself or choose another -Destination. Nothing was installed." }
            }
        }

        # The zip is read into memory once; the SHA256 is checked on those bytes and the same bytes are extracted.
        if ($fromFolder) {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $Source $name))
        } else {
            $protocol = [Net.ServicePointManager]::SecurityProtocol
            $client = New-Object System.Net.WebClient
            try {
                [Net.ServicePointManager]::SecurityProtocol = $protocol -bor [Net.SecurityProtocolType]::Tls12
                $url = "$($Source.TrimEnd('/'))/v$Version/$name"
                Write-Host "Downloading $url ..."
                $bytes = $client.DownloadData($url)
            } finally {
                $client.Dispose()
                [Net.ServicePointManager]::SecurityProtocol = $protocol
            }
        }
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try { $actual = [System.BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-', '') } finally { $hasher.Dispose() }
        if ($actual -ne $Sha256.ToUpperInvariant()) {
            throw "The SHA256 of $name is $actual, not $($Sha256.ToUpperInvariant()): it is not that release. Nothing was installed."
        }
        Write-Host "SHA256 checked: $actual"

        Add-Type -AssemblyName System.IO.Compression
        $top = "windows-tuneup-$Version/"
        $archive = New-Object System.IO.Compression.ZipArchive -ArgumentList (New-Object System.IO.MemoryStream -ArgumentList (, $bytes)), ([System.IO.Compression.ZipArchiveMode]::Read)
        try {
            $files = New-Object System.Collections.Generic.List[object]
            $seen = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $archive.Entries) {
                $problem = Get-InstallEntryProblem -Name $entry.FullName -Version $Version
                if ($problem) { throw "$problem. Nothing was installed." }
                $relative = $entry.FullName.Substring($top.Length)
                if (-not $relative -or $relative.EndsWith('/')) { continue }
                if (-not $seen.Add($relative)) { throw "The zip has the entry $($entry.FullName) twice. Nothing was installed." }
                $files.Add($entry)
            }
            if (-not $seen.Contains('tuneup.ps1') -or -not $seen.Contains('engine/Tuneup.psm1')) { throw "$name is not a release of windows-tuneup. Nothing was installed." }

            # The new copy is built next to the destination (same disk, so it can take its place by a rename).
            $suffix = [guid]::NewGuid().ToString('N')
            $staging = "$Destination.new-$suffix"
            $old = $null
            $installed = $false
            $lost = $false
            if (-not $admin -and -not [System.IO.Directory]::Exists($parentFolder)) { [void][System.IO.Directory]::CreateDirectory($parentFolder) }
            try {
                if ($admin) {
                    New-InstallFolder -Path $staging -Security (New-InstallFolderSecurity)
                    $problem = Get-InstallFolderProblem -Path $staging
                    if ($problem) { throw "The new folder $staging did not get its access list ($problem)." }
                } else {
                    New-InstallFolder -Path $staging
                }
                $inside = $staging + '\'
                foreach ($entry in $files) {
                    $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($staging, $entry.FullName.Substring($top.Length).Replace('/', '\')))
                    if (-not $target.StartsWith($inside, [StringComparison]::OrdinalIgnoreCase)) { throw "The zip has an entry outside its folder: $($entry.FullName)" }
                    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target))
                    $writer = New-Object System.IO.FileStream -ArgumentList $target, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)
                    try {
                        $reader = $entry.Open()
                        try { $reader.CopyTo($writer) } finally { $reader.Dispose() }
                    } finally {
                        $writer.Dispose()
                    }
                }
                [System.IO.File]::WriteAllText((Join-Path $staging '.windows-tuneup'), "$Version`r`n")
                if ($admin) {
                    # Under the default policy what an administrator creates belongs to Administrators; if this
                    # computer gives it to the account instead, that account could change it: refuse.
                    $problem = Get-InstallFolderProblem -Path $staging -Recurse
                    if ($problem) { throw "The new copy cannot be trusted ($problem)." }
                }

                # The earlier copy moves aside, the new one takes its place; if that fails, the earlier copy goes back.
                if ($replacing -ne (Test-Path -LiteralPath $Destination)) { throw "$Destination changed while the installer ran." }
                if ($replacing) {
                    try {
                        [System.IO.Directory]::Move($Destination, "$Destination.old-$suffix")
                    } catch {
                        $reason = $(if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message })
                        throw "$Destination could not be moved aside ($reason): close the programs and consoles that use it (also one whose current folder is in it) and run the installer again."
                    }
                    $old = "$Destination.old-$suffix"
                }
                try {
                    [System.IO.Directory]::Move($staging, $Destination)
                } catch {
                    $failure = $_
                    if ($old) {
                        try {
                            [System.IO.Directory]::Move($old, $Destination)
                        } catch {
                            $lost = $true
                            throw "Installing failed ($($failure.Exception.Message)) and the earlier copy could not be put back: it is in $old."
                        }
                        $old = $null
                    }
                    throw $failure
                }
                $installed = $true
            } catch {
                if ($lost) { throw }
                $kept = $(if ($replacing) { " The earlier copy in $Destination is as it was." } else { '' })
                throw "$($_.Exception.Message) Nothing was installed.$kept"
            } finally {
                if (-not $installed -and [System.IO.Directory]::Exists($staging)) {
                    try { [System.IO.Directory]::Delete($staging, $true) } catch { Write-Warning "The unfinished copy in $staging could not be removed ($($_.Exception.Message)): remove it yourself." }
                }
            }
        } finally {
            $archive.Dispose()
        }
        if ($old) {
            # Directory.Delete removes a link inside the folder, never what it points to.
            try { [System.IO.Directory]::Delete($old, $true) } catch { Write-Warning "The earlier copy, moved to $old, could not be removed ($($_.Exception.Message)): remove it yourself." }
        }

        Write-Host "windows-tuneup $Version is in $Destination"
        Write-Host "Run: powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Destination 'tuneup.ps1')`""
        if (-not $admin) {
            Write-Warning 'This copy is in a folder that programs of your account can change: use it for the tweaks of your user only, never as administrator. For system tweaks, run this installer in PowerShell as administrator: it installs in Program Files.'
        }
    } @args
} catch {
    throw
}
