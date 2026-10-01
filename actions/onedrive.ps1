# Uninstalls the OneDrive sync client (a Win32 program, not a Store app) and never deletes a file or
# folder of the user. It refuses, changing nothing, when Desktop, Documents or Pictures live in a
# OneDrive folder (Known Folder Move) or when OneDrive holds online-only files, which would no longer
# open from this PC. Undo reinstalls it with winget (package Microsoft.OneDrive, source winget); the
# user signs in again. Installed means a real OneDrive.exe: folders and logs left by an earlier
# uninstall do not count.

function Get-OnedriveActionHelperRoot {
    param()
    # Folders where OneDrive keeps the user's synced files.
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($name in 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $roots.Add($value) }
    }
    $accounts = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path -LiteralPath $accounts) {
        foreach ($account in Get-ChildItem -LiteralPath $accounts -ErrorAction SilentlyContinue) {
            $folder = (Get-ItemProperty -LiteralPath $account.PSPath -ErrorAction SilentlyContinue).UserFolder
            if ($folder) { $roots.Add([string]$folder) }
        }
    }
    @($roots | Sort-Object -Unique)
}

function Get-OnedriveActionHelperKnownFolder {
    param()
    # Desktop, Documents and Pictures as the registry keeps them (with %USERPROFILE% unexpanded).
    $item = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    foreach ($name in 'Desktop', 'Personal', 'My Pictures') {
        $raw = $null
        if ($null -ne $item) { $raw = $item.$name }
        if ($raw) { [Environment]::ExpandEnvironmentVariables([string]$raw) }
    }
}

function Test-OnedriveActionHelperRedirected {
    param()
    # Known Folder Move: one of those folders lives under a OneDrive folder.
    $roots = @(Get-OnedriveActionHelperRoot)
    foreach ($folder in @(Get-OnedriveActionHelperKnownFolder)) {
        if ($folder -match '\\OneDrive( - [^\\]+)?(\\|$)') { return $true }
        foreach ($root in $roots) {
            if (($folder.TrimEnd('\') + '\').StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }
    $false
}

function Get-OnedriveActionHelperOnlineOnly {
    param()
    # Files On-Demand placeholders: RECALL_ON_DATA_ACCESS, RECALL_ON_OPEN or OFFLINE. Listing a
    # folder does not download anything. Returns the first one found, or nothing.
    $recall = 0x400000 -bor 0x40000 -bor 0x1000
    foreach ($root in @(Get-OnedriveActionHelperRoot)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $hit = Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { ([int]$_.Attributes -band $recall) -ne 0 } | Select-Object -First 1
        if ($null -ne $hit) { return $hit.FullName }
    }
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

function Get-OnedriveActionHelperOtherProfile {
    param()
    # Other accounts with their own per-user OneDrive: it can only be removed signed in as them.
    $mine = [Environment]::GetEnvironmentVariable('USERPROFILE')
    $count = 0
    foreach ($profileKey in Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue) {
        $path = (Get-ItemProperty -LiteralPath $profileKey.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $path -or $path -ieq $mine -or $path -notlike '*\Users\*') { continue }
        if (Test-Path -LiteralPath (Join-Path -Path $path -ChildPath 'AppData\Local\Microsoft\OneDrive\OneDrive.exe') -PathType Leaf) { $count++ }
    }
    $count
}

function Wait-OnedriveActionHelperRemoval {
    param([int]$Seconds = 90)
    # The setup hands the work to an elevated child and can return before it ends.
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $now = Get-OnedriveActionHelperInstall
        if (-not ($now.perUser -or $now.perMachine)) { return $true }
        Start-Sleep -Seconds 2
    } until ((Get-Date) -gt $deadline)
    $false
}

function Get-OnedriveActionState {
    param([Parameter(Mandatory)]$Tweak)
    $install = Get-OnedriveActionHelperInstall
    [pscustomobject]@{
        id         = $Tweak.id
        installed  = ($install.perUser -or $install.perMachine)
        perUser    = $install.perUser
        perMachine = $install.perMachine
        version    = $install.version
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
    if (Test-OnedriveActionHelperRedirected) {
        return (New-TuneupOutcome -Refused -Reason 'onedrive-known-folders' -Detail "$($Tweak.id): Desktop, Documents or Pictures are in OneDrive (Known Folder Move). Move them back to the local profile in the OneDrive settings first; nothing was changed")
    }
    $placeholder = Get-OnedriveActionHelperOnlineOnly
    if ($placeholder) {
        return (New-TuneupOutcome -Refused -Reason 'onedrive-online-only-files' -Detail "$($Tweak.id): OneDrive holds files that are only in the cloud (for example $placeholder). Make them available offline or move them, then run again; nothing was changed")
    }
    $steps = @(Get-OnedriveActionHelperStep -Install $install)
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($step in $steps) {
        $run = Invoke-TuneupNative -FilePath $step.setup -Arguments ([string[]]$step.arguments)
        if (-not (Wait-OnedriveActionHelperRemoval) -and $run.ExitCode -ne 0) {
            $problems.Add("OneDriveSetup.exe $($step.arguments -join ' ') ended with code $($run.ExitCode): $($run.Output)")
        }
    }
    $others = [int](Get-OnedriveActionHelperOtherProfile)
    if ($others -gt 0) { $problems.Add("$others other account(s) still have their own OneDrive; each one must remove it signed in") }
    if (-not $problems.Count) { return }
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
    # Nothing to give back if it was not installed, or if it is installed again.
    if (-not [bool]$State.installed) { return }
    $now = Get-OnedriveActionHelperInstall
    if ($now.perUser -or $now.perMachine) { return }
    $arguments = @('install', '--id', 'Microsoft.OneDrive', '--source', 'winget', '--exact', '--no-upgrade',
        '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity')
    # Installed for all users before: without /allusers the setup installs for the current user only.
    if ([bool]$State.perMachine) { $arguments += @('--override', '/silent /allusers') }
    $result = Invoke-TuneupWinget -Arguments $arguments
    if ($script:WingetSuccessCode -notcontains $result.ExitCode) {
        throw "winget could not reinstall OneDrive ($($Tweak.id)), exit code $($result.ExitCode): $($result.Output). To install it by hand: winget install --id Microsoft.OneDrive"
    }
    New-TuneupOutcome -Reason 'reinstalled' -Detail 'Sign in to OneDrive again; Known Folder Move and the OneDrive of other accounts are not restored'
}
