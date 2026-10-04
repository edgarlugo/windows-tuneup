# -Startup (design, section 15): what starts with Windows or runs in the background. This file holds where
# each entry comes from, its id, the helpers that read a command line, the detectors (one per source, each
# one a function a test can stand in for), the list of entries and the startup document. Nothing here
# changes the system: turning an entry off is StartupTweak.ps1 and Invoke-TuneupStartupCommand.

$script:StartupIdPattern = '^startup\.[a-z0-9-]+\.[a-z0-9-]+$'
$script:StartupSlugLength = 32
$script:StartupApprovedRoot = @{
    user    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    machine = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
}
# Every source: its scope and, for the ones Task Manager turns off, the StartupApproved key it keeps the
# choice in. The order is the order of the list.
$script:StartupSources = [ordered]@{
    'run-user'          = [pscustomobject]@{ Scope = 'user'; Approved = "$($script:StartupApprovedRoot.user)\Run" }
    'run-machine'       = [pscustomobject]@{ Scope = 'machine'; Approved = "$($script:StartupApprovedRoot.machine)\Run" }
    'run32-machine'     = [pscustomobject]@{ Scope = 'machine'; Approved = "$($script:StartupApprovedRoot.machine)\Run32" }
    'runonce-user'      = [pscustomobject]@{ Scope = 'user'; Approved = $null }
    'runonce-machine'   = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'runonce32-machine' = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'policy-user'       = [pscustomobject]@{ Scope = 'user'; Approved = $null }
    'policy-machine'    = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'folder-user'       = [pscustomobject]@{ Scope = 'user'; Approved = "$($script:StartupApprovedRoot.user)\StartupFolder" }
    'folder-machine'    = [pscustomobject]@{ Scope = 'machine'; Approved = "$($script:StartupApprovedRoot.machine)\StartupFolder" }
    'store-app'         = [pscustomobject]@{ Scope = 'user'; Approved = $null }
    'task'              = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'service'           = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
    'driver'            = [pscustomobject]@{ Scope = 'machine'; Approved = $null }
}
# The Run keys and their sources. HKCU has no WOW6432Node copy of Run on 64-bit Windows (it is not
# redirected), so it is not read.
$script:StartupRunKeys = @(
    [pscustomobject]@{ Source = 'run-user'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
    [pscustomobject]@{ Source = 'run-machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' }
    [pscustomobject]@{ Source = 'run32-machine'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
    [pscustomobject]@{ Source = 'runonce-user'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' }
    [pscustomobject]@{ Source = 'runonce-machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' }
    [pscustomobject]@{ Source = 'runonce32-machine'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce' }
    [pscustomobject]@{ Source = 'policy-user'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run' }
    [pscustomobject]@{ Source = 'policy-machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run' }
)

# startup.<source>.<slug>-<hash>: the slug is the key in lowercase with everything but a-z and 0-9 turned
# into hyphens (32 characters at most, 'entry' when nothing is left), and the hash the first 8 hexadecimal
# digits of the SHA256 of <source>|<key in lowercase>. The same entry gets the same id in every run,
# elevated or not; the registry and the scheduled tasks do not tell case apart, so neither does the id.
function Get-TuneupStartupId {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Key)
    $normal = $Key.ToLowerInvariant()
    $slug = ($normal -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt $script:StartupSlugLength) { $slug = $slug.Substring(0, $script:StartupSlugLength).TrimEnd('-') }
    if (-not $slug) { $slug = 'entry' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$Source|$normal"))
    } finally {
        $sha.Dispose()
    }
    $short = -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })
    "startup.$Source.$slug-$short"
}

function Test-TuneupStartupId {
    param([AllowNull()][AllowEmptyString()][string]$Id)
    [bool]($Id -cmatch $script:StartupIdPattern)
}

# user or machine, from the source written in the id; nothing for an id that is not one of -Startup.
function Get-TuneupStartupIdScope {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-TuneupStartupId -Id $Id)) { return }
    $source = $script:StartupSources[$Id.Split('.')[1]]
    if ($null -ne $source) { $source.Scope }
}

