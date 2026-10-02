<#
.SYNOPSIS
    Downloads a release of windows-tuneup, checks its SHA256 and installs it.
.DESCRIPTION
    The install.ps1 attached to a release carries the version and the SHA256 of its zip, so
        irm https://github.com/edgarlugo/windows-tuneup/releases/download/v<version>/install.ps1 | iex
    installs exactly that release: a zip whose SHA256 differs is never extracted, and nothing that
    was downloaded runs before that check.

    As administrator it installs in %ProgramFiles%\windows-tuneup and gives the folder an access list
    that only administrators can change (users can read and run it). It refuses to replace an existing
    folder that does not belong to the administrators or that users can change: whoever can change the
    files of that folder could run code as administrator the next time it is used. Without elevation
    it extracts to -Destination (by default windows-tuneup-<version> in the current folder); that copy
    is for the tweaks of your user only and must not be run as administrator, because other programs of
    your account can change it.

    The copy of install.ps1 in the repository has no version: give -Version and -Sha256 (the line of
    the zip in SHA256SUMS of that release).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Destination D:\Tools\windows-tuneup
#>
param(
    [string]$Version = '__TUNEUP_VERSION__',
    [string]$Sha256 = '__TUNEUP_ZIP_SHA256__',
    [string]$Destination,
    # A release URL base (HTTPS only), or a folder that holds windows-tuneup-<version>.zip (offline and tests).
    [string]$Source = 'https://github.com/edgarlugo/windows-tuneup/releases/download'
)

# Everything runs in its own scope: through "irm | iex" nothing is left behind in the caller's session,
# and an error is thrown, never "exit", which would close that session.
& {
    param([string]$Version, [string]$Sha256, [string]$Destination, [string]$Source)
    $ErrorActionPreference = 'Stop'

    # Gives the reason a folder cannot be trusted to hold code that runs as administrator, or nothing.
    function Get-InstallFolderProblem {
        param([Parameter(Mandatory)][string]$Path, [switch]$LinkOnly)
        # Administrators, SYSTEM and TrustedInstaller are the owners and writers a folder of programs may have.
        $trustedSid = @('S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return "$Path is a link" }
        if ($LinkOnly) { return }
        $acl = Get-Acl -LiteralPath $Path
        $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if ($trustedSid -notcontains $owner) { return "it is owned by $($acl.Owner), not by Administrators" }
        $writer = Get-InstallFolderWriter -Path $Path
        if ($writer) { return "$writer can change it" }
    }

    # Gives the first principal other than the administrators and the system that can change a folder, or nothing.
    function Get-InstallFolderWriter {
        param([Parameter(Mandatory)][string]$Path)
        $trustedSid = @('S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
        $write = [int64][System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
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

    if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $Sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
        throw 'This install.ps1 has no release in it: use the one attached to a release, or give -Version and -Sha256 (the line of the zip in SHA256SUMS of that release).'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $admin = (New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $Destination) {
        if ($admin) { $Destination = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'windows-tuneup' }
        else { $Destination = Join-Path (Get-Location).ProviderPath "windows-tuneup-$Version" }
    }
    $Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    $name = "windows-tuneup-$Version.zip"
    $fromFolder = Test-Path -LiteralPath $Source -PathType Container
    if (-not $fromFolder -and $Source -notmatch '^https://') { throw "This installer only downloads over HTTPS: -Source must start with https:// (or be a folder that holds $name)." }
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-tuneup-install-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $zip = Join-Path $work $name
        if ($fromFolder) {
            Copy-Item -LiteralPath (Join-Path $Source $name) -Destination $zip
        } else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $url = "$($Source.TrimEnd('/'))/v$Version/$name"
            Write-Host "Downloading $url ..."
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        }
        # Nothing of what was downloaded is read as anything but bytes until this check passes.
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if ($actual -ne $Sha256.ToUpperInvariant()) {
            throw "The SHA256 of $name is $actual, not $($Sha256.ToUpperInvariant()): it is not that release. Nothing was installed."
        }
        Write-Host "SHA256 checked: $actual"

        # Every entry must be under windows-tuneup-<version>/ and land inside the folder it is extracted to.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extract = Join-Path $work 'extract'
        $inside = [System.IO.Path]::GetFullPath($extract).TrimEnd('\') + '\'
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archive.Entries) {
                $target = $null
                try { $target = [System.IO.Path]::GetFullPath((Join-Path $extract $entry.FullName)) } catch { $target = $null }
                if (-not $entry.FullName.StartsWith("windows-tuneup-$Version/", [StringComparison]::Ordinal) -or
                    -not $target -or -not $target.StartsWith($inside, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "The zip has an entry outside its folder: $($entry.FullName)"
                }
            }
        } finally {
            $archive.Dispose()
        }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
        $top = Join-Path $extract "windows-tuneup-$Version"
        if (-not (Test-Path -LiteralPath (Join-Path $top 'tuneup.ps1')) -or -not (Test-Path -LiteralPath (Join-Path $top 'engine\Tuneup.psm1'))) {
            throw "$name is not a release of windows-tuneup."
        }

        # An earlier copy is replaced; any other folder is left alone. As administrator the earlier copy
        # must also be one that only administrators could have changed.
        if (Test-Path -LiteralPath $Destination) {
            $link = Get-InstallFolderProblem -Path $Destination -LinkOnly
            if ($link) { throw "${link}: choose another -Destination. Nothing was installed." }
            $earlier = (Test-Path -LiteralPath (Join-Path $Destination 'tuneup.ps1')) -and (Test-Path -LiteralPath (Join-Path $Destination 'engine\Tuneup.psm1'))
            if (-not $earlier) { throw "$Destination exists and is not a copy of windows-tuneup: choose another -Destination." }
            if ($admin) {
                $problem = Get-InstallFolderProblem -Path $Destination
                if ($problem) { throw "$Destination cannot be trusted ($problem): remove it yourself or choose another -Destination. Nothing was installed." }
            }
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        if ($admin) {
            # The access list is set while the folder is still empty, so what is copied in inherits it.
            try {
                [System.IO.Directory]::SetAccessControl($Destination, (New-InstallFolderSecurity))
            } catch {
                Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
                throw
            }
        }
        Copy-Item -Path (Join-Path $top '*') -Destination $Destination -Recurse
        # Files saved by a browser carry a mark that PowerShell checks; these were not, but a copy made
        # by hand from a downloaded zip would, so it is cleared the same way.
        Get-ChildItem -LiteralPath $Destination -Recurse -File | Unblock-File

        Write-Host "windows-tuneup $Version is in $Destination"
        Write-Host "Run: powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Destination 'tuneup.ps1')`""
        if (-not $admin) {
            Write-Warning 'This copy is in a folder that programs of your account can change: use it for the tweaks of your user only, never as administrator. For system tweaks, run this installer in PowerShell as administrator: it installs in Program Files.'
        }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
} -Version $Version -Sha256 $Sha256 -Destination $Destination -Source $Source
