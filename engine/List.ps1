# -List (design, section 13.2): what the catalog and the profiles offer on this machine, read only.
# A tweak suits the machine when its Windows version, edition and hardware match, with the same checks
# as the plan; the rest is listed apart with the reason the plan would give. The blacklist is not data
# of the tool: the skill reads docs\<language>\blacklist.md of the installed copy.

function Get-TuneupListDocument {
    param([Parameter(Mandatory)]$Definition, [Parameter(Mandatory)]$Environment)
    $byId = @{}
    foreach ($tweak in $Definition.Catalog) { $byId[[string]$tweak.id] = $tweak }
    # Why a tweak does not suit this machine; no entry when it does.
    $notHere = @{}
    foreach ($tweak in $Definition.Catalog) {
        $reason = $null
        if (-not (Test-TuneupCompatible -Tweak $tweak -Environment $Environment)) { $reason = 'incompatible' }
        elseif (-not (Test-TuneupHardwareMatch -Tweak $tweak -Environment $Environment)) { $reason = 'not-applicable-hardware' }
        elseif ($Environment.IsManaged -and (Test-TuneupPolicyTweak -Tweak $tweak)) { $reason = 'managed-device' }
        if ($reason) { $notHere[[string]$tweak.id] = $reason }
    }
    $profileSet = @(@($Definition.Profiles | Where-Object { $_.id -eq 'base' }) + @($Definition.Profiles | Where-Object { $_.id -ne 'base' }))
    # The profiles that include each tweak, keyed by the spelling of the catalog.
    $includedBy = @{}
    foreach ($profileData in $profileSet) {
        foreach ($name in @($profileData.include | Where-Object { $_ })) {
            $tweak = $byId[[string]$name]
            if ($null -eq $tweak) { continue }
            $id = [string]$tweak.id
            if (-not $includedBy.ContainsKey($id)) { $includedBy[$id] = New-Object System.Collections.Generic.List[string] }
            if (-not $includedBy[$id].Contains([string]$profileData.id)) { $includedBy[$id].Add([string]$profileData.id) }
        }
    }
    $profileViews = @(foreach ($profileData in $profileSet) {
        $usable = @(@($profileData.include | Where-Object { $_ }) | ForEach-Object { $byId[[string]$_] } |
            Where-Object { $null -ne $_ -and -not $notHere.ContainsKey([string]$_.id) })
        [pscustomobject]@{
            id          = [string]$profileData.id
            aliases     = [string[]]@($profileData.aliases | Where-Object { $_ })
            title       = Get-TuneupLocalizedText $profileData.title
            description = Get-TuneupLocalizedText $profileData.description
            tweakCount  = $usable.Count
            needsAdmin  = (@($usable | Where-Object { Test-TuneupTweakNeedsAdmin -Tweak $_ }).Count -gt 0)
        }
    })
    $tweakViews = @(foreach ($tweak in $Definition.Catalog) {
        $id = [string]$tweak.id
        if ($notHere.ContainsKey($id)) { continue }
        [pscustomobject]@{
            id             = $id
            title          = Get-TuneupTitle -Tweak $tweak
            why            = Get-TuneupLocalizedText $tweak.why
            risk           = [string]$tweak.risk
            ask            = [bool]$tweak.ask
            type           = [string]$tweak.type
            scope          = [string]$tweak.scope
            needsAdmin     = [bool](Test-TuneupTweakNeedsAdmin -Tweak $tweak)
            rebootRequired = [bool]$tweak.rebootRequired
            requires       = [string[]]@(if ($null -ne $tweak.PSObject.Properties['requires']) { $tweak.requires })
            profiles       = [string[]]@(if ($includedBy.ContainsKey($id)) { $includedBy[$id] })
        }
    })
    $incompatible = @(foreach ($tweak in $Definition.Catalog) {
        $id = [string]$tweak.id
        if ($notHere.ContainsKey($id)) { [pscustomobject]@{ id = $id; reason = $notHere[$id] } }
    })
    [pscustomobject]@{ schemaVersion = 1; command = 'list'; profiles = $profileViews; tweaks = $tweakViews; incompatible = $incompatible }
}

function Write-TuneupListReport {
    param(
        [Parameter(Mandatory)]$Document,
        [AllowEmptyCollection()][string[]]$Warnings = @(),
        [switch]$Json
    )
    if ($Json) { Write-TuneupJson (Add-TuneupJsonWarning -Document $Document -Warnings $Warnings); return }
    $adminMark = ' ' + (Get-TuneupText -Key 'menu.profile.admin')
    Write-Host (Get-TuneupText -Key 'list.profiles')
    foreach ($profileView in $Document.profiles) {
        $mark = $(if ($profileView.needsAdmin) { $adminMark } else { '' })
        Write-Host (Get-TuneupText -Key 'list.profile' -Format $profileView.id, $profileView.title, $profileView.tweakCount, $mark)
    }
    Write-Host ''
    Write-Host (Get-TuneupText -Key 'list.tweaks')
    foreach ($tweakView in $Document.tweaks) {
        $mark = $(if ($tweakView.needsAdmin) { $adminMark } else { '' })
        Write-Host (Get-TuneupText -Key 'list.tweak' -Format $tweakView.id, $tweakView.title, (Get-TuneupText -Key "risk.$($tweakView.risk)"), $mark)
    }
    if (@($Document.incompatible).Count) {
        Write-Host ''
        Write-Host (Get-TuneupText -Key 'list.incompatible') -ForegroundColor DarkGray
        foreach ($item in $Document.incompatible) {
            Write-Host (Get-TuneupText -Key 'list.incompatibleLine' -Format $item.id, (Get-TuneupText -Key "reason.$($item.reason)")) -ForegroundColor DarkGray
        }
    }
}
