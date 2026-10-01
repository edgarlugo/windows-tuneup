function ConvertTo-TuneupEdition {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$EditionId)
    switch -Regex ($EditionId) {
        '^Server' { return 'Server' }
        '^Core' { return 'Home' }
        '^Professional' { return 'Pro' }
        '^(IoT)?Enterprise' { return 'Enterprise' }
        '^Education' { return 'Education' }
        default { return 'Unknown' }
    }
}

# Enterprise multi-session reports a Server-looking EditionID on a client OS, so the installation
# type decides whether the machine is a server.
function Resolve-TuneupEdition {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$EditionId,
        [AllowEmptyString()][string]$InstallationType = ''
    )
    if ($InstallationType -like 'Server*') { return 'Server' }
    if ($InstallationType -eq 'Client' -and $EditionId -match '^Server') { return 'Enterprise' }
    ConvertTo-TuneupEdition -EditionId $EditionId
}

function Get-TuneupFamily {
    param([Parameter(Mandatory)][int]$Build)
    if ($Build -ge 22000) { '11' } else { '10' }
}

function Test-TuneupAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# The accounts that own explorer.exe in the session of this process: who is signed in at this desktop.
function Get-TuneupSessionUserSid {
    $session = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'explorer.exe' AND SessionId = $session" -ErrorAction Stop |
        ForEach-Object { [string](Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction Stop).Sid } |
        Where-Object { $_ } | Sort-Object -Unique)
}

# True only when the one account at this desktop is the account of this process. Elevating with
# another administrator's password keeps the session but not the account: HKCU, AppData and the
# user's files would be those of the administrator. Without a desktop to compare with, false.
function Test-TuneupSessionUser {
    try {
        $owners = @(Get-TuneupSessionUserSid)
    } catch {
        return $false
    }
    $owners.Count -eq 1 -and $owners[0] -eq (Get-TuneupCurrentUserSid)
}

function Test-TuneupMdmEnrollment {
    $root = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
    if (-not (Test-Path -LiteralPath $root)) { return $false }
    foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
        $provider = (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).ProviderID
        if ($provider -eq 'MS DM Server') { return $true }
    }
    $false
}

function Test-TuneupPendingReboot {
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { return $true }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { return $true }
    $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    [bool]$sessionManager.PendingFileRenameOperations
}

# SMBIOS chassis types of portable machines: portable, laptop, notebook, sub-notebook, tablet,
# convertible and detachable.
$script:PortableChassisTypes = @(8, 9, 10, 14, 30, 31, 32)

# A battery on a portable chassis. A desktop whose UPS reports as a battery has a battery but a
# desktop chassis, so it does not count. When the chassis cannot be read, the battery decides (so a
# desktop with a UPS and no chassis information still counts as having one).
function Test-TuneupHasBattery {
    if (-not @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue).Count) { return $false }
    $types = @(Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue |
        ForEach-Object { $_.ChassisTypes } | Where-Object { $null -ne $_ })
    if (-not $types.Count) { return $true }
    @($types | Where-Object { $script:PortableChassisTypes -contains [int]$_ }).Count -gt 0
}

function Get-TuneupEnvironment {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$currentVersion.CurrentBuild
    $edition = Resolve-TuneupEdition -EditionId ([string]$currentVersion.EditionID) -InstallationType ([string]$currentVersion.InstallationType)
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $isAdmin = [bool](Test-TuneupAdmin)
    [pscustomobject]@{
        Build         = $build
        UBR           = [int]$currentVersion.UBR
        Family        = Get-TuneupFamily -Build $build
        Edition       = $edition
        IsServer      = ($edition -eq 'Server')
        IsManaged     = ([bool]$computer.PartOfDomain -or (Test-TuneupMdmEnrollment))
        IsAdmin       = $isAdmin
        # Only an elevated process can be another account than the one at the desktop.
        IsSessionUser = (-not $isAdmin) -or [bool](Test-TuneupSessionUser)
        HasBattery    = [bool](Test-TuneupHasBattery)
        PendingReboot = [bool](Test-TuneupPendingReboot)
    }
}
