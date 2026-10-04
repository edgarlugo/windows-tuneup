# -Startup (design, sections 15.4 and 15.5): the rules that say which startup entries are protected and
# which are recommended. They are data, in catalog\startup\rules.json of the copy of the tool itself
# (-CatalogPath never changes them, so nobody can plant another list of what is protected), so a person
# can review them; this file loads them, checks them and applies them to one entry.

$script:StartupRulesPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'catalog\startup\rules.json'
$script:StartupRuleCategories = [ordered]@{
    protect   = @('security', 'vpn', 'device', 'updates')
    recommend = @('updater', 'game-launcher', 'sync-client', 'chat-helper', 'companion-app')
}
# Every value of protected, in the order the checks give them.
$script:StartupProtections = @('policy', 'driver', 'windows-component') + $script:StartupRuleCategories.protect
$script:StartupWingetIdPattern = '^[A-Za-z0-9][A-Za-z0-9.+_-]*$'
# The fields each part of the rules can have: anything else is a typo that would silently do nothing.
$script:StartupRuleFields = @{
    top    = @('schemaVersion', 'about', 'windowsSigners', 'hostPrograms', 'windowsServices', 'protect', 'protectSigners', 'recommend')
    rule   = @('category', 'pattern', 'why', 'wingetId', 'workApp')
    signer = @('category', 'signer', 'sources', 'why', 'wingetId', 'workApp')
}

# The fields of an object that are not in the list (wingetId and workApp have their own messages).
function Get-TuneupStartupUnknownField {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string[]]$Known)
    foreach ($property in @($Object.PSObject.Properties)) {
        if ($Known -cnotcontains $property.Name) { $property.Name }
    }
}

