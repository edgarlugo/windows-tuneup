# -Clean (design, section 16): what takes space that Windows or a program makes again by itself, measured,
# and deleted only for the rules named in -Remove. Deleting cannot be undone, so it is never part of a
# profile, a run or -Undo: it is a command of its own, read only unless -Remove names a rule. The rules are
# data, in catalog\clean\rules.json of the copy of the tool itself (-CatalogPath never changes them); this
# file loads them, checks them, measures them and deletes what they allow.

$script:CleanRulesPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'catalog\clean\rules.json'
$script:CleanIdPattern = '^clean\.[a-z0-9]+(-[a-z0-9]+)*$'
$script:CleanCategories = @('temp', 'browser', 'installers', 'dev', 'report')
# report and recycle-bin are only measured: no -Remove ever deletes them.
$script:CleanKinds = @('files', 'lghub-depots', 'delivery-optimization', 'report', 'recycle-bin')
$script:CleanReportKinds = @('report', 'recycle-bin')
# The variables a path starts with, by scope: the folders of the account for user, of the machine for
# machine. They are read from Windows (GetFolderPath), never from the environment, which the account can
# change. Tests point them at their own folders through CleanVariableOverride.
$script:CleanVariables = [ordered]@{
    user    = @('LOCALAPPDATA', 'APPDATA', 'USERPROFILE')
    machine = @('PROGRAMDATA', 'SYSTEMROOT', 'SYSTEMDRIVE')
}
$script:CleanVariableOverride = @{}
$script:CleanRuleFields = @('id', 'category', 'kind', 'scope', 'paths', 'filter', 'recurse', 'topFolders', 'exclude', 'minAgeDays', 'apps', 'services',
    'title', 'why', 'hint', 'sources')
$script:CleanNamePattern = '^[A-Za-z0-9_.-]+$'
# Never cleaned, whatever a rule says (design, section 4): the logs that repairs need, the recovery
# environment, the store of components and drivers, and the files of the accounts outside their caches.
$script:CleanForbiddenPatterns = @(
    '\\Logs\\CBS(\\|$)', '\\Logs\\DISM(\\|$)', '\\Recovery(\\|$)', '\\WinSxS(\\|$)', '\\System32(\\|$)', '\\SysWOW64(\\|$)',
    '\\Installer(\\|$)', '\\Documents(\\|$)', '\\Desktop(\\|$)', '\\Pictures(\\|$)', '\\OneDrive[^\\]*(\\|$)'
)
# -Large: how long the search of the biggest folders may take, and what it never reads.
$script:CleanLargeBudgetSeconds = 180
$script:CleanLargeCount = 15
$script:CleanLargeSkip = @('Windows', '$Recycle.Bin', 'System Volume Information', 'Recovery', 'Users', 'Documents and Settings', 'PerfLogs', 'Config.Msi')

function Get-TuneupCleanUnknownField {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string[]]$Known)
    foreach ($property in @($Object.PSObject.Properties)) {
        if ($Known -cnotcontains $property.Name) { $property.Name }
    }
}

