# Appx package names look like Microsoft.BingNews; Store ids are the 12-character product ids
# that winget uses with --source msstore.
$script:AppxNamePattern = '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}\z'
$script:StoreIdPattern = '^[0-9A-Z]{12}\z'

# The lists are read once per process and dropped after any change, so a plan, the apply and the
# check that follows it do not each list every package again.
$script:AppxPackageCache = @{}
$script:AppxProvisionedCache = $null

function Clear-TuneupAppxCache {
    $script:AppxPackageCache = @{}
    $script:AppxProvisionedCache = $null
}

function Test-AppxTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.name -cnotmatch $script:AppxNamePattern) { 'has an invalid appx package name' }
    if ([string]$set.storeId -cnotmatch $script:StoreIdPattern) { 'needs a Microsoft Store id (12 capital letters or digits) in set.storeId' }
    if ($set.action -cne 'remove') { "has an invalid appx action '$($set.action)'" }
    if ($Tweak.scope -cne 'machine') { 'must use scope machine' }
}

function Get-TuneupAppxPackage {
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:AppxPackageCache.ContainsKey($Name)) {
        # -Name takes wildcards, so only the exact name is kept.
        $script:AppxPackageCache[$Name] = @(Get-AppxPackage -AllUsers -Name $Name -ErrorAction Stop | Where-Object { $_.Name -eq $Name })
    }
    $script:AppxPackageCache[$Name]
}

function Get-TuneupAppxProvisionedPackage {
    param([Parameter(Mandatory)][string]$Name)
    if ($null -eq $script:AppxProvisionedCache) {
        $script:AppxProvisionedCache = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
    }
    $script:AppxProvisionedCache | Where-Object { $_.DisplayName -eq $Name }
}

function Remove-TuneupAppxPackage {
    param([Parameter(Mandatory)]$Package)
    try {
        Remove-AppxPackage -Package $Package.PackageFullName -AllUsers -ErrorAction Stop
    } finally {
        Clear-TuneupAppxCache
    }
}

function Remove-TuneupAppxProvisionedPackage {
    param([Parameter(Mandatory)]$Package)
    try {
        Remove-AppxProvisionedPackage -Online -PackageName $Package.PackageName -AllUsers -ErrorAction Stop | Out-Null
    } finally {
        Clear-TuneupAppxCache
    }
}


function Get-TuneupAppxUserSid {
    param([Parameter(Mandatory)]$User)
    # Windows returns a struct with string Sid and Username fields; its text form is only the type name.
    # Text that carries the SID itself (like "S-1-5-21-...[PC\me]") is an edge case that is read too.
    $id = $User.UserSecurityId
    if ("$($id.Sid) $id" -match 'S-1-[0-9]+(?:-[0-9]+)+') { $Matches[0] }
}

function Get-TuneupAppxInstalledSid {
    param([AllowEmptyCollection()][object[]]$Packages = @())
    # -AllUsers also lists packages that are only staged for a user (provisioned, never installed).
    $sids = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    $unknown = 0
    foreach ($package in $Packages) {
        foreach ($user in @($package.PackageUserInformation)) {
            if ([string]$user.InstallState -ne 'Installed') { continue }
            $sid = Get-TuneupAppxUserSid -User $user
            if (-not $sid) { $unknown++; $sid = "unknown-$unknown" }
            [void]$sids.Add($sid)
        }
    }
    @($sids)
}

function Test-TuneupAppxInstalledForAnyUser {
    param([AllowEmptyCollection()][object[]]$Packages = @())
    @(Get-TuneupAppxInstalledSid -Packages $Packages).Count -gt 0
}

function Get-AppxTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.name
    $installed = @(Get-TuneupAppxPackage -Name $name)
    $provisioned = @(Get-TuneupAppxProvisionedPackage -Name $name)
    $sids = @(Get-TuneupAppxInstalledSid -Packages $installed)
    $me = Get-TuneupCurrentUserSid
    $currentUserHad = ($sids -contains $me)
    $versions = @(@($installed | ForEach-Object { [string]$_.Version }) + @($provisioned | ForEach-Object { [string]$_.Version }) | Where-Object { $_ })
    [pscustomobject]@{
        installedUsers = ($sids.Count -gt 0)
        currentUserHad = $currentUserHad
        currentUserSid = $(if ($currentUserHad) { $me } else { $null })
        otherUsers     = @($sids | Where-Object { $_ -ne $me }).Count
        provisioned    = ($provisioned.Count -gt 0)
        version        = $(if ($versions.Count) { $versions[0] } else { $null })
    }
}

function Test-AppxTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-AppxTweakState -Tweak $Tweak
    # An app that is neither installed nor provisioned already matches the goal: there is nothing to remove.
    if ($state.installedUsers -or $state.provisioned) { return 'not-applied' }
    'applied'
}

