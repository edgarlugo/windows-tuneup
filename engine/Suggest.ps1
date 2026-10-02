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

# The signals, in the order of the document; each one but managed suggests the profile of its name.
$script:SuggestSignals = @('dev', 'gaming', 'laptop', 'work', 'legacy', 'managed')
$script:SuggestProfiles = [ordered]@{ dev = 'dev'; gaming = 'gaming'; laptop = 'laptop'; work = 'work'; legacy = 'legacy' }
# Never suggested: only the user can want them.
$script:SuggestQuestions = @('privacy', 'lite')
$script:LegacyRamGB = 8
# What counts as a product of a signal: a pattern for the display name of an uninstall entry, for the
# name of a Store package of the user, or both. Name is the evidence: a fixed product name, never the
# display name itself. The Xbox app and the Game Bar come with Windows 11, so Gaming Services (which the
# Xbox app installs to play Game Pass) is what says games.
$script:SuggestProducts = @(
    [pscustomobject]@{ Signal = 'dev'; Name = 'Visual Studio'; Program = '^Visual Studio (Community|Professional|Enterprise|Build Tools) '; Appx = $null }
    [pscustomobject]@{ Signal = 'dev'; Name = 'Visual Studio Code'; Program = '^Microsoft Visual Studio Code'; Appx = $null }
    [pscustomobject]@{ Signal = 'dev'; Name = 'JetBrains'; Program = '^(JetBrains |IntelliJ IDEA|PyCharm|WebStorm|CLion|GoLand|PhpStorm|RubyMine|DataGrip)'; Appx = $null }
    [pscustomobject]@{ Signal = 'dev'; Name = 'Android Studio'; Program = '^Android Studio'; Appx = $null }
    [pscustomobject]@{ Signal = 'dev'; Name = 'Git'; Program = '^Git( version [\d.]+)?$'; Appx = $null }
    [pscustomobject]@{ Signal = 'dev'; Name = 'Node.js'; Program = '^Node\.js'; Appx = $null }
    [pscustomobject]@{ Signal = 'dev'; Name = 'Python'; Program = '^Python \d'; Appx = '^PythonSoftwareFoundation\.Python\.' }
    [pscustomobject]@{ Signal = 'dev'; Name = 'JDK'; Program = '(Java\(TM\) SE Development Kit|\bJDK\b|OpenJDK|Corretto)'; Appx = $null }
    [pscustomobject]@{ Signal = 'dev'; Name = 'WSL'; Program = '^Windows Subsystem for Linux'; Appx = '^MicrosoftCorporationII\.WindowsSubsystemForLinux$' }
    [pscustomobject]@{ Signal = 'gaming'; Name = 'Steam'; Program = '^Steam$'; Appx = $null }
    [pscustomobject]@{ Signal = 'gaming'; Name = 'Epic Games Launcher'; Program = '^Epic Games Launcher$'; Appx = $null }
    [pscustomobject]@{ Signal = 'gaming'; Name = 'EA app'; Program = '^EA app$'; Appx = $null }
    [pscustomobject]@{ Signal = 'gaming'; Name = 'Xbox Gaming Services'; Program = $null; Appx = '^Microsoft\.GamingServices$' }
)

# Runs one detector. One that fails gives nothing and a warning: the signals that use it may be missing,
# and the document is still written.
function Invoke-TuneupDetector {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$What, [Parameter(Mandatory)][scriptblock]$Detector)
    try {
        [pscustomobject]@{ Ok = $true; Value = (& $Detector) }
    } catch {
        Write-Warning "Could not check $What, so the signals that use it may be missing: $($_.Exception.Message)"
        [pscustomobject]@{ Ok = $false; Value = $null }
    }
}

