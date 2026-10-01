# Uninstalls the OneDrive sync client (a Win32 program, not a Store app) and never deletes a file or
# folder of the user. It refuses, changing nothing, when a shell folder (Desktop, Documents, Pictures,
# Music, Videos, Favorites...) lives in a OneDrive folder (Known Folder Move), when OneDrive holds
# online-only files or folders, which would no longer open from this PC, or when it cannot check every
# file. A per-machine install is removed for every account, so before that every other profile of the
# PC is checked too. It also refuses when the process does not run as the account signed in at this
# desktop (elevated with another administrator's password): OneDrive, its folders and its files belong
# to that account. Undo reinstalls it with winget (package Microsoft.OneDrive, source winget); the user
# signs in again. Installed means a real OneDrive.exe: folders and logs left by an earlier uninstall do
# not count.

function Get-OnedriveActionHelperEnvironmentRoot {
    param()
    # The roots that OneDrive announces to the processes of the current account.
    foreach ($name in 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $value }
    }
}

function Get-OnedriveActionHelperRoot {
    param([string]$SoftwareKey = 'HKCU:\Software', [switch]$Environment)
    # Folders where OneDrive keeps the synced files of one account: the root of each account
    # (Accounts\*\UserFolder) and every SharePoint or Teams library synced outside it (one value per
    # local folder under Accounts\*\Tenants\*). -Environment adds the roots of the current account.
    $roots = New-Object System.Collections.Generic.List[string]
    if ($Environment) { foreach ($value in @(Get-OnedriveActionHelperEnvironmentRoot)) { $roots.Add([string]$value) } }
    $accounts = Join-Path -Path $SoftwareKey -ChildPath 'Microsoft\OneDrive\Accounts'
    if (Test-Path -LiteralPath $accounts) {
        foreach ($account in @(Get-ChildItem -LiteralPath $accounts -ErrorAction SilentlyContinue)) {
            $folder = (Get-ItemProperty -LiteralPath $account.PSPath -ErrorAction SilentlyContinue).UserFolder
            if ($folder) { $roots.Add([string]$folder) }
            $tenants = Join-Path -Path $account.PSPath -ChildPath 'Tenants'
            if (-not (Test-Path -LiteralPath $tenants)) { continue }
            foreach ($tenant in @(Get-ChildItem -LiteralPath $tenants -ErrorAction SilentlyContinue)) {
                foreach ($name in @($tenant.GetValueNames())) {
                    if ($name -match '^(?:[A-Za-z]:\\|\\\\)') { $roots.Add([string]$name) }
                }
            }
        }
    }
    @($roots | Sort-Object -Unique)
}

function Get-OnedriveActionHelperKnownFolder {
    param([string]$SoftwareKey = 'HKCU:\Software', [string]$ProfilePath = [Environment]::GetFolderPath('UserProfile'))
    # Every shell folder of one account (Desktop, Documents, Pictures, Music, Videos, Favorites,
    # Downloads...), as the registry keeps it, with %USERPROFILE% read as that account's profile.
    $key = Join-Path -Path $SoftwareKey -ChildPath 'Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    if (-not (Test-Path -LiteralPath $key)) { return }
    $item = Get-Item -LiteralPath $key
    try {
        foreach ($name in @($item.GetValueNames())) {
            $raw = [string]$item.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
            if (-not $raw) { continue }
            $raw = $raw -ireplace '%USERPROFILE%', $ProfilePath.Replace('$', '$$')
            [Environment]::ExpandEnvironmentVariables($raw)
        }
    } finally {
        $item.Close()
    }
}