function Set-AppxTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.name
    $problems = New-Object System.Collections.Generic.List[string]
    # Both lists are read before anything is removed: a failed read after a removal would hide that
    # the app is already gone for its users. A package that is only staged has no user to remove it from.
    $packages = @(Get-TuneupAppxPackage -Name $name | Where-Object { Test-TuneupAppxInstalledForAnyUser -Packages @($_) })
    $provisioned = @()
    try {
        $provisioned = @(Get-TuneupAppxProvisionedPackage -Name $name)
    } catch {
        $problems.Add("reading the provisioned packages failed: $($_.Exception.Message)")
    }
    $changed = 0
    foreach ($package in $packages) {
        try {
            Remove-TuneupAppxPackage -Package $package
            $changed++
        } catch {
            $problems.Add("removing $($package.PackageFullName) for all users failed: $($_.Exception.Message)")
        }
    }
    foreach ($package in $provisioned) {
        try {
            Remove-TuneupAppxProvisionedPackage -Package $package
            $changed++
        } catch {
            $problems.Add("removing the provisioned package $($package.PackageName) failed: $($_.Exception.Message)")
        }
    }
    if (-not $problems.Count) { return }
    $message = $problems -join '; '
    # Some removal worked: the app is partly gone, which is not the same as a failure.
    if ($changed) { return (New-TuneupOutcome -Partial -Detail $message) }
    throw $message
}

# winget exit codes that mean the app is there already: APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
# (0x8A150061, what install --no-upgrade returns for an installed app) and
# APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE (0x8A15002B), in case a winget version answers that.
$script:WingetSuccessCode = @(0, -1978335135, -1978335189)

function Get-TuneupWingetPath {
    $command = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) { $command.Source }
}

function Invoke-TuneupWinget {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $path = Get-TuneupWingetPath
    if (-not $path) { throw "winget is not available for this user (run the undo from the signed-in user's elevated prompt)" }
    # winget writes UTF-8, but PowerShell decodes native output with the console code page (OEM by
    # default), which garbles accents in its messages. Switch for the call and put the page back.
    $previous = $null
    try {
        $previous = [Console]::OutputEncoding
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    } catch {
        # No console is attached (for example a hosted run): keep the default decoding.
        $previous = $null
    }
    try {
        Invoke-TuneupNative -FilePath $path -Arguments $Arguments
    } finally {
        if ($null -ne $previous) { [Console]::OutputEncoding = $previous }
    }
}

function Get-TuneupWingetInstallArgument {
    param([Parameter(Mandatory)][string]$StoreId)
    'install', '--id', $StoreId, '--source', 'msstore', '--exact', '--no-upgrade', '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity'
}

function Test-TuneupAppxInstalledForCurrentUser {
    param([Parameter(Mandatory)][string]$Name)
    @(Get-AppxPackage -Name $Name -ErrorAction Stop | Where-Object { $_.Name -eq $Name }).Count -gt 0
}

function Restore-AppxTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    $name = [string]$Tweak.set.name
    $manual = "winget install --id $($Tweak.set.storeId) --source msstore"
    # Whose copy it is was already decided when the entry was read: one that belongs to another account
    # never gets here (Get-TuneupRunJournal leaves it pending for its owner).
    # A state saved before the user fields existed only knows that someone had the app: assume the current user.
    $currentUserHad = [bool]$State.installedUsers
    if ($null -ne $State.PSObject.Properties['currentUserHad']) { $currentUserHad = [bool]$State.currentUserHad }
    $savedOthers = 0
    if ($null -ne $State.PSObject.Properties['otherUsers']) { $savedOthers = [int]$State.otherUsers }
    Clear-TuneupAppxCache
    $reinstalled = $false
    if ($currentUserHad -and -not (Test-TuneupAppxInstalledForCurrentUser -Name $name)) {
        $result = Invoke-TuneupWinget -Arguments @(Get-TuneupWingetInstallArgument -StoreId $Tweak.set.storeId)
        if ($script:WingetSuccessCode -notcontains $result.ExitCode) {
            throw "winget could not reinstall $name ($($Tweak.set.storeId)), exit code $($result.ExitCode): $($result.Output)"
        }
        Clear-TuneupAppxCache
        $reinstalled = $true
    }
    # What the Store cannot give back, judged by what the system holds now: a provisioning or another
    # user's copy that is still there was never lost, whatever the state saved before the removal says.
    # What cannot be read now is taken from the saved state.
    $provisionedLost = [bool]$State.provisioned
    try {
        if ($provisionedLost -and @(Get-TuneupAppxProvisionedPackage -Name $name).Count -gt 0) { $provisionedLost = $false }
    } catch {
        $provisionedLost = [bool]$State.provisioned
    }
    $others = $savedOthers
    if ($savedOthers -gt 0) {
        try {
            $me = Get-TuneupCurrentUserSid
            $othersNow = @(Get-TuneupAppxInstalledSid -Packages @(Get-TuneupAppxPackage -Name $name) | Where-Object { $_ -ne $me }).Count
            $others = [Math]::Max(0, $savedOthers - $othersNow)
        } catch {
            $others = $savedOthers
        }
    }
    $notes = New-Object System.Collections.Generic.List[string]
    if ($provisionedLost) { $notes.Add('not provisioned again for new users') }
    if ($others -gt 0) { $notes.Add("$others other $(if ($others -eq 1) { 'user' } else { 'users' }) not restored") }
    if ($reinstalled) {
        $detail = $notes -join '; '
        if ($others -gt 0) { $detail += ". Each of them can reinstall it with: $manual" }
        return (New-TuneupOutcome -Reason 'reinstalled' -Detail $detail)
    }
    if (-not $notes.Count) { return }
    # The current user kept the app and only the provisioning is gone: a note, not a reason.
    if ($currentUserHad -and $others -eq 0) { return (New-TuneupOutcome -Detail ($notes -join '; ')) }
    $reason = $(if ($others -gt 0) { 'installed-for-other-users' } else { 'not-reprovisioned' })
    New-TuneupOutcome -Reason $reason -Detail "$($notes -join '; '). To install it by hand: $manual"
}
