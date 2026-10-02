# -Suggest (design, section 13.2): what this machine has, read only and without administrator, and the
# profiles that fit it. Each detector reads one source and decides nothing, so a test can stand in for
# it; Get-TuneupSuggestion turns what they read into signals.

# The uninstall entries of the machine (64 and 32 bits) and of the current user.
$script:UninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
)
$script:EntraJoinInfo = 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'
$script:StorageNamespace = 'root/Microsoft/Windows/Storage'
# MediaType of MSFT_PhysicalDisk.
$script:DiskMediaTypes = @{ 0 = 'Unspecified'; 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }

# The display names of the installed programs. A root that does not exist is skipped; one that exists
# but cannot be read fails the detector.
function Get-TuneupInstalledProgramName {
    param([string[]]$Root = $script:UninstallRoots)
    foreach ($path in $Root) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        Get-Item -LiteralPath $path -ErrorAction Stop | Out-Null
        foreach ($key in @(Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue)) {
            $name = $key.GetValue('DisplayName')
            if ($name) { [string]$name }
        }
    }
}

# The names of the Store packages of the current user (the Appx module of Windows PowerShell).
function Get-TuneupUserAppxName {
    foreach ($package in @(Get-AppxPackage -ErrorAction Stop)) { [string]$package.Name }
}

function Get-TuneupComputerSystem {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    [pscustomobject]@{ PartOfDomain = [bool]$computer.PartOfDomain; TotalPhysicalMemory = [double]$computer.TotalPhysicalMemory }
}

# Joined to Entra ID (Azure AD, also hybrid): Windows keeps one entry per join under JoinInfo. A work
# account added to Windows only (registered, not joined) leaves no entry there.
function Test-TuneupEntraJoined {
    param([string]$Path = $script:EntraJoinInfo)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    @(Get-ChildItem -LiteralPath $Path -ErrorAction Stop).Count -gt 0
}

# HDD, SSD, SCM or Unspecified for the physical disk that holds the system drive. The Storage classes
# can be read without administrator. A system drive on Storage Spaces or RAID has no physical disk with
# its disk number: that fails, and the caller reports it.
function Get-TuneupSystemDiskMediaType {
    $letter = (Get-TuneupSystemDrive).Substring(0, 1)
    $partition = @(Get-CimInstance -Namespace $script:StorageNamespace -ClassName MSFT_Partition -Filter "DriveLetter = '$letter'" -ErrorAction Stop) | Select-Object -First 1
    if ($null -eq $partition) { throw "No partition has the letter $letter" }
    $disk = @(Get-CimInstance -Namespace $script:StorageNamespace -ClassName MSFT_PhysicalDisk -Filter "DeviceId = '$($partition.DiskNumber)'" -ErrorAction Stop) | Select-Object -First 1
    if ($null -eq $disk) { throw "Cannot find physical disk $($partition.DiskNumber) of the system drive" }
    $type = $script:DiskMediaTypes[[int]$disk.MediaType]
    $(if ($type) { $type } else { 'Unspecified' })
}