# The variables a startup command uses, from the folders of Windows and of the account, never from the
# environment of the process (any program of the account can change it).
function Get-TuneupStartupPathVariable {
    $windows = [Environment]::GetFolderPath('Windows')
    [ordered]@{
        'SystemRoot'              = $windows
        'windir'                  = $windows
        'SystemDrive'             = ([System.IO.Path]::GetPathRoot($windows)).TrimEnd('\')
        'ProgramFiles'            = [Environment]::GetFolderPath('ProgramFiles')
        'ProgramFiles(x86)'       = [Environment]::GetFolderPath('ProgramFilesX86')
        'CommonProgramFiles'      = [Environment]::GetFolderPath('CommonProgramFiles')
        'CommonProgramFiles(x86)' = [Environment]::GetFolderPath('CommonProgramFilesX86')
        'ProgramData'             = [Environment]::GetFolderPath('CommonApplicationData')
        'LOCALAPPDATA'            = [Environment]::GetFolderPath('LocalApplicationData')
        'APPDATA'                 = [Environment]::GetFolderPath('ApplicationData')
        'USERPROFILE'             = [Environment]::GetFolderPath('UserProfile')
    }
}

# A text with those variables written out; any other variable stays as it is.
function Expand-TuneupStartupPath {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if (-not $Text) { return $Text }
    $variables = Get-TuneupStartupPathVariable
    $evaluator = {
        param($match)
        $name = $match.Groups[1].Value
        foreach ($variable in $variables.Keys) {
            if ($variable -ieq $name -and $variables[$variable]) { return $variables[$variable] }
        }
        $match.Value
    }.GetNewClosure()
    [regex]::Replace($Text, '%([^%]+)%', $evaluator)
}

# The program a command line runs, as a full path, or nothing. Quoted: what is between the first quotes
# (some tasks keep it quoted twice). Not quoted: up to the first extension of a program followed by a space
# or the end, or the first word. A bare name is in System32; \SystemRoot\, System32\ and \??\ are the
# kernel ways of writing a driver path.
function Get-TuneupCommandProgram {
    param([AllowNull()][AllowEmptyString()][string]$Command)
    $text = ([string](Expand-TuneupStartupPath -Text ([string]$Command))).Trim()
    if (-not $text) { return }
    if ($text.StartsWith('"')) {
        $inner = $text.TrimStart('"')
        $end = $inner.IndexOf('"')
        $program = $(if ($end -ge 0) { $inner.Substring(0, $end) } else { $inner })
    } else {
        $match = [regex]::Match($text, '^(?<program>.+?\.(?:exe|com|bat|cmd|lnk|scr|sys|ps1))(?=\s|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $program = $(if ($match.Success) { $match.Groups['program'].Value } else { ($text -split '\s+')[0] })
    }
    $program = $program.Trim()
    if ($program.StartsWith('\??\')) { $program = $program.Substring(4) }
    $windows = [Environment]::GetFolderPath('Windows')
    if ($program -match '^\\SystemRoot\\') { $program = Join-Path $windows $program.Substring('\SystemRoot\'.Length) }
    elseif ($program -match '^system32\\') { $program = Join-Path $windows $program }
    elseif ($program -notmatch '\\') { $program = Join-Path ([Environment]::SystemDirectory) $program }
    if ($program -notmatch '^[A-Za-z]:\\') { return }
    $program
}

# The CN of a certificate subject (the name of who signed), or nothing.
function Get-TuneupCommonName {
    param([AllowNull()][AllowEmptyString()][string]$DistinguishedName)
    $match = [regex]::Match([string]$DistinguishedName, '(?:^|,\s*)CN=(?:"(?<value>[^"]*)"|(?<value>[^,]*))')
    if ($match.Success -and $match.Groups['value'].Value.Trim()) { $match.Groups['value'].Value.Trim() }
}

# Task Manager keeps one binary value per entry under StartupApproved: an even first byte (02, or 06 for
# some entries of Windows) is on, an odd one (03, followed by when it was turned off) is off, and no value
# is on (design, section 15.3).
function Test-TuneupStartupApprovedEnabled {
    param([AllowNull()][object[]]$Value)
    $bytes = @($Value | Where-Object { $null -ne $_ })
    if (-not $bytes.Count) { return $true }
    ([int]$bytes[0] -band 1) -eq 0
}

# One entry of the list. Target holds what turning it off needs (the StartupApproved key and value, the
# key of a Store task, the task, the service); it never goes to the JSON document.
function New-TuneupStartupEntry {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$Command,
        [AllowNull()][AllowEmptyString()][string]$Path,
        [bool]$Enabled = $true,
        [bool]$Policy = $false,
        [hashtable]$Target = @{}
    )
    $info = $script:StartupSources[$Source]
    if ($null -eq $info) { throw "Unknown startup source '$Source'" }
    [pscustomobject]@{
        id                = Get-TuneupStartupId -Source $Source -Key $Key
        name              = $Name
        source            = $Source
        scope             = $info.Scope
        key               = $Key
        command           = $(if ($Command) { $Command } else { $null })
        path              = $(if ($Path) { $Path } else { $null })
        publisher         = $null
        enabled           = $Enabled
        policy            = $Policy
        running           = $null
        memoryMB          = $null
        cpuSeconds        = $null
        protected         = $null
        canDisable        = $false
        needsAdmin        = ($info.Scope -eq 'machine')
        recommended       = $false
        recommendedReason = $null
        notRecommendedReason = $null
        uninstall         = $null
        target            = [pscustomobject]$Target
    }
}

$script:StoreTaskRoot = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
$script:SecurityCenterClasses = @('AntiVirusProduct', 'FirewallProduct')
$script:StartupSignerCache = @{}
$script:ServiceRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
# The roots of Microsoft that sign Windows and its updates (Microsoft Root Authority, Microsoft Root
# Certificate Authority, and the 2010 and 2011 ones), by thumbprint.
$script:MicrosoftRootThumbprints = @(
    'A43489159A520F0D93D032CCAF37E7FE20A8B419'
    'CDD4EEAE6000AC7F40C3802C171E30148030C072'
    '3B1EFD3A66EA28B16697394703A72CA340A05BD5'
    '8F43288AD272F3103B6FB1428485EA3014C0BCFE'
)
# The service hosts of Windows: a service they run is a service of Windows (one of another publisher would
# be a ServiceDll in a shared group, which -Startup does not read).
$script:WindowsServiceHosts = @('svchost.exe', 'lsass.exe')

# The values of a Run key, name and command as they are written (not expanded). A key that does not exist
# gives nothing; one that exists but cannot be read fails.
function Get-TuneupStartupRunValue {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    try {
        foreach ($name in $key.GetValueNames()) {
            # The default value of the key is not an entry.
            if (-not $name) { continue }
            [pscustomobject]@{ Name = $name; Command = [string]$key.GetValue($name, $null, 'DoNotExpandEnvironmentNames') }
        }
    } finally {
        $key.Close()
    }
}

# The binary values of a StartupApproved key, by name (a table that does not tell case apart, like the
# registry). An empty table when the key does not exist.
function Get-TuneupStartupApprovedValue {
    param([Parameter(Mandatory)][string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    try {
        foreach ($name in $key.GetValueNames()) {
            if ($name -and $key.GetValueKind($name) -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $values[$name] = [byte[]]$key.GetValue($name) }
        }
    } finally {
        $key.Close()
    }
    $values
}

# The files of a startup folder (desktop.ini and subfolders are not entries). Nothing when the folder does
# not exist.
function Get-TuneupStartupFolderItem {
    param([AllowEmptyString()][string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction Stop)) {
        if ($file.Name -ieq 'desktop.ini') { continue }
        [pscustomobject]@{ Name = $file.Name; FullName = $file.FullName }
    }
}

# Where a shortcut points and with which arguments. CreateShortcut only reads the file: nothing is saved.
function Get-TuneupShortcutTarget {
    param([Parameter(Mandatory)][string]$Path)
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($Path)
        [pscustomobject]@{ Target = [string]$link.TargetPath; Arguments = [string]$link.Arguments }
    } finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

# The keys of SystemAppData\<package family>\<task> that hold a State: what Windows keeps for the startup
# tasks of Store apps (StartupTaskState). Whether a key is really a startup task is decided against the
# manifest of the package (Get-TuneupStartupStoreEntry).
function Get-TuneupStartupStoreTask {
    param([string]$Root = $script:StoreTaskRoot)
    if (-not (Test-Path -LiteralPath $Root)) { return }
    foreach ($package in @(Get-ChildItem -LiteralPath $Root -ErrorAction Stop)) {
        foreach ($task in @(Get-ChildItem -LiteralPath $package.PSPath -ErrorAction Stop)) {
            $state = $task.GetValue('State')
            if ($null -eq $state) { continue }
            [pscustomobject]@{
                PackageFamilyName = $package.PSChildName
                TaskId            = $task.PSChildName
                State             = [int]$state
                KeyPath           = "$Root\$($package.PSChildName)\$($task.PSChildName)"
            }
        }
    }
}

# The Store packages of the current user, with what -Startup needs of them.
function Get-TuneupStartupPackage {
    foreach ($package in @(Get-AppxPackage -ErrorAction Stop)) {
        [pscustomobject]@{
            PackageFamilyName = [string]$package.PackageFamilyName
            Name              = [string]$package.Name
            Publisher         = [string]$package.Publisher
            InstallLocation   = [string]$package.InstallLocation
            SignatureKind     = [string]$package.SignatureKind
        }
    }
}

# The startup tasks (Extension windows.startupTask) that a package manifest declares. The document is
# loaded without resolving anything outside it. Each task also carries the PublisherDisplayName of the
# package (the publisher that Settings shows), so the manifest is read once.
function Get-TuneupAppxManifestStartupTask {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $xml = New-Object System.Xml.XmlDocument
    $xml.XmlResolver = $null
    $xml.Load($Path)
    $publisherNode = $xml.SelectSingleNode("/*[local-name()='Package']/*[local-name()='Properties']/*[local-name()='PublisherDisplayName']")
    $publisher = $(if ($null -ne $publisherNode -and $publisherNode.InnerText.Trim()) { $publisherNode.InnerText.Trim() } else { $null })
    foreach ($node in @($xml.SelectNodes("//*[local-name()='Extension'][@Category='windows.startupTask']/*[local-name()='StartupTask']"))) {
        [pscustomobject]@{ TaskId = $node.GetAttribute('TaskId'); DisplayName = $node.GetAttribute('DisplayName'); PublisherDisplayName = $publisher }
    }
}

# The scheduled tasks outside \Microsoft\ with a sign-in or boot trigger, and the program of their first
# action. Without elevation Windows hides some tasks.
function Get-TuneupStartupScheduledTask {
    foreach ($task in @(Get-ScheduledTask -ErrorAction Stop)) {
        if ([string]$task.TaskPath -like '\Microsoft\*') { continue }
        $triggers = @($task.Triggers | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.CimClass.CimClassName })
        if (-not @($triggers | Where-Object { $_ -eq 'MSFT_TaskLogonTrigger' -or $_ -eq 'MSFT_TaskBootTrigger' }).Count) { continue }
        $action = @($task.Actions | Where-Object { $null -ne $_ -and [string]$_.CimClass.CimClassName -eq 'MSFT_TaskExecAction' }) | Select-Object -First 1
        [pscustomobject]@{
            TaskPath  = [string]$task.TaskPath
            TaskName  = [string]$task.TaskName
            State     = [string]$task.State
            Execute   = $(if ($null -ne $action) { [string]$action.Execute } else { $null })
            Arguments = $(if ($null -ne $action) { [string]$action.Arguments } else { $null })
        }
    }
}

# The services and the drivers whose start mode is Auto (delayed included).
function Get-TuneupStartupServiceItem {
    foreach ($service in @(Get-CimInstance -ClassName Win32_Service -Filter "StartMode = 'Auto'" -ErrorAction Stop)) {
        [pscustomobject]@{
            Kind = 'service'; Name = [string]$service.Name; DisplayName = [string]$service.DisplayName; PathName = [string]$service.PathName
            State = [string]$service.State; ProcessId = [int]$service.ProcessId; DelayedAutoStart = [bool]$service.DelayedAutoStart
        }
    }
    foreach ($driver in @(Get-CimInstance -ClassName Win32_SystemDriver -Filter "StartMode = 'Auto'" -ErrorAction Stop)) {
        [pscustomobject]@{
            Kind = 'driver'; Name = [string]$driver.Name; DisplayName = [string]$driver.DisplayName; PathName = [string]$driver.PathName
            State = [string]$driver.State; ProcessId = 0; DelayedAutoStart = $false
        }
    }
}

# The folders of the products of one class that Windows Security lists (its paths only: Defender gives a
# windowsdefender:// link). Windows Server has no Security Center: that fails, and the caller warns. A
# product whose program sits right in a folder that holds everything (a drive, the folder of Windows,
# System32, SysWOW64, Program Files, ProgramData) gives no folder: everything there would look protected.
function Get-TuneupSecurityProductFolder {
    param([Parameter(Mandatory)][string]$ClassName)
    $windows = [Environment]::GetFolderPath('Windows')
    $broad = @($windows, [Environment]::SystemDirectory, (Join-Path $windows 'SysWOW64'), [Environment]::GetFolderPath('ProgramFiles'),
        [Environment]::GetFolderPath('ProgramFilesX86'), [Environment]::GetFolderPath('CommonApplicationData')) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    foreach ($product in @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName $ClassName -ErrorAction Stop)) {
        foreach ($path in @($product.pathToSignedProductExe, $product.pathToSignedReportingExe)) {
            $expanded = Expand-TuneupStartupPath -Text ([string]$path)
            if ($expanded -notmatch '^[A-Za-z]:\\') { continue }
            $folder = ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($expanded))).TrimEnd('\')
            if ($folder -match '^[A-Za-z]:$' -or @($broad | Where-Object { $_ -ieq $folder }).Count) { continue }
            $folder
        }
    }
}

function Clear-TuneupFileSignerCache {
    $script:StartupSignerCache = @{}
}

# Whether the chain of a certificate reaches one of the roots of Microsoft, by thumbprint (a name can be
# copied, a thumbprint cannot). Offline: revocation is not checked, so nothing is downloaded for it.
function Test-TuneupMicrosoftRootChain {
    param([Parameter(Mandatory)]$Certificate)
    if ($Certificate -isnot [System.Security.Cryptography.X509Certificates.X509Certificate2]) { return $false }
    $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    try {
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        # The result of Build is not what counts: the elements it found are, and a root is known by its thumbprint.
        [void]$chain.Build($Certificate)
        foreach ($element in @($chain.ChainElements)) {
            if ($script:MicrosoftRootThumbprints -contains $element.Certificate.Thumbprint) { return $true }
        }
        $false
    } finally {
        $chain.Reset()
    }
}

# Who signed a file and whether Windows vouches for it, from a valid Authenticode signature (catalog
# signatures included): { Signer (the CN), IsOSBinary (Windows says it is a file of Windows), MicrosoftRoot
# (the chain reaches a root of Microsoft) }. Nothing when the signature is not valid or the file is not
# there. Each file is read once per list; one that could not be read fails once and is unknown afterwards.
function Get-TuneupFileSignature {
    param([Parameter(Mandatory)][string]$Path)
    if ($script:StartupSignerCache.ContainsKey($Path)) { return $script:StartupSignerCache[$Path] }
    $result = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        } catch {
            $script:StartupSignerCache[$Path] = $null
            throw
        }
        if ([string]$signature.Status -eq 'Valid' -and $null -ne $signature.SignerCertificate) {
            # IsOSBinary is there in Windows PowerShell 5.1; an older Signature without it is not proof.
            $isOs = $signature.PSObject.Properties['IsOSBinary']
            $result = [pscustomobject]@{
                Signer        = Get-TuneupCommonName -DistinguishedName ([string]$signature.SignerCertificate.Subject)
                IsOSBinary    = ($null -ne $isOs -and $isOs.Value -eq $true)
                MicrosoftRoot = [bool](Test-TuneupMicrosoftRootChain -Certificate $signature.SignerCertificate)
            }
        }
    }
    $script:StartupSignerCache[$Path] = $result
    $result
}

# A signature of Windows: a signer of windowsSigners that Windows vouches for (IsOSBinary) or whose chain
# reaches a root of Microsoft. The name of the signer alone is never enough.
function Test-TuneupWindowsSignature {
    param([AllowNull()]$Signature, [Parameter(Mandatory)]$Rules)
    if ($null -eq $Signature -or -not $Signature.Signer) { return $false }
    [bool](@($Rules.windowsSigners) -contains [string]$Signature.Signer -and ($Signature.IsOSBinary -or $Signature.MicrosoftRoot))
}

# Keeps a signature on an entry: the publisher it shows, and in its target the signer and whether Windows
# vouches for it (what the protections use).
function Set-TuneupStartupSignature {
    param([Parameter(Mandatory)]$Entry, [AllowNull()]$Signature, [Parameter(Mandatory)]$Rules)
    $signer = $(if ($null -ne $Signature -and $Signature.Signer) { [string]$Signature.Signer } else { $null })
    $Entry.publisher = $signer
    $Entry.target | Add-Member -NotePropertyName Signer -NotePropertyValue $signer -Force
    $Entry.target | Add-Member -NotePropertyName WindowsSigned -NotePropertyValue (Test-TuneupWindowsSignature -Signature $Signature -Rules $Rules) -Force
}

# Whether a full path is inside the folder of Windows (after resolving . and ..), without case. Nothing
# that is not a full path is.
function Test-TuneupWindowsFolderPath {
    param([AllowNull()][AllowEmptyString()][string]$Path)
    if ($Path -notmatch '^[A-Za-z]:\\') { return $false }
    $full = [System.IO.Path]::GetFullPath($Path)
    $windows = ([Environment]::GetFolderPath('Windows')).TrimEnd('\') + '\'
    $full.StartsWith($windows, [System.StringComparison]::OrdinalIgnoreCase)
}

# Whether a service starts as a protected process (LaunchProtected: 1 Windows, 2 Windows light, 3
# antimalware light), from its key; nothing when it does not say. A standard user can read the key.
function Get-TuneupServiceLaunchProtected {
    param([Parameter(Mandatory)][string]$Name, [string]$Root = $script:ServiceRoot)
    $path = Join-Path $Root $Name
    if (-not (Test-Path -LiteralPath $path)) { return }
    $value = (Get-Item -LiteralPath $path -ErrorAction Stop).GetValue('LaunchProtected')
    if ($null -ne $value) { [int]$value }
}

# The running processes. Windows keeps the path and the times of some processes (other accounts, protected
# ones) from a process that is not elevated: those stay unknown, never guessed.
function Get-TuneupStartupProcess {
    foreach ($process in @(Get-Process -ErrorAction Stop)) {
        $path = $null
        try { $path = [string]$process.Path } catch { $path = $null }
        $cpu = $null
        try {
            if ($null -ne $process.TotalProcessorTime) { $cpu = [double]$process.TotalProcessorTime.TotalSeconds }
        } catch {
            $cpu = $null
        }
        [pscustomobject]@{ Id = [int]$process.Id; Path = $(if ($path) { $path } else { $null }); WorkingSet = [int64]$process.WorkingSet64; CpuSeconds = $cpu }
    }
}

$script:StartupFolders = @(
    [pscustomobject]@{ Source = 'folder-user'; Folder = 'Startup' }
    [pscustomobject]@{ Source = 'folder-machine'; Folder = 'CommonStartup' }
)

# Where a startup folder is (Startup or CommonStartup), from the folders of the account; empty when the
# account has none.
function Get-TuneupStartupFolderPath {
    param([Parameter(Mandatory)][ValidateSet('Startup', 'CommonStartup')][string]$Name)
    [Environment]::GetFolderPath($Name)
}

# The StartupApproved values of a key, or an empty table when they cannot be read (the detector warns).
function Read-TuneupStartupApprovedSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $read = Invoke-TuneupDetector -What "the startup choices of Task Manager in $Path" -Detector { Get-TuneupStartupApprovedValue -Path $Path }
    if ($read.Ok -and $read.Value -is [hashtable]) { return $read.Value }
    @{}
}

# The values of the Run, RunOnce and policy Run keys, with whether Task Manager turned them off.
function Get-TuneupStartupRunEntry {
    [CmdletBinding()]
    param()
    foreach ($run in $script:StartupRunKeys) {
        $values = Invoke-TuneupDetector -What "the startup key $($run.Path)" -Detector { Get-TuneupStartupRunValue -Path $run.Path }
        if (-not $values.Ok) { continue }
        $approvedPath = $script:StartupSources[$run.Source].Approved
        $approved = $(if ($approvedPath) { Read-TuneupStartupApprovedSet -Path $approvedPath } else { @{} })
        foreach ($value in @($values.Value | Where-Object { $null -ne $_ })) {
            $bytes = $null
            if ($approved.ContainsKey($value.Name)) { $bytes = $approved[$value.Name] }
            New-TuneupStartupEntry -Source $run.Source -Key $value.Name -Name $value.Name -Command $value.Command `
                -Path (Get-TuneupCommandProgram -Command $value.Command) -Enabled (Test-TuneupStartupApprovedEnabled -Value $bytes) `
                -Policy ($run.Source -like 'policy-*') -Target @{ ApprovedPath = $approvedPath; ApprovedName = [string]$value.Name; ApprovedValue = $bytes }
        }
    }
}

# The files of the startup folders (a shortcut by where it points), with whether Task Manager turned them off.
function Get-TuneupStartupFolderEntry {
    [CmdletBinding()]
    param()
    foreach ($folder in $script:StartupFolders) {
        $path = Get-TuneupStartupFolderPath -Name $folder.Folder
        if (-not $path) { continue }
        $items = Invoke-TuneupDetector -What "the startup folder $path" -Detector { Get-TuneupStartupFolderItem -Path $path }
        if (-not $items.Ok) { continue }
        $approvedPath = $script:StartupSources[$folder.Source].Approved
        $approved = Read-TuneupStartupApprovedSet -Path $approvedPath
        foreach ($item in @($items.Value | Where-Object { $null -ne $_ })) {
            $program = [string]$item.FullName
            $command = [string]$item.FullName
            if ([System.IO.Path]::GetExtension([string]$item.Name) -ieq '.lnk') {
                $link = Invoke-TuneupDetector -What "the shortcut $($item.Name)" -Detector { Get-TuneupShortcutTarget -Path $item.FullName }
                if ($link.Ok -and $null -ne $link.Value -and $link.Value.Target) {
                    $program = Expand-TuneupStartupPath -Text ([string]$link.Value.Target)
                    $command = ('"{0}" {1}' -f $program, [string]$link.Value.Arguments).Trim()
                }
            }
            $bytes = $null
            if ($approved.ContainsKey($item.Name)) { $bytes = $approved[$item.Name] }
            New-TuneupStartupEntry -Source $folder.Source -Key ([string]$item.Name) -Name ([System.IO.Path]::GetFileNameWithoutExtension([string]$item.Name)) `
                -Command $command -Path $program -Enabled (Test-TuneupStartupApprovedEnabled -Value $bytes) `
                -Target @{ ApprovedPath = $approvedPath; ApprovedName = [string]$item.Name; ApprovedValue = $bytes }
        }
    }
}

# The startup tasks of the Store apps of the user: only the keys whose task the manifest of the package
# declares (each manifest is read once). State 2 and 4 are on; 3 and 4 come from a policy.
function Get-TuneupStartupStoreEntry {
    [CmdletBinding()]
    param()
    $tasks = Invoke-TuneupDetector -What 'the startup tasks of Store apps' -Detector { Get-TuneupStartupStoreTask }
    if (-not $tasks.Ok -or -not @($tasks.Value | Where-Object { $null -ne $_ }).Count) { return }
    $packages = Invoke-TuneupDetector -What 'the Store apps of this user' -Detector { Get-TuneupStartupPackage }
    if (-not $packages.Ok) { return }
    $byFamily = @{}
    foreach ($package in @($packages.Value | Where-Object { $null -ne $_ })) { $byFamily[$package.PackageFamilyName] = $package }
    $declared = @{}
    foreach ($task in @($tasks.Value | Where-Object { $null -ne $_ })) {
        $package = $byFamily[$task.PackageFamilyName]
        if ($null -eq $package -or -not $package.InstallLocation) { continue }
        if (-not $declared.ContainsKey($task.PackageFamilyName)) {
            $manifest = Join-Path $package.InstallLocation 'AppxManifest.xml'
            $read = Invoke-TuneupDetector -What "the manifest of $($package.Name)" -Detector { Get-TuneupAppxManifestStartupTask -Path $manifest }
            $declared[$task.PackageFamilyName] = @(if ($read.Ok) { $read.Value | Where-Object { $null -ne $_ } })
        }
        $startupTask = @($declared[$task.PackageFamilyName] | Where-Object { $_.TaskId -eq $task.TaskId }) | Select-Object -First 1
        if ($null -eq $startupTask) { continue }
        $name = $(if ($startupTask.DisplayName -and $startupTask.DisplayName -notlike 'ms-resource:*') { [string]$startupTask.DisplayName } else { [string]$package.Name })
        $entry = New-TuneupStartupEntry -Source 'store-app' -Key "$($task.PackageFamilyName)\$($task.TaskId)" -Name $name `
            -Enabled (@(2, 4) -contains $task.State) -Policy (@(3, 4) -contains $task.State) `
            -Target @{
                StoreKeyPath = [string]$task.KeyPath; StoreState = [int]$task.State; InstallLocation = [string]$package.InstallLocation
                # Part of Windows only by the kind of its signature; the CN of the package is its signer.
                WindowsPart = ($package.SignatureKind -eq 'System'); Signer = (Get-TuneupCommonName -DistinguishedName $package.Publisher)
            }
        # The publisher that Settings shows; the CN of the package (sometimes a GUID) when the manifest
        # gives none or only a resource reference.
        $display = [string]$startupTask.PublisherDisplayName
        $entry.publisher = $(if ($display.Trim() -and $display -notlike 'ms-resource:*') { $display.Trim() } else { $entry.target.Signer })
        $entry
    }
}

# The scheduled tasks that start at sign-in or at boot.
function Get-TuneupStartupTaskEntry {
    [CmdletBinding()]
    param()
    $tasks = Invoke-TuneupDetector -What 'the scheduled tasks' -Detector { Get-TuneupStartupScheduledTask }
    if (-not $tasks.Ok) { return }
    foreach ($task in @($tasks.Value | Where-Object { $null -ne $_ })) {
        $command = ('{0} {1}' -f [string]$task.Execute, [string]$task.Arguments).Trim()
        $entry = New-TuneupStartupEntry -Source 'task' -Key "$($task.TaskPath)$($task.TaskName)" -Name ([string]$task.TaskName) -Command $command `
            -Path (Get-TuneupCommandProgram -Command $task.Execute) -Enabled ($task.State -ne 'Disabled') `
            -Target @{ TaskPath = [string]$task.TaskPath; TaskName = [string]$task.TaskName }
        if ($task.State -eq 'Running') { $entry.running = $true }
        $entry
    }
}

# The services and drivers that start on their own, but not the ones of Windows: they are not something
# that a program of another publisher added. A service of Windows is one whose signature Windows vouches
# for, or one that a service host of Windows (svchost, lsass) runs from the folder of Windows. Fail closed:
# any other service that runs from the folder of Windows and is not signed by another publisher (no valid
# signature, a signer that only names Windows, or a host program such as cmd.exe, whose signature is not
# the one of the service) is listed but protected as part of Windows.
function Get-TuneupStartupServiceEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Rules)
    $services = Invoke-TuneupDetector -What 'the services and drivers that start on their own' -Detector { Get-TuneupStartupServiceItem }
    if (-not $services.Ok) { return }
    foreach ($service in @($services.Value | Where-Object { $null -ne $_ })) {
        $program = Get-TuneupCommandProgram -Command $service.PathName
        $file = $(if ($program) { [System.IO.Path]::GetFileName($program) } else { $null })
        $hosted = $file -and @($Rules.hostPrograms) -contains $file
        $signature = $null
        if ($program -and -not $hosted) { $signature = (Invoke-TuneupDetector -What "the signature of $program" -Detector { Get-TuneupFileSignature -Path $program }).Value }
        if (Test-TuneupWindowsSignature -Signature $signature -Rules $Rules) { continue }
        $inWindows = Test-TuneupWindowsFolderPath -Path $program
        $otherPublisher = $null -ne $signature -and $signature.Signer -and @($Rules.windowsSigners) -notcontains [string]$signature.Signer
        $windowsPart = $inWindows -and -not $otherPublisher
        if ($windowsPart -and $script:WindowsServiceHosts -contains $file) { continue }
        $name = $(if ($service.DisplayName) { [string]$service.DisplayName } else { [string]$service.Name })
        $startType = $(if ($service.DelayedAutoStart) { 'AutomaticDelayed' } else { 'Automatic' })
        $launchProtected = $null
        if ($service.Kind -eq 'service') {
            $launchProtected = (Invoke-TuneupDetector -What "whether $($service.Name) starts as a protected process" -Detector { Get-TuneupServiceLaunchProtected -Name $service.Name }).Value
        }
        $entry = New-TuneupStartupEntry -Source $service.Kind -Key ([string]$service.Name) -Name $name -Command $service.PathName -Path $program `
            -Target @{ ServiceName = [string]$service.Name; StartType = $startType; ProcessId = [int]$service.ProcessId; WindowsPart = [bool]$windowsPart; LaunchProtected = $launchProtected }
        Set-TuneupStartupSignature -Entry $entry -Signature $signature -Rules $Rules
        $entry.running = ([string]$service.State -eq 'Running')
        $entry
    }
}

# Memory and CPU of what runs: the process of a service by its id (only that one), the processes of a
# Store app by its folder, any other program by its path. Nothing is matched for a hosted program.
function Set-TuneupStartupUsage {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Process)
    $target = $Entry.target
    $mine = @()
    if ($null -ne $target -and $null -ne $target.PSObject.Properties['ProcessId']) {
        if ($target.ProcessId) { $mine = @($Process | Where-Object { $_.Id -eq $target.ProcessId }) }
    } elseif ($null -ne $target -and $null -ne $target.PSObject.Properties['InstallLocation'] -and $target.InstallLocation) {
        $prefix = ([string]$target.InstallLocation).TrimEnd('\') + '\'
        $mine = @($Process | Where-Object { $_.Path -and ([string]$_.Path).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
    } elseif ($Entry.path) {
        $mine = @($Process | Where-Object { $_.Path -and [string]$_.Path -ieq [string]$Entry.path })
    }
    if (-not $mine.Count) {
        if ($null -eq $Entry.running) { $Entry.running = $false }
        return
    }
    $Entry.running = $true
    $Entry.memoryMB = [int][math]::Round([double](($mine | Measure-Object -Property WorkingSet -Sum).Sum) / 1MB)
    $cpu = @($mine | Where-Object { $null -ne $_.CpuSeconds })
    if ($cpu.Count) { $Entry.cpuSeconds = [math]::Round([double](($cpu | Measure-Object -Property CpuSeconds -Sum).Sum), 1) }
}

# Publisher, protection, whether it can be turned off, recommendation and use of one entry. A hosted
# program (rundll32, cmd, powershell...) has no publisher or use of its own: they would be the ones of
# Windows. -Process is null when the processes could not be read: running stays as it is (unknown).
function Complete-TuneupStartupEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)]$Rules,
        [AllowEmptyCollection()][string[]]$SecurityFolder = @(),
        [AllowNull()][AllowEmptyCollection()][object[]]$Process,
        # A work PC (managed, or joined to Entra ID): the apps of work (workApp) are not recommended there.
        [bool]$WorkPc = $false
    )
    $program = [string]$Entry.path
    $hosted = $program -and @($Rules.hostPrograms) -contains [System.IO.Path]::GetFileName($program)
    # Services keep the signature they were listed with, and a Store app the signer of its package.
    if ($null -eq $Entry.target.PSObject.Properties['Signer']) {
        $signature = $null
        if ($program -and -not $hosted) { $signature = (Invoke-TuneupDetector -What "the signature of $program" -Detector { Get-TuneupFileSignature -Path $program }).Value }
        Set-TuneupStartupSignature -Entry $Entry -Signature $signature -Rules $Rules
    }
    $Entry.protected = Get-TuneupStartupProtection -Entry $Entry -Rules $Rules -SecurityFolder $SecurityFolder
    $Entry.canDisable = [bool]$Entry.enabled -and -not (Get-TuneupStartupFixedReason -Entry $Entry)
    if ($Entry.canDisable) {
        $rule = Get-TuneupStartupRecommendation -Entry $Entry -Rules $Rules
        $workApp = $(if ($null -ne $rule) { $rule.PSObject.Properties['workApp'] } else { $null })
        if ($null -ne $rule -and $WorkPc -and $null -ne $workApp -and $workApp.Value -eq $true) {
            # It can still be turned off; the reason lets people (and the skill) say why it is not recommended.
            $Entry.notRecommendedReason = 'work-app'
        } elseif ($null -ne $rule) {
            $Entry.recommended = $true
            $Entry.recommendedReason = [string]$rule.category
            $Entry.uninstall = Get-TuneupStartupUninstallCommand -Rule $rule
        }
    }
    if ($null -ne $Process -and -not $hosted) { Set-TuneupStartupUsage -Entry $Entry -Process $Process }
}

# Everything that starts with Windows or runs in the background, in the order of the sources. A source
# that cannot be read is a warning and the rest is still listed. -WorkPc: see Test-TuneupStartupWorkPc.
function Get-TuneupStartupEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Rules, [bool]$WorkPc = $false)
    Clear-TuneupFileSignerCache
    $entries = @(Get-TuneupStartupRunEntry) + @(Get-TuneupStartupFolderEntry) + @(Get-TuneupStartupStoreEntry) +
        @(Get-TuneupStartupTaskEntry) + @(Get-TuneupStartupServiceEntry -Rules $Rules)
    $processes = Invoke-TuneupDetector -What 'the running programs' -Detector { Get-TuneupStartupProcess }
    $running = $null
    if ($processes.Ok) { $running = @($processes.Value | Where-Object { $null -ne $_ }) }
    $securityFolders = @(foreach ($class in $script:SecurityCenterClasses) {
            (Invoke-TuneupDetector -What "the $class products of Windows Security" -Detector { Get-TuneupSecurityProductFolder -ClassName $class }).Value
        })
    $securityFolders = @($securityFolders | Where-Object { $_ })
    foreach ($entry in @($entries | Where-Object { $null -ne $_ })) {
        Complete-TuneupStartupEntry -Entry $entry -Rules $Rules -SecurityFolder $securityFolders -Process $running -WorkPc $WorkPc
        $entry
    }
}

# A work PC, where OneDrive, Teams and Outlook are not recommended: managed (domain or MDM, which the
# environment of the command already holds) or joined to Entra ID (one registry read), the same rule as the
# work signal of -Suggest. A join that cannot be read is a warning and counts as no join.
function Test-TuneupStartupWorkPc {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Environment)
    if ($Environment.IsManaged) { return $true }
    $entra = Invoke-TuneupDetector -What 'the Entra ID join' -Detector { Test-TuneupEntraJoined }
    [bool]($entra.Ok -and $entra.Value -eq $true)
}