# The problems of one path of a rule; nothing when it is valid.
function Test-TuneupCleanPath {
    param([Parameter(Mandatory)][string]$RuleId, [Parameter(Mandatory)][string]$Scope, [AllowEmptyString()][string]$Path)
    $match = [regex]::Match($Path, '^%([A-Z]+)%(\\.+)$')
    if (-not $match.Success) { return "rule '$RuleId' path '$Path' must start with a variable and name a folder or file under it" }
    $variable = $match.Groups[1].Value
    if (@($script:CleanVariables[$Scope]) -cnotcontains $variable) { return "rule '$RuleId' path '$Path' cannot use %$variable% with scope $Scope" }
    $segments = @($match.Groups[2].Value.Substring(1).Split('\'))
    foreach ($segment in $segments) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.' -or $segment -eq '..') { return "rule '$RuleId' path '$Path' has an empty or relative segment" }
        if ($segment -ne '*' -and $segment.IndexOfAny([char[]]'*?/:"<>|') -ge 0) { return "rule '$RuleId' path '$Path' has a wildcard or a character that is not allowed inside '$segment'" }
    }
    if ($segments[-1] -eq '*') { return "rule '$RuleId' path '$Path' cannot end with *" }
    foreach ($pattern in $script:CleanForbiddenPatterns) {
        if ([regex]::IsMatch($Path, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { return "rule '$RuleId' path '$Path' is in a place that is never cleaned" }
    }
}

function Test-TuneupCleanText {
    param($Value)
    $null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value.es) -and -not [string]::IsNullOrWhiteSpace([string]$Value.en)
}

# The problems of a set of rules; nothing when it is valid.
function Test-TuneupCleanRuleSet {
    param([Parameter(Mandatory)]$Rules)
    if ($Rules.schemaVersion -ne 1) { 'schemaVersion must be 1' }
    foreach ($field in @(Get-TuneupCleanUnknownField -Object $Rules -Known @('schemaVersion', 'about', 'rules'))) { "the rules have an unknown field '$field'" }
    $items = @($Rules.rules | Where-Object { $null -ne $_ })
    if (-not $items.Count) { 'there are no rules' }
    $seen = @{}
    foreach ($rule in $items) {
        $id = [string]$rule.id
        if ($id -cnotmatch $script:CleanIdPattern) { "rule '$id' has an id that is not clean.<words>" ; continue }
        if ($seen.ContainsKey($id)) { "rule '$id' is there twice" }
        $seen[$id] = $true
        foreach ($field in @(Get-TuneupCleanUnknownField -Object $rule -Known $script:CleanRuleFields)) { "rule '$id' has an unknown field '$field'" }
        $kind = [string]$rule.kind
        if ($script:CleanKinds -cnotcontains $kind) { "rule '$id' has an unknown kind '$kind'" }
        if ($script:CleanCategories -cnotcontains [string]$rule.category) { "rule '$id' has an unknown category '$($rule.category)'" }
        # What is only measured is in the report category, and nothing else is.
        if (($script:CleanReportKinds -ccontains $kind) -ne ([string]$rule.category -ceq 'report')) { "rule '$id' must be of category report exactly when its kind is only measured" }
        $scope = [string]$rule.scope
        if (@('user', 'machine') -cnotcontains $scope) { "rule '$id' has an unknown scope '$scope'" ; continue }
        if (-not (Test-TuneupCleanText $rule.title)) { "rule '$id' needs a title in es and en" }
        if (-not (Test-TuneupCleanText $rule.why)) { "rule '$id' needs a why in es and en" }
        $hint = $rule.PSObject.Properties['hint']
        if ($script:CleanReportKinds -ccontains $kind) {
            if ($null -eq $hint -or -not (Test-TuneupCleanText $hint.Value)) { "rule '$id' is only measured and needs a hint in es and en: how to free it by hand" }
        } elseif ($null -ne $hint) { "rule '$id' cannot have a hint: it is deleted by the tool" }
        $sources = @($rule.sources | Where-Object { $null -ne $_ })
        if (-not $sources.Count -or @($sources | Where-Object { [string]$_ -notmatch '^https://' }).Count) { "rule '$id' needs sources, each an https address" }
        $paths = @($rule.paths | Where-Object { $null -ne $_ })
        if ($kind -ceq 'recycle-bin') {
            if ($paths.Count) { "rule '$id' finds the Recycle Bin by itself and cannot have paths" }
        } elseif (-not $paths.Count) { "rule '$id' has no paths" }
        foreach ($path in $paths) { Test-TuneupCleanPath -RuleId $id -Scope $scope -Path ([string]$path) }
        $minAge = $rule.PSObject.Properties['minAgeDays']
        if ($null -ne $minAge -and ($minAge.Value -isnot [int] -or $minAge.Value -lt 0)) { "rule '$id' minAgeDays must be a whole number of days, 0 or more" }
        foreach ($flag in 'recurse', 'topFolders') {
            $value = $rule.PSObject.Properties[$flag]
            if ($null -ne $value -and $value.Value -isnot [bool]) { "rule '$id' $flag must be true or false" }
        }
        $filter = $rule.PSObject.Properties['filter']
        if ($null -ne $filter -and ([string]::IsNullOrWhiteSpace([string]$filter.Value) -or ([string]$filter.Value).IndexOfAny([char[]]'\/:') -ge 0)) { "rule '$id' filter must be a file name pattern" }
        foreach ($list in 'apps', 'services', 'exclude') {
            foreach ($name in @($rule.$list | Where-Object { $null -ne $_ })) {
                if ([string]$name -cnotmatch $script:CleanNamePattern) { "rule '$id' $list has a name that is not allowed: '$name'" }
            }
        }
        if ($kind -cne 'files' -and @($rule.PSObject.Properties | Where-Object { @('filter', 'recurse', 'topFolders', 'exclude') -ccontains $_.Name }).Count) {
            "rule '$id' of kind $kind cannot have filter, recurse, topFolders or exclude"
        }
    }
}

# The rules of the tool; rules with problems stop the command (nothing is measured or deleted).
function Import-TuneupCleanRuleSet {
    param([string]$Path = $script:CleanRulesPath)
    $rules = [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom) | ConvertFrom-Json
    $problems = @(Test-TuneupCleanRuleSet -Rules $rules)
    if ($problems.Count) { throw "The clean rules $Path are not valid: $($problems -join '; ')" }
    $rules
}

function Get-TuneupCleanVariableValue {
    param([Parameter(Mandatory)][string]$Name)
    if ($script:CleanVariableOverride.ContainsKey($Name)) { return [string]$script:CleanVariableOverride[$Name] }
    switch ($Name) {
        'LOCALAPPDATA' { [Environment]::GetFolderPath('LocalApplicationData') }
        'APPDATA' { [Environment]::GetFolderPath('ApplicationData') }
        'USERPROFILE' { [Environment]::GetFolderPath('UserProfile') }
        'PROGRAMDATA' { [Environment]::GetFolderPath('CommonApplicationData') }
        'SYSTEMROOT' { [Environment]::GetFolderPath('Windows') }
        'SYSTEMDRIVE' { [System.IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows')).TrimEnd('\') }
        default { throw "Unknown variable %$Name%" }
    }
}

function Test-TuneupCleanReparsePoint {
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)
    ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
}

# The folders and files a path of a rule names now: the variable resolved, each * one folder of that level.
# A folder that is a reparse point (a junction or a link) is never followed, so a rule cannot be pointed
# somewhere else; the variable's own folder may be one (a profile moved by the organization).
function Resolve-TuneupCleanPath {
    param([Parameter(Mandatory)][string]$Path)
    $match = [regex]::Match($Path, '^%([A-Z]+)%\\(.+)$')
    $base = Get-TuneupCleanVariableValue -Name $match.Groups[1].Value
    if (-not $base -or -not [System.IO.Directory]::Exists($base)) { return }
    $current = @($base)
    $segments = @($match.Groups[2].Value.Split('\'))
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $last = $index -eq $segments.Count - 1
        $next = New-Object System.Collections.Generic.List[string]
        foreach ($folder in $current) {
            if ($segments[$index] -eq '*') {
                try {
                    foreach ($child in ([System.IO.DirectoryInfo]$folder).EnumerateDirectories()) {
                        if (-not (Test-TuneupCleanReparsePoint -Item $child)) { $next.Add($child.FullName) }
                    }
                } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
                    Write-Verbose "Could not list $folder, so nothing under it is cleaned: $($_.Exception.Message)"
                }
                continue
            }
            $candidate = Join-Path $folder $segments[$index]
            if ([System.IO.Directory]::Exists($candidate)) {
                if (-not (Test-TuneupCleanReparsePoint -Item ([System.IO.DirectoryInfo]$candidate))) { $next.Add($candidate) }
            } elseif ($last -and [System.IO.File]::Exists($candidate)) {
                if (-not (Test-TuneupCleanReparsePoint -Item ([System.IO.FileInfo]$candidate))) { $next.Add($candidate) }
            }
        }
        $current = $next.ToArray()
        if (-not $current.Count) { return }
    }
    $current
}

function New-TuneupCleanTally {
    [pscustomobject]@{ Files = 0; Bytes = [long]0; Deleted = 0; FreedBytes = [long]0; Kept = 0; Unreadable = 0 }
}

# Walks one folder of a rule, counting what the rule would delete and, with -Delete, deleting it: files
# that match the filter, are older than -Before and are not read-only, at any depth unless -NoRecurse.
# At the first level, -Exclude names what stays and -TopFolders keeps the files. A reparse point is never
# followed nor deleted. Each folder is checked again right before its files are deleted. A file that
# cannot be deleted (open, denied) is kept and counted; a folder that the walk emptied is removed, except
# the folder of the rule itself and one that changed after -Before.
function Invoke-TuneupCleanWalk {
    param(
        [Parameter(Mandatory)][System.IO.DirectoryInfo]$Directory,
        [Parameter(Mandatory)]$Tally,
        [Parameter(Mandatory)][datetime]$Before,
        [string]$Filter = '*',
        [switch]$NoRecurse,
        [switch]$TopFolders,
        [AllowEmptyCollection()][string[]]$Exclude = @(),
        [switch]$Delete,
        [int]$Depth = 0
    )
    $Directory.Refresh()
    if (-not $Directory.Exists -or (Test-TuneupCleanReparsePoint -Item $Directory)) { return }
    $wasOld = $Directory.LastWriteTimeUtc -lt $Before
    try {
        $children = @($Directory.EnumerateFileSystemInfos())
    } catch [System.UnauthorizedAccessException], [System.IO.IOException], [System.Security.SecurityException] {
        $Tally.Unreadable++
        return
    }
    $pattern = New-Object System.Management.Automation.WildcardPattern -ArgumentList $Filter, ([System.Management.Automation.WildcardOptions]::IgnoreCase)
    foreach ($child in $children) {
        if ($Depth -eq 0 -and @($Exclude | Where-Object { $_ -ieq $child.Name }).Count) { continue }
        if (Test-TuneupCleanReparsePoint -Item $child) { continue }
        if ($child -is [System.IO.DirectoryInfo]) {
            if ($NoRecurse) { continue }
            Invoke-TuneupCleanWalk -Directory $child -Tally $Tally -Before $Before -Filter $Filter -Delete:$Delete -Depth ($Depth + 1)
            continue
        }
        if ($Depth -eq 0 -and $TopFolders) { continue }
        if (-not $pattern.IsMatch($child.Name) -or $child.LastWriteTimeUtc -ge $Before) { continue }
        $length = [long]$child.Length
        $Tally.Files++
        $Tally.Bytes += $length
        if (-not $Delete) { continue }
        if (($child.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) { $Tally.Kept++; continue }
        $Directory.Refresh()
        if (Test-TuneupCleanReparsePoint -Item $Directory) { $Tally.Kept++; continue }
        try {
            [System.IO.File]::Delete($child.FullName)
            $Tally.Deleted++
            $Tally.FreedBytes += $length
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            $Tally.Kept++
        }
    }
    if ($Delete -and $Depth -gt 0 -and $wasOld) {
        try {
            $Directory.Refresh()
            if (-not (Test-TuneupCleanReparsePoint -Item $Directory) -and -not @($Directory.EnumerateFileSystemInfos()).Count) { $Directory.Delete($false) }
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            Write-Verbose "The empty folder $($Directory.FullName) stays: $($_.Exception.Message)"
        }
    }
}

function Get-TuneupCleanRuleValue {
    param([Parameter(Mandatory)]$Rule, [Parameter(Mandatory)][string]$Name, $Default)
    $property = $Rule.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    $property.Value
}

function Get-TuneupCleanBefore {
    param([Parameter(Mandatory)]$Rule, [datetime]$Now = [datetime]::UtcNow)
    $days = [int](Get-TuneupCleanRuleValue -Rule $Rule -Name 'minAgeDays' -Default 0)
    # Without an age, everything up to now (a file written during the walk is left for another time).
    $Now.AddDays(-$days)
}

# The versions of G HUB that stay: the build ids that current.json and next.json, next to depots, name.
# $null when neither can be read: then nothing is deleted.
function Get-TuneupCleanLghubKeep {
    param([Parameter(Mandatory)][string]$Depots)
    $parent = Split-Path $Depots -Parent
    $keep = New-Object System.Collections.Generic.List[string]
    $read = 0
    foreach ($name in 'current.json', 'next.json') {
        $file = Join-Path $parent $name
        if (-not [System.IO.File]::Exists($file)) { continue }
        try {
            $buildId = [string]([System.IO.File]::ReadAllText($file, $script:Utf8NoBom) | ConvertFrom-Json).buildId
        } catch {
            return $null
        }
        if ($buildId -notmatch '^[0-9]+$') { return $null }
        $keep.Add($buildId)
        $read++
    }
    if (-not $read) { return $null }
    , $keep.ToArray()
}

# Measures one rule and, with -Delete, deletes what it allows. Gives the tally and, when the rule could not
# be read at all, why (unreadable). report and recycle-bin are only measured, whatever -Delete says.
function Invoke-TuneupCleanRule {
    param([Parameter(Mandatory)]$Rule, [switch]$Delete, [datetime]$Now = [datetime]::UtcNow)
    $tally = New-TuneupCleanTally
    $before = Get-TuneupCleanBefore -Rule $Rule -Now $Now
    $kind = [string]$Rule.kind
    $isReport = $script:CleanReportKinds -ccontains $kind
    $roots = @()
    if ($kind -eq 'recycle-bin') {
        $bin = Join-Path (Get-TuneupCleanVariableValue -Name 'SYSTEMDRIVE') ('$Recycle.Bin\' + (Get-TuneupCurrentUserSid))
        if ([System.IO.Directory]::Exists($bin)) { $roots = @($bin) }
    } else {
        $roots = @($Rule.paths | ForEach-Object { Resolve-TuneupCleanPath -Path ([string]$_) })
    }
    $result = [pscustomobject]@{ Tally = $tally; Paths = [string[]]$roots; Reason = $null }
    if (-not $roots.Count) { return $result }
    $doDelete = $Delete -and -not $isReport
    if ($kind -eq 'lghub-depots') {
        $keep = Get-TuneupCleanLghubKeep -Depots $roots[0]
        if ($null -eq $keep) { $result.Reason = 'unreadable'; return $result }
        foreach ($depot in @(([System.IO.DirectoryInfo]$roots[0]).EnumerateDirectories())) {
            if ($keep -contains $depot.Name -or (Test-TuneupCleanReparsePoint -Item $depot) -or $depot.LastWriteTimeUtc -ge $before) { continue }
            # Everything inside an old version goes, whatever its age; then the version folder itself.
            Invoke-TuneupCleanWalk -Directory $depot -Tally $tally -Before $Now -Delete:$doDelete -Depth 1
            if ($doDelete) {
                try {
                    if (-not @($depot.EnumerateFileSystemInfos()).Count) { $depot.Delete($false) }
                } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
                    Write-Verbose "The folder of the old version $($depot.FullName) stays: $($_.Exception.Message)"
                }
            }
        }
        return $result
    }
    foreach ($root in $roots) {
        if ([System.IO.File]::Exists($root)) {
            # A file named by the rule itself (hiberfil.sys): only measured.
            $info = [System.IO.FileInfo]$root
            $tally.Files++
            $tally.Bytes += [long]$info.Length
            continue
        }
        $walk = @{ Directory = [System.IO.DirectoryInfo]$root; Tally = $tally; Before = $before; Delete = ($doDelete -and $kind -eq 'files') }
        if ($kind -eq 'files') {
            $walk.Filter = [string](Get-TuneupCleanRuleValue -Rule $Rule -Name 'filter' -Default '*')
            $walk.NoRecurse = -not [bool](Get-TuneupCleanRuleValue -Rule $Rule -Name 'recurse' -Default $true)
            $walk.TopFolders = [bool](Get-TuneupCleanRuleValue -Rule $Rule -Name 'topFolders' -Default $false)
            $walk.Exclude = [string[]]@($Rule.exclude | Where-Object { $_ })
        }
        Invoke-TuneupCleanWalk @walk
    }
    if ($doDelete -and $kind -eq 'delivery-optimization' -and $tally.Files) {
        # Windows deletes its own cache: the service knows what it is using.
        Invoke-TuneupCleanDeliveryOptimization
        $after = New-TuneupCleanTally
        foreach ($root in $roots) { Invoke-TuneupCleanWalk -Directory ([System.IO.DirectoryInfo]$root) -Tally $after -Before $before }
        $tally.Deleted = [math]::Max(0, $tally.Files - $after.Files)
        $tally.FreedBytes = [math]::Max([long]0, $tally.Bytes - $after.Bytes)
        $tally.Kept = $after.Files
    }
    if ($tally.Unreadable -and -not $tally.Files) { $result.Reason = 'unreadable' }
    $result
}

function Invoke-TuneupCleanDeliveryOptimization {
    Import-Module DeliveryOptimization -ErrorAction Stop
    Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
}

# The processes of the rule that run now (by name), and its services that are not stopped.
function Get-TuneupCleanBusy {
    param([Parameter(Mandatory)]$Rule)
    $apps = @($Rule.apps | Where-Object { $_ })
    $services = @($Rule.services | Where-Object { $_ })
    [pscustomobject]@{
        Apps     = [string[]]@(if ($apps.Count) { Get-Process -Name $apps -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique })
        Services = [string[]]@(if ($services.Count) { Get-Service -Name $services -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Stopped' } | ForEach-Object { $_.Name } })
    }
}

function Get-TuneupCleanText {
    param($Value)
    $text = $Value.(Get-TuneupLang)
    if (-not $text) { $text = $Value.en }
    [string]$text
}

# Why a rule cannot be removed now, in the order a person fixes it; nothing when it can.
function Get-TuneupCleanBlockReason {
    param([Parameter(Mandatory)]$Rule, [Parameter(Mandatory)]$Measured, [Parameter(Mandatory)]$Busy, [Parameter(Mandatory)]$Environment)
    if ($script:CleanReportKinds -ccontains [string]$Rule.kind) { return 'report-only' }
    if ($Rule.scope -eq 'machine' -and -not $Environment.IsAdmin) { return 'needs-admin' }
    if ($Rule.scope -eq 'user' -and $Environment.IsAdmin -and $Environment.IsSessionUser -eq $false) { return 'session-user' }
    if (-not $Measured.Paths.Count) { return 'not-present' }
    if ($Measured.Reason) { return $Measured.Reason }
    if ($Busy.Apps.Count) { return 'app-running' }
    if ($Busy.Services.Count) { return 'service-running' }
    if (-not $Measured.Tally.Files) { return 'nothing-to-remove' }
}

function ConvertTo-TuneupCleanView {
    param([Parameter(Mandatory)]$Rule, [Parameter(Mandatory)]$Measured, [Parameter(Mandatory)]$Busy, [Parameter(Mandatory)]$Environment)
    # A function that returns nothing gives an empty value, which JSON would write as {}: null instead.
    $reason = [string](Get-TuneupCleanBlockReason -Rule $Rule -Measured $Measured -Busy $Busy -Environment $Environment)
    if (-not $reason) { $reason = $null }
    $hint = $Rule.PSObject.Properties['hint']
    [pscustomobject]@{
        id          = [string]$Rule.id
        category    = [string]$Rule.category
        title       = Get-TuneupCleanText $Rule.title
        why         = Get-TuneupCleanText $Rule.why
        hint        = $(if ($null -ne $hint) { Get-TuneupCleanText $hint.Value } else { $null })
        scope       = [string]$Rule.scope
        reportOnly  = $script:CleanReportKinds -ccontains [string]$Rule.kind
        needsAdmin  = [string]$Rule.scope -eq 'machine'
        paths       = [string[]]@($Measured.Paths)
        files       = [int]$Measured.Tally.Files
        bytes       = [long]$Measured.Tally.Bytes
        unreadable  = [int]$Measured.Tally.Unreadable
        runningApps = [string[]]@($Busy.Apps)
        runningServices = [string[]]@($Busy.Services)
        canRemove   = -not $reason
        reason      = $reason
    }
}

function Get-TuneupSystemDriveFreeByte {
    $root = [System.IO.Path]::GetPathRoot((Get-TuneupCleanVariableValue -Name 'SYSTEMDRIVE') + '\')
    [long](New-Object System.IO.DriveInfo -ArgumentList $root).AvailableFreeSpace
}

# The biggest folders of the account and of the system drive (the children of the profile, of AppData\Local
# and AppData\Roaming, and of the root of the drive but Windows and its own folders), measured until the
# time runs out: what was not measured completely is partial. Read only.
function Get-TuneupCleanLargest {
    param([int]$BudgetSeconds = $script:CleanLargeBudgetSeconds, [int]$Count = $script:CleanLargeCount)
    $profileRoot = Get-TuneupCleanVariableValue -Name 'USERPROFILE'
    $driveRoot = (Get-TuneupCleanVariableValue -Name 'SYSTEMDRIVE') + '\'
    $folders = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    $skipInProfile = @('AppData')
    foreach ($parent in @($profileRoot, (Get-TuneupCleanVariableValue -Name 'LOCALAPPDATA'), (Get-TuneupCleanVariableValue -Name 'APPDATA'), $driveRoot)) {
        if (-not [System.IO.Directory]::Exists($parent)) { continue }
        try {
            foreach ($child in ([System.IO.DirectoryInfo]$parent).EnumerateDirectories()) {
                if (Test-TuneupCleanReparsePoint -Item $child) { continue }
                if ($parent -eq $profileRoot -and $skipInProfile -contains $child.Name) { continue }
                if ($parent -eq $driveRoot -and ($script:CleanLargeSkip -contains $child.Name -or ($child.Attributes -band [System.IO.FileAttributes]::System))) { continue }
                $folders.Add($child)
            }
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            Write-Verbose "Could not list $parent, so its folders are left out: $($_.Exception.Message)"
        }
    }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $items = foreach ($folder in $folders) {
        $bytes = [long]0
        $partial = $false
        $stack = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
        $stack.Push($folder)
        while ($stack.Count) {
            if ($clock.Elapsed.TotalSeconds -ge $BudgetSeconds) { $partial = $true; break }
            $current = $stack.Pop()
            try {
                foreach ($child in $current.EnumerateFileSystemInfos()) {
                    if (Test-TuneupCleanReparsePoint -Item $child) { continue }
                    if ($child -is [System.IO.DirectoryInfo]) { $stack.Push($child) } else { $bytes += [long]$child.Length }
                }
            } catch [System.UnauthorizedAccessException], [System.IO.IOException], [System.Security.SecurityException] {
                $partial = $true
            }
        }
        [pscustomobject]@{ path = $folder.FullName; bytes = $bytes; partial = $partial }
    }
    [pscustomobject]@{
        complete = $clock.Elapsed.TotalSeconds -lt $BudgetSeconds
        items    = @($items | Sort-Object -Property bytes -Descending | Select-Object -First $Count)
    }
}

function Get-TuneupCleanDocument {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$View, [bool]$IsAdmin, [long]$FreeBytes, $Largest, $Removal)
    $removable = @($View | Where-Object { $_.canRemove })
    [pscustomobject]@{
        schemaVersion = 1
        command       = 'clean'
        isAdmin       = $IsAdmin
        freeBytes     = $FreeBytes
        rules         = @($View)
        summary       = [pscustomobject]@{
            total          = @($View).Count
            canRemove      = $removable.Count
            removableBytes = [long](@($removable | Measure-Object -Property bytes -Sum).Sum)
            reportBytes    = [long](@($View | Where-Object { $_.reportOnly } | Measure-Object -Property bytes -Sum).Sum)
        }
        largest       = $Largest
        removal       = $Removal
    }
}

# A size for people, in the number format of the language: 1,4 GB, 350 MB, 12 KB.
function Format-TuneupCleanSize {
    param([long]$Bytes)
    $format = Get-TuneupNumberFormat
    if ($Bytes -ge 1GB) { return ('{0} GB' -f ([math]::Round($Bytes / 1GB, 1)).ToString('0.0', $format)) }
    if ($Bytes -ge 1MB) { return ('{0} MB' -f ([math]::Round($Bytes / 1MB)).ToString('0', $format)) }
    '{0} KB' -f ([math]::Ceiling($Bytes / 1KB)).ToString('0', $format)
}

# The clean document as JSON, or for people: by category, each rule with its id, size and why it cannot be
# removed now; then what is only measured, with how to free it by hand; then the biggest folders.
function Write-TuneupCleanReport {
    param([Parameter(Mandatory)]$Document, [AllowEmptyCollection()][string[]]$Warnings = @(), [switch]$Json)
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Document -Warnings $Warnings); return }
    Write-Host (Get-TuneupText -Key 'clean.header' -Format (Format-TuneupCleanSize -Bytes $Document.freeBytes))
    $adminMark = ' ' + (Get-TuneupText -Key 'menu.profile.admin')
    foreach ($category in $script:CleanCategories) {
        $rules = @($Document.rules | Where-Object { $_.category -eq $category })
        if (-not $rules.Count) { continue }
        Write-Host ''
        Write-Host (Get-TuneupText -Key "clean.category.$category")
        foreach ($rule in $rules) {
            # Without administrator a folder of the machine may not be readable at all: that is not "empty".
            $size = $(if ($rule.needsAdmin -and -not $Document.isAdmin -and -not $rule.files -and ($rule.unreadable -or -not $rule.paths.Count)) { Get-TuneupText -Key 'clean.unmeasured' }
                elseif ($rule.paths.Count) { Format-TuneupCleanSize -Bytes $rule.bytes } else { Get-TuneupText -Key 'clean.absent' })
            $admin = $(if ($rule.needsAdmin -and -not $rule.reportOnly) { $adminMark } else { '' })
            $color = $(if ($rule.canRemove) { 'Cyan' } elseif ($rule.reportOnly) { 'Gray' } else { 'DarkGray' })
            Write-Host (Get-TuneupText -Key 'clean.rule' -Format $rule.title, $size, $admin) -ForegroundColor $color
            if (-not $rule.reportOnly) { Write-Host (Get-TuneupText -Key 'clean.id' -Format $rule.id) -ForegroundColor DarkGray }
            Write-Host (Get-TuneupText -Key 'clean.why' -Format $rule.why) -ForegroundColor DarkGray
            if ($rule.reason -and @('report-only', 'not-present') -notcontains $rule.reason) {
                $names = (@($rule.runningApps) + @($rule.runningServices)) -join ', '
                Write-Host (Get-TuneupText -Key 'clean.blocked' -Format (Get-TuneupText -Key "clean.reason.$($rule.reason)" -Format $names))
            }
            if ($rule.hint -and $rule.paths.Count) { Write-Host (Get-TuneupText -Key 'clean.hint' -Format $rule.hint) }
        }
    }
    if ($null -ne $Document.largest) {
        Write-Host ''
        Write-Host (Get-TuneupText -Key 'clean.largest.header')
        foreach ($item in @($Document.largest.items)) {
            $mark = $(if ($item.partial) { ' ' + (Get-TuneupText -Key 'clean.largest.partial') } else { '' })
            Write-Host (Get-TuneupText -Key 'clean.largest.item' -Format (Format-TuneupCleanSize -Bytes $item.bytes), $item.path, $mark)
        }
        if (-not $Document.largest.complete) { Write-Host (Get-TuneupText -Key 'clean.largest.incomplete') }
    }
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'clean.total' -Format (Format-TuneupCleanSize -Bytes $Document.summary.removableBytes), $Document.summary.canRemove)
    Write-Host (Get-TuneupText -Key 'clean.howTo')
}

# What -Remove did, for people.
function Write-TuneupCleanRemoval {
    param([Parameter(Mandatory)]$Removal)
    foreach ($result in @($Removal.results)) {
        $reason = $(if ($result.reason) { ' ' + (Get-TuneupText -Key "clean.reason.$($result.reason)" -Format ((@($result.runningApps) + @($result.runningServices)) -join ', ')) } else { '' })
        Write-Host (Get-TuneupText -Key "clean.result.$($result.status)" -Format $result.title, (Format-TuneupCleanSize -Bytes $result.freedBytes), $result.deletedFiles, $result.keptFiles, $reason)
        if ($result.error) { Write-Host "  $($result.error)" -ForegroundColor Red }
    }
    Write-Host (Get-TuneupText -Key 'clean.freed' -Format (Format-TuneupCleanSize -Bytes $Removal.freedBytes), (Format-TuneupCleanSize -Bytes $Removal.freeBytesAfter))
}
