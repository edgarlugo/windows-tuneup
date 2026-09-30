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

function Get-TuneupFamily {
    param([Parameter(Mandatory)][int]$Build)
    if ($Build -ge 22000) { '11' } else { '10' }
}

function Test-TuneupAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

function Get-TuneupEnvironment {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$currentVersion.CurrentBuild
    $edition = ConvertTo-TuneupEdition -EditionId ([string]$currentVersion.EditionID)
    if ($currentVersion.InstallationType -eq 'Server') { $edition = 'Server' }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    [pscustomobject]@{
        Build         = $build
        UBR           = [int]$currentVersion.UBR
        Family        = Get-TuneupFamily -Build $build
        Edition       = $edition
        IsServer      = ($edition -eq 'Server')
        IsManaged     = ([bool]$computer.PartOfDomain -or (Test-TuneupMdmEnrollment))
        IsAdmin       = [bool](Test-TuneupAdmin)
        HasBattery    = (@(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0)
        PendingReboot = [bool](Test-TuneupPendingReboot)
    }
}