function Get-TuneupSuggestion {
    [CmdletBinding()]
    param()
    $programs = Invoke-TuneupDetector -What 'the installed programs' -Detector { Get-TuneupInstalledProgramName }
    $packages = Invoke-TuneupDetector -What 'the Store apps of this user' -Detector { Get-TuneupUserAppxName }
    $battery = Invoke-TuneupDetector -What 'the battery' -Detector { Test-TuneupHasBattery }
    $computer = Invoke-TuneupDetector -What 'the domain and the memory of the computer' -Detector { Get-TuneupComputerSystem }
    $entra = Invoke-TuneupDetector -What 'the Entra ID join' -Detector { Test-TuneupEntraJoined }
    $mdm = Invoke-TuneupDetector -What 'the MDM enrollment' -Detector { Test-TuneupMdmEnrollment }
    $disk = Invoke-TuneupDetector -What 'the disk of the system drive' -Detector { Get-TuneupSystemDiskMediaType }

    $evidence = @{}
    foreach ($id in $script:SuggestSignals) { $evidence[$id] = New-Object System.Collections.Generic.List[string] }
    $add = { param($Signal, $Name) if (-not $evidence[$Signal].Contains($Name)) { $evidence[$Signal].Add($Name) } }
    $programNames = @($programs.Value | Where-Object { $_ })
    $packageNames = @($packages.Value | Where-Object { $_ })
    foreach ($product in $script:SuggestProducts) {
        $pattern = $product.Program
        $foundProgram = $pattern -and @($programNames | Where-Object { $_ -match $pattern }).Count
        $pattern = $product.Appx
        $foundPackage = $pattern -and @($packageNames | Where-Object { $_ -match $pattern }).Count
        if ($foundProgram -or $foundPackage) { & $add $product.Signal $product.Name }
    }
    if ($battery.Value -eq $true) { & $add 'laptop' 'battery' }
    if ($null -ne $computer.Value -and $computer.Value.PartOfDomain) {
        & $add 'work' 'domain'
        & $add 'managed' 'domain'
    }
    if ($entra.Value -eq $true) { & $add 'work' 'Entra ID' }
    if ($mdm.Value -eq $true) {
        & $add 'work' 'MDM'
        & $add 'managed' 'MDM'
    }
    if ($null -ne $computer.Value -and $computer.Value.TotalPhysicalMemory) {
        # Windows reports a little less than what is installed: 8 GB comes as 7.8.
        $ramGB = [int][math]::Round([double]$computer.Value.TotalPhysicalMemory / 1GB)
        if ($ramGB -lt $script:LegacyRamGB) { & $add 'legacy' "RAM $ramGB GB" }
    }
    if ($disk.Value -eq 'HDD') { & $add 'legacy' 'HDD' }

    $signals = @(foreach ($id in $script:SuggestSignals) {
        [pscustomobject]@{ id = $id; detected = ($evidence[$id].Count -gt 0); evidence = [string[]]$evidence[$id].ToArray() }
    })
    $suggestions = @([pscustomobject]@{ profile = 'base'; signals = [string[]]@() }) + @(foreach ($id in $script:SuggestProfiles.Keys) {
        if ($evidence[$id].Count) { [pscustomobject]@{ profile = $script:SuggestProfiles[$id]; signals = [string[]]@($id) } }
    })
    $questions = @(foreach ($id in $script:SuggestQuestions) { [pscustomobject]@{ id = $id; text = Get-TuneupText -Key "suggest.question.$id" } })
    [pscustomobject]@{ schemaVersion = 1; command = 'suggest'; signals = $signals; suggestions = $suggestions; questions = $questions }
}

function Write-TuneupSuggestReport {
    param(
        [Parameter(Mandatory)]$Document,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Document -Warnings $Warnings); return }
    Write-Host (Get-TuneupText -Key 'suggest.signals')
    foreach ($signal in $Document.signals) {
        $label = Get-TuneupText -Key "suggest.signal.$($signal.id)"
        if ($signal.detected) { Write-Host (Get-TuneupText -Key 'suggest.detected' -Format $label, (@($signal.evidence) -join ', ')) -ForegroundColor Cyan }
        else { Write-Host (Get-TuneupText -Key 'suggest.notDetected' -Format $label) -ForegroundColor DarkGray }
    }
    $profileIds = @($Document.suggestions | ForEach-Object { $_.profile })
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'suggest.profiles' -Format ($profileIds -join ', '))
    $toPlan = @($profileIds | Where-Object { $_ -ne 'base' })
    Write-Host (Get-TuneupText -Key 'suggest.try' -Format $(if ($toPlan.Count) { $toPlan -join ',' } else { 'base' }))
    Write-Host (Get-TuneupText -Key 'suggest.questions')
    foreach ($question in $Document.questions) { Write-Host "  - $($question.text)" }
    if (@($Document.signals | Where-Object { $_.id -eq 'managed' -and $_.detected }).Count) {
        Write-Host ''
        Write-Host (Get-TuneupText -Key 'suggest.managed') -ForegroundColor Yellow
    }
}
