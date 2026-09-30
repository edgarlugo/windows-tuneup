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

function Test-TuneupPolicyTweak {
    param([Parameter(Mandatory)]$Tweak)
    ($Tweak.type -eq 'registry') -and ([string]$Tweak.set.path -match '\\Policies\\')
}

function New-TuneupPlan {
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [Parameter(Mandatory)][object[]]$Profiles,
        [AllowEmptyCollection()][string[]]$ProfileIds = @(),
        [AllowEmptyCollection()][string[]]$Include = @(),
        [AllowEmptyCollection()][string[]]$Exclude = @(),
        [Parameter(Mandatory)]$Environment,
        [Parameter(Mandatory)][scriptblock]$TestState,
        [switch]$Interactive
    )
    $byId = @{}
    foreach ($tweak in $Catalog) { $byId[[string]$tweak.id] = $tweak }
    foreach ($tweakId in @($Include) + @($Exclude)) {
        if (-not $byId.ContainsKey($tweakId)) { throw (Get-TuneupText -Key 'err.unknownTweak' -Format $tweakId) }
    }
    $profilesById = @{}
    foreach ($profileData in $Profiles) { $profilesById[[string]$profileData.id] = $profileData }

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('base') + @($ProfileIds)) {
        $profileId = Resolve-TuneupProfileId -Profiles $Profiles -Name $name
        if (-not $selected.Contains($profileId)) { $selected.Add($profileId) }
    }

    $wanted = New-Object System.Collections.Generic.List[string]
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($profileId in $selected) {
        $profileData = $profilesById[$profileId]
        foreach ($tweakId in @($profileData.include | Where-Object { $_ })) { if (-not $wanted.Contains($tweakId)) { $wanted.Add($tweakId) } }
        foreach ($tweakId in @($profileData.keep | Where-Object { $_ })) { if (-not $keep.Contains($tweakId)) { $keep.Add($tweakId) } }
    }
    foreach ($tweakId in $Include) { if (-not $wanted.Contains($tweakId)) { $wanted.Add($tweakId) } }

    foreach ($tweakId in $wanted) {
        $tweak = $byId[$tweakId]
        if ($null -eq $tweak) { throw (Get-TuneupText -Key 'err.unknownTweak' -Format $tweakId) }
        $reason = $null
        if ($Exclude -contains $tweakId) { $reason = 'excluded' }
        elseif ($keep.Contains($tweakId) -and $Include -notcontains $tweakId) { $reason = 'kept-by-profile' }
        elseif (-not (Test-TuneupCompatible -Tweak $tweak -Environment $Environment)) { $reason = 'incompatible' }
        elseif ($Environment.IsManaged -and (Test-TuneupPolicyTweak -Tweak $tweak)) { $reason = 'managed-device' }
        elseif ($tweak.risk -eq 'high' -and $Include -notcontains $tweakId) { $reason = 'high-risk-not-requested' }
        elseif ($tweak.ask -and -not $Interactive -and $Include -notcontains $tweakId) { $reason = 'needs-confirmation' }
        else {
            $state = & $TestState $tweak
            if ($state -eq 'applied') { $reason = 'already-applied' }
            elseif ($state -eq 'not-present') { $reason = 'not-present' }
        }
        [pscustomobject]@{
            Id     = $tweakId
            Tweak  = $tweak
            Action = $(if ($reason) { 'skip' } else { 'apply' })
            Reason = $reason
        }
    }
}
