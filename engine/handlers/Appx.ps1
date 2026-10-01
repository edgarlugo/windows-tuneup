# Appx package names look like Microsoft.BingNews; Store ids are the 12-character product ids
# that winget uses with --source msstore.
$script:AppxNamePattern = '^[A-Za-z0-9][A-Za-z0-9.-]{2,49}$'
$script:StoreIdPattern = '^[0-9A-Z]{12}$'

function Test-AppxTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $set = $Tweak.set
    if ([string]$set.name -cnotmatch $script:AppxNamePattern) { 'has an invalid appx package name' }
    if ([string]$set.storeId -cnotmatch $script:StoreIdPattern) { 'needs a Microsoft Store id (12 capital letters or digits) in set.storeId' }
    if ($set.action -cne 'remove') { "has an invalid appx action '$($set.action)'" }
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
}

function Get-TuneupAppxPackage {
    param([Parameter(Mandatory)][string]$Name)
    # -Name takes wildcards, so only the exact name is kept.
    Get-AppxPackage -AllUsers -Name $Name -ErrorAction Stop | Where-Object { $_.Name -eq $Name }
}

function Get-TuneupAppxProvisionedPackage {
    param([Parameter(Mandatory)][string]$Name)
    Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $Name }
}

function Remove-TuneupAppxPackage {
    param([Parameter(Mandatory)]$Package)
    Remove-AppxPackage -Package $Package.PackageFullName -AllUsers -ErrorAction Stop
}

function Remove-TuneupAppxProvisionedPackage {
    param([Parameter(Mandatory)]$Package)
    Remove-AppxProvisionedPackage -Online -PackageName $Package.PackageName -AllUsers -ErrorAction Stop | Out-Null
}

function Test-TuneupAppxInstalledForAnyUser {
    param([AllowEmptyCollection()][object[]]$Packages = @())
    # -AllUsers also lists packages that are only staged for a user (provisioned, never installed).
    foreach ($package in $Packages) {
        foreach ($user in @($package.PackageUserInformation)) {
            if ([string]$user.InstallState -eq 'Installed') { return $true }
        }
    }
    $false
}

function Get-AppxTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.name
    $installed = @(Get-TuneupAppxPackage -Name $name)
    $provisioned = @(Get-TuneupAppxProvisionedPackage -Name $name)
    $versions = @(@($installed | ForEach-Object { [string]$_.Version }) + @($provisioned | ForEach-Object { [string]$_.Version }) | Where-Object { $_ })
    [pscustomobject]@{
        installedUsers = (Test-TuneupAppxInstalledForAnyUser -Packages $installed)
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
    $changed = 0
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($package in @(Get-TuneupAppxPackage -Name $name)) {
        try {
            Remove-TuneupAppxPackage -Package $package
            $changed++
        } catch {
            $problems.Add("removing $($package.PackageFullName) for all users failed: $($_.Exception.Message)")
        }
    }
    foreach ($package in @(Get-TuneupAppxProvisionedPackage -Name $name)) {
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

# winget: APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED (0x8A150061).
$script:WingetAlreadyInstalled = -1978335135

function Get-TuneupWingetPath {
    $command = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) { $command.Source }
}

function Invoke-TuneupWinget {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $path = Get-TuneupWingetPath
    if (-not $path) { throw 'winget is not available. Install App Installer from the Microsoft Store and run the undo again.' }
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
    'install', '--id', $StoreId, '--source', 'msstore', '--exact', '--accept-package-agreements', '--accept-source-agreements', '--silent', '--disable-interactivity'
}

function Test-TuneupAppxInstalledForCurrentUser {
    param([Parameter(Mandatory)][string]$Name)
    @(Get-AppxPackage -Name $Name -ErrorAction Stop | Where-Object { $_.Name -eq $Name }).Count -gt 0
}

function Restore-AppxTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    $name = [string]$Tweak.set.name
    $storeId = [string]$Tweak.set.storeId
    if (-not $State.installedUsers) {
        if ($State.provisioned) {
            # Provisioning needs the package file, which the Store does not hand out.
            return (New-TuneupOutcome -Reason 'not-reprovisioned' -Detail "$name was only provisioned for new users and cannot be provisioned again. To install it: winget install --id $storeId --source msstore")
        }
        return
    }
    if (Test-TuneupAppxInstalledForCurrentUser -Name $name) { return }
    $result = Invoke-TuneupWinget -Arguments @(Get-TuneupWingetInstallArgument -StoreId $storeId)
    if ($result.ExitCode -ne 0 -and $result.ExitCode -ne $script:WingetAlreadyInstalled) {
        throw "winget could not reinstall $name ($storeId), exit code $($result.ExitCode): $($result.Output)"
    }
    New-TuneupOutcome -Reason 'reinstalled' -Detail "$name was reinstalled from the Microsoft Store for the current user only; it was not provisioned again for new users"
}