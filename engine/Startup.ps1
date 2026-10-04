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
