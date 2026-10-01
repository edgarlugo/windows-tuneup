function Resolve-TuneupProfileId {
    param(
        [Parameter(Mandatory)][object[]]$Profiles,
        [Parameter(Mandatory)][string]$Name
    )
    $needle = $Name.Trim().ToLowerInvariant()
    foreach ($profileData in $Profiles) {
        if ($profileData.id -eq $needle -or @($profileData.aliases) -contains $needle) { return [string]$profileData.id }
    }
    throw (Get-TuneupText -Key 'err.unknownProfile' -Format $Name)
}

function Test-TuneupCompatible {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Environment)
    (@($Tweak.os.families) -contains $Environment.Family) -and
    ($Environment.Build -ge [int]$Tweak.os.minBuild) -and
    (@($Tweak.os.editions) -contains $Environment.Edition)
}

# The optional requires list of a tweak names the hardware it is meant for.
function Test-TuneupHardwareMatch {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Environment)
    $requiresProperty = $Tweak.PSObject.Properties['requires']
    if ($null -eq $requiresProperty) { return $true }
    foreach ($requirement in @($requiresProperty.Value)) {
        switch -CaseSensitive ([string]$requirement) {
            'battery' { if (-not $Environment.HasBattery) { return $false } }
            'no-battery' { if ($Environment.HasBattery) { return $false } }
            default { throw "Unknown requirement '$requirement' in tweak $($Tweak.id)" }
        }
    }
    $true
}

function Test-TuneupPolicyTweak {
    param([Parameter(Mandatory)]$Tweak)
    ($Tweak.type -eq 'registry') -and ([string]$Tweak.set.path -match '\\Policies\\')
}

function Get-TuneupCleanList {
    param([AllowEmptyCollection()][AllowNull()][string[]]$Values)
    @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
}

function New-TuneupPlan {
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [Parameter(Mandatory)][object[]]$Profiles,
        [AllowEmptyCollection()][AllowNull()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][AllowNull()][string[]]$Include = @(),
        [AllowEmptyCollection()][AllowNull()][string[]]$Exclude = @(),
        [Parameter(Mandatory)]$Environment,
        [Parameter(Mandatory)][scriptblock]$TestState,
        [switch]$Interactive
    )
    $ProfileIds = @(Get-TuneupCleanList $ProfileIds)
    $Include = @(Get-TuneupCleanList $Include)
    $Exclude = @(Get-TuneupCleanList $Exclude)

    # Hashtable lookups are case-insensitive; every id is canonicalized to the catalog's own spelling.
    $byId = @{}
    foreach ($tweak in $Catalog) { $byId[[string]$tweak.id] = $tweak }
    $canonical = {
        param([string]$TweakId)
        if ($byId.ContainsKey($TweakId)) { [string]$byId[$TweakId].id } else { $TweakId }
    }
    foreach ($tweakId in @($Include) + @($Exclude)) {
        if (-not $byId.ContainsKey($tweakId)) { throw (Get-TuneupText -Key 'err.unknownTweak' -Format $tweakId) }
    }
    $Include = @($Include | ForEach-Object { & $canonical $_ })
    $Exclude = @($Exclude | ForEach-Object { & $canonical $_ })
    $profilesById = @{}
    foreach ($profileData in $Profiles) { $profilesById[[string]$profileData.id] = $profileData }

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('base') + @($ProfileIds)) {
        $profileId = Resolve-TuneupProfileId -Profiles $Profiles -Name $name
        if ($selected -notcontains $profileId) { $selected.Add($profileId) }
    }

    $wanted = New-Object System.Collections.Generic.List[string]
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($profileId in $selected) {
        $profileData = $profilesById[$profileId]
        foreach ($tweakId in @($profileData.include | Where-Object { $_ } | ForEach-Object { & $canonical $_ })) { if ($wanted -notcontains $tweakId) { $wanted.Add($tweakId) } }
        foreach ($tweakId in @($profileData.keep | Where-Object { $_ } | ForEach-Object { & $canonical $_ })) { if ($keep -notcontains $tweakId) { $keep.Add($tweakId) } }
    }
    foreach ($tweakId in $Include) { if ($wanted -notcontains $tweakId) { $wanted.Add($tweakId) } }

    foreach ($tweakId in $wanted) {
        $tweak = $byId[$tweakId]
        if ($null -eq $tweak) { throw (Get-TuneupText -Key 'err.unknownTweak' -Format $tweakId) }
        $requested = $Include -contains $tweakId
        $reason = $null
        $note = $null
        if ($Exclude -contains $tweakId) { $reason = 'excluded' }
        elseif (($keep -contains $tweakId) -and -not $requested) { $reason = 'kept-by-profile' }
        elseif (-not (Test-TuneupCompatible -Tweak $tweak -Environment $Environment)) { $reason = 'incompatible' }
        elseif (-not (Test-TuneupHardwareMatch -Tweak $tweak -Environment $Environment)) { $reason = 'not-applicable-hardware' }
        elseif ($Environment.IsManaged -and (Test-TuneupPolicyTweak -Tweak $tweak)) { $reason = 'managed-device' }
        else {
            if ((Test-TuneupHandlerReadNeedsAdmin -Tweak $tweak) -and -not $Environment.IsAdmin) {
                # Applying it needs elevation anyway; the plan says it is checked then instead of
                # calling it unreadable.
                $state = 'unverified'
            } else {
                try { $state = & $TestState $tweak } catch { $state = 'unreadable' }
            }
            if ($state -eq 'applied') { $reason = 'already-applied' }
            elseif ($state -eq 'not-present') { $reason = 'not-present' }
            elseif ($state -eq 'unreadable') { $reason = 'state-unreadable' }
            elseif ($tweak.risk -eq 'high' -and -not $requested) { $reason = 'high-risk-not-requested' }
            elseif ($tweak.ask -and -not $Interactive -and -not $requested) { $reason = 'needs-confirmation' }
            elseif ($state -eq 'unverified') { $note = 'unverified-needs-admin' }
        }
        [pscustomobject]@{
            Id     = $tweakId
            Tweak  = $tweak
            Action = $(if ($reason) { 'skip' } else { 'apply' })
            Reason = $(if ($reason) { $reason } else { $note })
        }
    }
}