# The problems of a set of rules; nothing when it is valid.
function Test-TuneupStartupRuleSet {
    param([Parameter(Mandatory)]$Rules)
    if ($Rules.schemaVersion -ne 1) { 'schemaVersion must be 1' }
    foreach ($field in @(Get-TuneupStartupUnknownField -Object $Rules -Known $script:StartupRuleFields.top)) { "the rules have an unknown field '$field'" }
    foreach ($field in 'windowsSigners', 'hostPrograms', 'windowsServices') {
        $values = @($Rules.$field | Where-Object { $null -ne $_ })
        if (-not $values.Count -or @($values | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count) {
            "$field must be a list of names"
        }
    }
    foreach ($list in $script:StartupRuleCategories.Keys) {
        $categories = $script:StartupRuleCategories[$list]
        $items = @($Rules.$list | Where-Object { $null -ne $_ })
        if (-not $items.Count) { "$list has no rules" }
        foreach ($rule in $items) {
            $pattern = [string]$rule.pattern
            if ($categories -cnotcontains [string]$rule.category) { "$list rule '$pattern' has an unknown category '$($rule.category)'" }
            foreach ($field in @(Get-TuneupStartupUnknownField -Object $rule -Known $script:StartupRuleFields.rule)) { "$list rule '$pattern' has an unknown field '$field'" }
            if ([string]::IsNullOrWhiteSpace($pattern)) {
                "$list has a rule without a pattern"
                continue
            }
            try {
                # A pattern that matches an empty text matches every entry (one with no publisher, say).
                if ([regex]::IsMatch('', $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { "$list rule '$pattern' matches an empty text" }
            } catch {
                "$list rule '$pattern' is not a valid pattern: $($_.Exception.Message)"
            }
            # Why the rule is there, for whoever reviews the list (JSON has no comments).
            if ([string]::IsNullOrWhiteSpace([string]$rule.why)) { "$list rule '$pattern' has no why" }
            $workApp = $rule.PSObject.Properties['workApp']
            if ($null -ne $workApp) {
                if ($list -ne 'recommend') { "$list rule '$pattern' cannot have workApp" }
                elseif ($workApp.Value -isnot [bool]) { "$list rule '$pattern' workApp must be true or false" }
            }
            $winget = $rule.PSObject.Properties['wingetId']
            if ($null -eq $winget) { continue }
            if ($list -ne 'recommend') { "$list rule '$pattern' cannot have a wingetId" }
            elseif ([string]$winget.Value -cnotmatch $script:StartupWingetIdPattern) { "$list rule '$pattern' has an invalid wingetId '$($winget.Value)'" }
        }
    }
    # Protections by the signer of the program, each for the sources it names (optional list).
    foreach ($rule in @($Rules.protectSigners | Where-Object { $null -ne $_ })) {
        $signer = [string]$rule.signer
        if ([string]::IsNullOrWhiteSpace($signer)) {
            'protectSigners has a rule without a signer'
            continue
        }
        if ($script:StartupRuleCategories.protect -cnotcontains [string]$rule.category) { "protectSigners rule '$signer' has an unknown category '$($rule.category)'" }
        $sources = @($rule.sources | Where-Object { $null -ne $_ })
        if (-not $sources.Count) { "protectSigners rule '$signer' must name the sources it applies to" }
        foreach ($source in $sources) {
            if (-not $script:StartupSources.Contains([string]$source)) { "protectSigners rule '$signer' has an unknown source '$source'" }
        }
        if ([string]::IsNullOrWhiteSpace([string]$rule.why)) { "protectSigners rule '$signer' has no why" }
        foreach ($field in @(Get-TuneupStartupUnknownField -Object $rule -Known $script:StartupRuleFields.signer)) { "protectSigners rule '$signer' has an unknown field '$field'" }
        if ($null -ne $rule.PSObject.Properties['wingetId']) { "protectSigners rule '$signer' cannot have a wingetId" }
        if ($null -ne $rule.PSObject.Properties['workApp']) { "protectSigners rule '$signer' cannot have workApp" }
    }
}

# The rules of the tool; rules with problems stop the command (a list of what is protected that cannot be
# read is never taken as "nothing is protected").
function Import-TuneupStartupRuleSet {
    param([string]$Path = $script:StartupRulesPath)
    $rules = [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom) | ConvertFrom-Json
    $problems = @(Test-TuneupStartupRuleSet -Rules $rules)
    if ($problems.Count) { throw "The startup rules $Path are not valid: $($problems -join '; ')" }
    $rules
}

# The texts a pattern is tried on: the name of the entry, its publisher, the file name of its program and
# its key (a value, file, task or service name).
function Get-TuneupStartupMatchText {
    param([Parameter(Mandatory)]$Entry)
    $file = $(if ($Entry.path) { [System.IO.Path]::GetFileName([string]$Entry.path) } else { $null })
    @([string]$Entry.name, [string]$Entry.publisher, [string]$file, [string]$Entry.key) | Where-Object { $_ }
}

# The first rule of the list whose pattern matches one of those texts, without case.
function Find-TuneupStartupRule {
    param([Parameter(Mandatory)]$Entry, [AllowEmptyCollection()][object[]]$Rules = @())
    $texts = @(Get-TuneupStartupMatchText -Entry $Entry)
    foreach ($rule in @($Rules | Where-Object { $null -ne $_ })) {
        foreach ($text in $texts) {
            if ([regex]::IsMatch($text, [string]$rule.pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { return $rule }
        }
    }
}

# Why an entry must stay as it is, or nothing; the first check that holds gives the reason. -SecurityFolder:
# the folders of the products that Windows Security lists (antivirus, firewall).
function Get-TuneupStartupProtection {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)]$Rules, [AllowEmptyCollection()][string[]]$SecurityFolder = @())
    if ($Entry.policy) { return 'policy' }
    if ($Entry.source -eq 'driver') { return 'driver' }
    # Signed by Windows only when Windows vouches for the signature (IsOSBinary or a Microsoft root), never
    # by the name of the signer alone; a Store app only by the kind of its signature (WindowsPart).
    if ($Entry.source -ne 'store-app' -and (Get-TuneupStartupTargetValue -Entry $Entry -Name 'WindowsSigned') -eq $true) { return 'windows-component' }
    if (@('service', 'driver') -contains $Entry.source) {
        # A per-user service is <name>_<hex suffix>: it is the service of Windows of that name.
        $key = [string]$Entry.key
        $base = $key -replace '_[0-9a-fA-F]{4,}$', ''
        if (@($Rules.windowsServices) -contains $key -or @($Rules.windowsServices) -contains $base) { return 'windows-component' }
    }
    # A Store app of Windows, or a service that runs from the folder of Windows and could not be shown to be
    # of another publisher (fail closed).
    if ((Get-TuneupStartupTargetValue -Entry $Entry -Name 'WindowsPart') -eq $true) { return 'windows-component' }
    # Windows starts it as a protected process (1 Windows, 2 Windows light, 3 antimalware light).
    if ($Entry.source -eq 'service' -and @(1, 2, 3) -contains (Get-TuneupStartupTargetValue -Entry $Entry -Name 'LaunchProtected')) { return 'security' }
    if ($Entry.path) {
        $folder = (Split-Path -Path ([string]$Entry.path) -Parent).TrimEnd('\') + '\'
        foreach ($product in @($SecurityFolder | Where-Object { $_ })) {
            if ($folder.StartsWith(([string]$product).TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return 'security' }
        }
    }
    $categories = @(@(Find-TuneupStartupRule -Entry $Entry -Rules @($Rules.protect)) + @(Find-TuneupStartupSignerRule -Entry $Entry -Rules $Rules) |
            Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.category })
    # A pattern rule and a signer rule can both hold: the category that comes first in the order wins.
    foreach ($category in $script:StartupRuleCategories.protect) {
        if ($categories -contains $category) { return $category }
    }
}

# A value that the list keeps in the target of an entry, or nothing.
function Get-TuneupStartupTargetValue {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Entry.target) { return }
    $property = $Entry.target.PSObject.Properties[$Name]
    if ($null -ne $property) { $property.Value }
}

# The first protectSigners rule for the source of an entry whose signer is the signer of the entry (the
# valid Authenticode signer of its program, kept in its target; never the publisher it shows), compared
# whole and without case.
function Find-TuneupStartupSignerRule {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)]$Rules)
    $signer = [string](Get-TuneupStartupTargetValue -Entry $Entry -Name 'Signer')
    if (-not $signer) { return }
    foreach ($rule in @($Rules.protectSigners | Where-Object { $null -ne $_ })) {
        if (@($rule.sources) -contains [string]$Entry.source -and [string]$rule.signer -ieq $signer) { return $rule }
    }
}