function Test-OnedriveActionHelperUnder {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    ($Path.TrimEnd('\') + '\').StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-OnedriveActionHelperRedirected {
    param([string]$SoftwareKey = 'HKCU:\Software', [string]$ProfilePath = [Environment]::GetFolderPath('UserProfile'), [switch]$Environment)
    # Known Folder Move: a shell folder lives in a folder named OneDrive or under a root of OneDrive.
    $roots = @(Get-OnedriveActionHelperRoot -SoftwareKey $SoftwareKey -Environment:$Environment)
    foreach ($folder in @(Get-OnedriveActionHelperKnownFolder -SoftwareKey $SoftwareKey -ProfilePath $ProfilePath)) {
        if ($folder -match '\\OneDrive( - [^\\]+)?(\\|$)') { return $true }
        foreach ($root in $roots) {
            if (Test-OnedriveActionHelperUnder -Path $folder -Root $root) { return $true }
        }
    }
    $false
}

function Test-OnedriveActionHelperCloudAttribute {
    param([long]$Attributes)
    # Files On-Demand placeholders, files and folders: RECALL_ON_DATA_ACCESS (0x400000),
    # RECALL_ON_OPEN (0x40000) or OFFLINE (0x1000).
    ($Attributes -band (0x400000 -bor 0x40000 -bor 0x1000)) -ne 0
}

function Get-OnedriveActionHelperLongPath {
    param([Parameter(Mandatory)][string]$Path)
    # With \\?\ the listing also reaches paths longer than 260 characters.
    if ($Path.StartsWith('\\?\')) { return $Path }
    if ($Path.StartsWith('\\')) { return '\\?\UNC\' + $Path.Substring(2) }
    '\\?\' + $Path
}

function Get-OnedriveActionHelperTopFolder {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path, [switch]$Folder)
    # Only the name of the folder, right under the root, that holds the item (or of the root), never a
    # full path of the user.
    $parts = @($Path.Substring($Root.TrimEnd('\').Length).TrimStart('\') -split '\\')
    if ($parts.Count -gt 1 -or $Folder) { return $parts[0] }
    Split-Path -Path $Root -Leaf
}

function Get-OnedriveActionHelperLinkType {
    param([Parameter(Mandatory)]$Item)
    # Junction or SymbolicLink for a link; nothing for other reparse points, such as the folders that
    # OneDrive keeps as cloud files placeholders.
    [string]$Item.LinkType
}

function Get-OnedriveActionHelperOnlineOnly {
    param([AllowEmptyCollection()][string[]]$Root = @())
    # Walks every file and folder under the roots (listing downloads nothing) and fails closed: what
    # could not be listed is counted, so a refusal can say that the check was not complete. The walk
    # is done by hand because Get-ChildItem -Recurse of Windows PowerShell does not enter reparse
    # points, and every folder of OneDrive is one. It enters a folder that is a cloud placeholder or a
    # reparse point that is not a link; a junction or a symbolic link inside a root is not followed
    # (it could lead anywhere, even in a loop) and counts as not checked.
    $count = 0
    $first = $null
    $errors = 0
    foreach ($folder in @($Root | Where-Object { $_ } | Sort-Object -Unique)) {
        # A root that does not exist has nothing in it; one that cannot be opened is not checked.
        try {
            $rootItem = Get-Item -LiteralPath $folder -Force -ErrorAction Stop
        } catch [System.Management.Automation.ItemNotFoundException] {
            continue
        } catch {
            $errors++
            continue
        }
        if ($null -eq $rootItem -or -not $rootItem.PSIsContainer) { continue }
        $long = Get-OnedriveActionHelperLongPath -Path $folder.TrimEnd('\')
        $pending = New-Object System.Collections.Generic.Stack[string]
        $pending.Push($long)
        while ($pending.Count) {
            $directory = $pending.Pop()
            try {
                $entries = @((New-Object System.IO.DirectoryInfo -ArgumentList $directory).EnumerateFileSystemInfos())
            } catch {
                $errors++
                continue
            }
            foreach ($entry in $entries) {
                $attributes = [long]$entry.Attributes
                $cloud = Test-OnedriveActionHelperCloudAttribute -Attributes $attributes
                $isFolder = $entry -is [System.IO.DirectoryInfo]
                if ($cloud) {
                    $count++
                    if ($null -eq $first) { $first = Get-OnedriveActionHelperTopFolder -Root $long -Path $entry.FullName -Folder:$isFolder }
                }
                if (-not $isFolder) { continue }
                if (($attributes -band [long][System.IO.FileAttributes]::ReparsePoint) -and -not $cloud) {
                    try {
                        $link = Get-OnedriveActionHelperLinkType -Item $entry
                    } catch {
                        $link = 'unknown'
                    }
                    if ($link) {
                        $errors++
                        continue
                    }
                }
                $pending.Push($entry.FullName)
            }
        }
    }
    [pscustomobject]@{ count = $count; firstFolder = $first; errors = $errors }
}

function Get-OnedriveActionHelperVersion {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    # File versions compared as versions (10.0 is newer than 9.0); one that cannot be read counts as 0.0.
    $version = $null
    if ([version]::TryParse(([string]$Text).Trim(), [ref]$version)) { return $version }
    [version]'0.0'
}

function Get-OnedriveActionHelperNewest {
    param([AllowEmptyCollection()][object[]]$File = @())
    $File | Sort-Object -Property { Get-OnedriveActionHelperVersion -Text ([string]$_.VersionInfo.FileVersion) } -Descending | Select-Object -First 1
}

function Get-OnedriveActionHelperSystemSetup {
    param()
    # The OneDriveSetup.exe that comes with Windows (System32, or SysWOW64 on older 64-bit builds). It
    # is owned by TrustedInstaller, unlike the copy in the user's AppData, which the user can replace.
    foreach ($folder in [Environment]::GetFolderPath('System'), [Environment]::GetFolderPath('SystemX86')) {
        if (-not $folder) { continue }
        $setup = Join-Path -Path $folder -ChildPath 'OneDriveSetup.exe'
        if (Test-Path -LiteralPath $setup -PathType Leaf) { return $setup }
    }
}

function Get-OnedriveActionHelperInstall {
    param()
    # Folders as Windows knows them: environment variables can be changed by the user.
    $local = Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'Microsoft\OneDrive'
    $result = [ordered]@{ perUser = $false; perMachine = $false; machineSetup = $null; version = $null }
    $userExe = Join-Path -Path $local -ChildPath 'OneDrive.exe'
    if (Test-Path -LiteralPath $userExe -PathType Leaf) {
        $result.perUser = $true
        $result.version = (Get-Item -LiteralPath $userExe).VersionInfo.FileVersion
    }
    # Per-machine installs keep OneDrive.exe at the root of Microsoft OneDrive or one version folder down.
    $bases = @([Environment]::GetFolderPath('ProgramFiles'), [Environment]::GetFolderPath('ProgramFilesX86')) | Where-Object { $_ } | Select-Object -Unique
    foreach ($base in $bases) {
        $root = Join-Path -Path $base -ChildPath 'Microsoft OneDrive'
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $exe = Get-ChildItem -LiteralPath $root -Filter 'OneDrive.exe' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $exe) { continue }
        $result.perMachine = $true
        if (-not $result.version) { $result.version = $exe.VersionInfo.FileVersion }
        $setup = Get-OnedriveActionHelperNewest -File @(Get-ChildItem -LiteralPath $root -Filter 'OneDriveSetup.exe' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue)
        if ($null -ne $setup) { $result.machineSetup = $setup.FullName }
        break
    }
    [pscustomobject]$result
}

function Get-OnedriveActionHelperStep {
    param([Parameter(Mandatory)]$Install)
    # The setups that remove each kind of install. Elevated, only a setup that no one but SYSTEM,
    # TrustedInstaller or Administrators can change is run: the per-machine one next to the installed
    # client, and for a per-user install the one of Windows (OneDriveSetup.exe /uninstall removes the
    # OneDrive of the account that runs it), never the copy in the user's AppData.
    $steps = @()
    if ($Install.perMachine) {
        $setup = [string]$Install.machineSetup
        if (-not $setup -or -not (Test-Path -LiteralPath $setup -PathType Leaf)) {
            throw 'OneDriveSetup.exe was not found next to the installed client; nothing was changed'
        }
        if (-not (Test-TuneupTrustedExecutable -Path $setup -StopAt ([Environment]::GetFolderPath('ProgramFiles'))) -and
            -not (Test-TuneupTrustedExecutable -Path $setup -StopAt ([Environment]::GetFolderPath('ProgramFilesX86')))) {
            throw "OneDriveSetup.exe next to the installed client is not trusted (someone other than administrators can change it); nothing was changed"
        }
        $steps += , [pscustomobject]@{ flavour = 'perMachine'; setup = $setup; arguments = @('/uninstall', '/allusers') }
    }
    if ($Install.perUser) {
        $setup = Get-OnedriveActionHelperSystemSetup
        if (-not $setup) { throw 'The OneDriveSetup.exe of Windows was not found in System32, so the per-user OneDrive cannot be removed safely; nothing was changed' }
        if (-not (Test-TuneupTrustedExecutable -Path $setup -StopAt ([Environment]::GetFolderPath('Windows')))) {
            throw "The OneDriveSetup.exe of Windows is not trusted (someone other than administrators can change it); nothing was changed"
        }
        $steps += , [pscustomobject]@{ flavour = 'perUser'; setup = $setup; arguments = @('/uninstall') }
    }
    $steps
}

function Get-OnedriveActionHelperProfilePath {
    param([Parameter(Mandatory)][string]$Raw)
    # ProfileImagePath as Windows keeps it (%SystemDrive%\Users\Ana), expanded with the folders of
    # Windows and not with the variables of this process, which a user can set. Any other variable is
    # left as it is, and that profile is then treated as one that cannot be checked.
    $windows = [Environment]::GetFolderPath('Windows')
    $drive = [System.IO.Path]::GetPathRoot($windows).TrimEnd('\')
    $path = $Raw -ireplace '%SystemRoot%', $windows.Replace('$', '$$')
    $path -ireplace '%SystemDrive%', $drive.Replace('$', '$$')
}

function Get-OnedriveActionHelperProfile {
    param()
    # The other accounts with a profile on this PC, told apart by their SID wherever their folder is:
    # its SID, folder and, when its registry is loaded (signed in, or a process of it running), the
    # Software key of its hive.
    $me = Get-TuneupCurrentUserSid
    foreach ($key in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction Stop)) {
        $sid = [string]$key.PSChildName
        if ($sid -notmatch '^S-1-(?:5-21|12-1)-[0-9-]+(?:\.bak)?$' -or $sid -eq $me) { continue }
        $raw = [string]$key.GetValue('ProfileImagePath', $null, 'DoNotExpandEnvironmentNames')
        if (-not $raw) { continue }
        $path = Get-OnedriveActionHelperProfilePath -Raw $raw
        $software = "Registry::HKEY_USERS\$($sid -replace '\.bak$', '')\Software"
        [pscustomobject]@{
            sid      = $sid
            name     = Split-Path -Path $path -Leaf
            path     = $path
            software = $(if (Test-Path -LiteralPath $software) { $software } else { $null })
        }
    }
}

function Get-OnedriveActionHelperSyncRoot {
    param([string]$Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager')
    # The roots that OneDrive registered with Windows for every account (one key per account and
    # library, named OneDrive!<SID>!..., whose UserSyncRoots value is named after the SID). They are
    # readable without loading the registry of an account that is signed out. Other sync providers
    # are not touched by removing OneDrive.
    if (-not (Test-Path -LiteralPath $Key)) { return }
    foreach ($provider in @(Get-ChildItem -LiteralPath $Key -ErrorAction Stop)) {
        if ([string]$provider.PSChildName -notlike 'OneDrive!*') { continue }
        $roots = Join-Path -Path $provider.PSPath -ChildPath 'UserSyncRoots'
        if (-not (Test-Path -LiteralPath $roots)) { continue }
        $item = Get-Item -LiteralPath $roots -ErrorAction Stop
        try {
            foreach ($name in @($item.GetValueNames())) {
                $path = [string]$item.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
                if ($name -and $path) { [pscustomobject]@{ sid = [string]$name; path = $path } }
            }
        } finally {
            $item.Close()
        }
    }
}

function Test-OnedriveActionHelperNonEmpty {
    param([Parameter(Mandatory)][string]$Path)
    # Whether a folder holds anything; a folder that cannot be listed throws.
    @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Select-Object -First 1).Count -gt 0
}

function Get-OnedriveActionHelperProfileFolder {
    param([Parameter(Mandatory)][string]$ProfilePath)
    # The folders that OneDrive creates in a profile: OneDrive and OneDrive - <organization>.
    @(Get-ChildItem -LiteralPath $ProfilePath -Directory -Force -Filter 'OneDrive*' -ErrorAction Stop | ForEach-Object { $_.FullName })
}

function Get-OnedriveActionHelperProfileRisk {
    param([Parameter(Mandatory)]$Account)
    # Why removing OneDrive for all users could cost this account its files, or nothing.
    if ([string]$Account.path -match '%') { return 'unreadable' }
    $sid = [string]$Account.sid -replace '\.bak$', ''
    try {
        $syncRoots = @(Get-OnedriveActionHelperSyncRoot | Where-Object { $_.sid -eq $sid } | ForEach-Object { $_.path })
    } catch {
        return 'unreadable'
    }
    $folders = @()
    if (Test-Path -LiteralPath $Account.path -PathType Container) {
        try {
            $folders = @(Get-OnedriveActionHelperProfileFolder -ProfilePath $Account.path)
        } catch {
            return 'unreadable'
        }
    }
    if ($Account.software) {
        if (Test-OnedriveActionHelperRedirected -SoftwareKey $Account.software -ProfilePath $Account.path) { return 'known-folders' }
        $scan = Get-OnedriveActionHelperOnlineOnly -Root (@(Get-OnedriveActionHelperRoot -SoftwareKey $Account.software) + $syncRoots + $folders)
        if ($scan.errors -gt 0) { return 'unreadable' }
        if ($scan.count -gt 0) { return 'online-only' }
        return
    }
    # Signed out: its settings cannot be read, so a OneDrive folder or sync root with anything in it
    # is a risk. A root that no longer exists holds nothing.
    foreach ($folder in @($folders) + @($syncRoots)) {
        if (-not $folder) { continue }
        try {
            if (-not (Test-Path -LiteralPath $folder)) { continue }
            if (Test-OnedriveActionHelperNonEmpty -Path $folder) { return 'signed-out' }
        } catch {
            return 'unreadable'
        }
    }
}

function Get-OnedriveActionHelperProfileAtRisk {
    param()
    foreach ($account in @(Get-OnedriveActionHelperProfile)) {
        $why = Get-OnedriveActionHelperProfileRisk -Account $account
        if ($why) { [pscustomobject]@{ name = $account.name; why = $why } }
    }
}

function Get-OnedriveActionHelperOtherProfile {
    param()
    # Other accounts with their own per-user OneDrive: it can only be removed signed in as them.
    $count = 0
    try {
        $accounts = @(Get-OnedriveActionHelperProfile)
    } catch {
        $accounts = @()
    }
    foreach ($account in $accounts) {
        if (Test-Path -LiteralPath (Join-Path -Path $account.path -ChildPath 'AppData\Local\Microsoft\OneDrive\OneDrive.exe') -PathType Leaf) { $count++ }
    }
    $count
}

function Test-OnedriveActionHelperRunning {
    param()
    @(Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue).Count -gt 0
}

function Wait-OnedriveActionHelperRemoval {
    param([Parameter(Mandatory)][ValidateSet('perUser', 'perMachine')][string]$Flavour, [int]$Seconds = 90)
    # The setup hands the work to an elevated child and can return before it ends. Each kind of
    # install is waited for on its own, so one that is gone never waits for the other.
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if (-not (Get-OnedriveActionHelperInstall).$Flavour) { return $true }
        Start-Sleep -Seconds 2
    } until ((Get-Date) -gt $deadline)
    $false
}

function Get-OnedriveActionState {
    param([Parameter(Mandatory)]$Tweak)
    $install = Get-OnedriveActionHelperInstall
    $installed = ($install.perUser -or $install.perMachine)
    [pscustomobject]@{
        id             = $Tweak.id
        installed      = $installed
        perUser        = $install.perUser
        perMachine     = $install.perMachine
        version        = $install.version
        # Whose OneDrive it was: the undo of another account leaves it for its owner.
        currentUserSid = $(if ($installed) { Get-TuneupCurrentUserSid } else { $null })
    }
}

function Test-OnedriveActionState {
    param([Parameter(Mandatory)]$Tweak)
    if ((Get-OnedriveActionState -Tweak $Tweak).installed) { return 'not-applied' }
    'applied'
}

function Set-OnedriveActionDesired {
    param([Parameter(Mandatory)]$Tweak)
    $install = Get-OnedriveActionHelperInstall
    if (-not ($install.perUser -or $install.perMachine)) { return }
    # The refusals come before anything is touched.
    if (-not (Test-TuneupSessionUser)) {
        return (New-TuneupOutcome -Refused -Reason 'onedrive-session-user' -Detail "$($Tweak.id): this process does not run as the account signed in at this desktop (it was elevated with another administrator's password, or there is no desktop to compare with), and OneDrive, its folders and its files belong to that account. Run windows-tuneup from an elevated prompt of the account that is signed in; nothing was changed")
    }
    if (Test-OnedriveActionHelperRedirected -SoftwareKey 'HKCU:\Software' -ProfilePath ([Environment]::GetFolderPath('UserProfile')) -Environment) {
        return (New-TuneupOutcome -Refused -Reason 'onedrive-known-folders' -Detail "$($Tweak.id): a folder such as Desktop, Documents or Pictures is in OneDrive (Known Folder Move). Move them back to the local profile in the OneDrive settings first; nothing was changed")
    }
    $roots = @(Get-OnedriveActionHelperRoot -SoftwareKey 'HKCU:\Software' -Environment)
    try {
        $roots += @(Get-OnedriveActionHelperProfileFolder -ProfilePath ([Environment]::GetFolderPath('UserProfile')))
        $scan = Get-OnedriveActionHelperOnlineOnly -Root $roots
    } catch {
        $scan = [pscustomobject]@{ count = 0; firstFolder = $null; errors = 1 }
    }
    if ($scan.errors -gt 0) {
        return (New-TuneupOutcome -Refused -Reason 'onedrive-scan-incomplete' -Detail "$($Tweak.id): $($scan.errors) file(s) or folder(s) of OneDrive could not be listed, so it is not certain that none of them lives only in the cloud. Check the access to the OneDrive folders and run again; nothing was changed")
    }
    if ($scan.count -gt 0) {
        return (New-TuneupOutcome -Refused -Reason 'onedrive-online-only-files' -Detail "$($Tweak.id): OneDrive holds $($scan.count) file(s) or folder(s) that are only in the cloud (the first one in the folder '$($scan.firstFolder)'). Make them available offline or move them, then run again; nothing was changed")
    }
    # A per-machine install is removed for every account: none of them may be at risk either.
    if ($install.perMachine) {
        $atRisk = @(Get-OnedriveActionHelperProfileAtRisk)
        if ($atRisk.Count) {
            return (New-TuneupOutcome -Refused -Reason 'onedrive-other-accounts' -Detail "$($Tweak.id): OneDrive is installed for all users and $($atRisk.Count) other account(s) of this PC (the first one '$($atRisk[0].name)': $($atRisk[0].why)) use Known Folder Move, have files only in the cloud, or keep OneDrive folders that cannot be checked while they are signed out or cannot be read. Each of them must sign in and move the folders back or make the files available offline; nothing was changed")
        }
    }
    $steps = @(Get-OnedriveActionHelperStep -Install $install)
    $wasRunning = [bool](Test-OnedriveActionHelperRunning)
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($step in $steps) {
        $run = Invoke-TuneupNative -FilePath $step.setup -Arguments ([string[]]$step.arguments)
        if (-not (Wait-OnedriveActionHelperRemoval -Flavour $step.flavour)) {
            $what = $(if ($step.flavour -eq 'perMachine') { 'the OneDrive for all users' } else { 'the OneDrive of this account' })
            $output = $(if ($run.Output) { ": $($run.Output)" } else { '' })
            $problems.Add("OneDriveSetup.exe $($step.arguments -join ' ') ended with code $($run.ExitCode) and $what was still installed after waiting$output")
        }
    }
    $others = [int](Get-OnedriveActionHelperOtherProfile)
    if ($others -gt 0) { $problems.Add("$others other account(s) still have their own OneDrive; each one must remove it signed in") }
    $note = $(if ($wasRunning) { 'OneDrive was running; its setup closed it' } else { $null })
    if (-not $problems.Count) {
        if ($note) { return (New-TuneupOutcome -Detail $note) }
        return
    }
    if ($note) { $problems.Add($note) }
    $message = $problems -join '; '
    $now = Get-OnedriveActionHelperInstall
    # Gone for this account, or for all users, while something else is left: partly done.
    if (($install.perMachine -and -not $now.perMachine) -or ($install.perUser -and -not $now.perUser)) {
        return (New-TuneupOutcome -Partial -Detail $message)
    }
    throw $message
}

function Restore-OnedriveActionState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    # Only the kinds of install that were there and are gone now are given back.
    if (-not [bool]$State.installed) { return }
    $now = Get-OnedriveActionHelperInstall
    $missing = @()
    if ([bool]$State.perMachine -and -not $now.perMachine) { $missing += 'perMachine' }
    if ([bool]$State.perUser -and -not $now.perUser) { $missing += 'perUser' }
    if (-not $missing.Count) { return }
    foreach ($flavour in $missing) {
        $arguments = @('install', '--id', 'Microsoft.OneDrive', '--source', 'winget', '--exact', '--no-upgrade',
            '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity')
        # For all users: without /allusers the setup installs for the current account only.
        if ($flavour -eq 'perMachine') { $arguments += @('--override', '/silent /allusers') }
        $result = Invoke-TuneupWinget -Arguments $arguments
        if ($script:WingetSuccessCode -notcontains $result.ExitCode) {
            throw "winget could not reinstall OneDrive ($($Tweak.id)), exit code $($result.ExitCode): $($result.Output). To install it by hand: winget install --id Microsoft.OneDrive"
        }
    }
    $notes = New-Object System.Collections.Generic.List[string]
    $notes.Add('Sign in to OneDrive again; Known Folder Move and the OneDrive of other accounts are not restored')
    $after = Get-OnedriveActionHelperInstall
    foreach ($flavour in $missing) {
        if ($after.$flavour) { continue }
        $what = $(if ($flavour -eq 'perMachine') { 'for all users' } else { 'for this account' })
        $notes.Add("the OneDrive $what could not be confirmed; to install it by hand: winget install --id Microsoft.OneDrive")
    }
    New-TuneupOutcome -Reason 'reinstalled-onedrive' -Detail ($notes -join '; ')
}