# Why an entry cannot be turned off, or nothing: its protection, a run-once entry (Windows deletes it once
# it ran; turning it off would mean deleting it), or a task whose name or folder holds a wildcard character
# or the backtick that escapes one (the task handler looks tasks up with PowerShell wildcards and could not
# be sure it found that one).
function Get-TuneupStartupFixedReason {
    param([Parameter(Mandatory)]$Entry)
    if ($Entry.protected) { return [string]$Entry.protected }
    if ([string]$Entry.source -like 'runonce*') { return 'run-once' }
    # The list could not finish reading it (a warning said so): what was not checked is never turned off.
    if ((Get-TuneupStartupTargetValue -Entry $Entry -Name 'Incomplete') -eq $true) { return 'unreadable' }
    if ($Entry.source -eq 'task' -and [string]$Entry.key -match '[*?\[\]`]') { return 'unsupported-name' }
}

# The recommend rule that names an entry, or nothing. Only a mark: nothing is turned off for it.
function Get-TuneupStartupRecommendation {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)]$Rules)
    Find-TuneupStartupRule -Entry $Entry -Rules @($Rules.recommend)
}

# The command that would uninstall what a rule recommends turning off, to show and never to run; nothing
# when the rule has no winget id.
function Get-TuneupStartupUninstallCommand {
    param([AllowNull()]$Rule)
    if ($null -eq $Rule) { return }
    $winget = $Rule.PSObject.Properties['wingetId']
    if ($null -ne $winget -and [string]$winget.Value -cmatch $script:StartupWingetIdPattern) { "winget uninstall --id $($winget.Value) --exact" }
}
