$script:TweakRisks = @('low', 'medium', 'high')
$script:TweakScopes = @('machine', 'user')
$script:TweakFamilies = @('10', '11')
$script:TweakEditions = @('Home', 'Pro', 'Enterprise', 'Education')
# Hardware a tweak can ask for in its optional requires list; the planner checks them.
$script:TweakRequirements = @('battery', 'no-battery')

function Import-TuneupCatalog {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($file in Get-ChildItem -LiteralPath $Path -Filter '*.json' | Sort-Object Name) {
        $data = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $tweaksProperty = $null
        if ($null -ne $data) { $tweaksProperty = $data.PSObject.Properties['tweaks'] }
        if ($null -eq $tweaksProperty -or $tweaksProperty.Value -isnot [array]) {
            [pscustomobject]@{ id = $null; sourceFile = $file.Name; loadError = "file $($file.Name) has no tweaks array" }
            continue
        }
        foreach ($tweak in @($tweaksProperty.Value)) {
            if ($null -eq $tweak) { continue }
            $tweak | Add-Member -NotePropertyName sourceFile -NotePropertyValue $file.Name -Force
            $tweak
        }
    }
}

function Test-TuneupIntegerInRange {
    param($Value, [decimal]$Min, [decimal]$Max)
    $integerTypes = @([int], [long], [uint32], [uint64], [int16], [uint16], [byte], [sbyte])
    $isInteger = $false
    foreach ($type in $integerTypes) { if ($Value -is $type) { $isInteger = $true } }
    if (-not $isInteger) { return $false }
    $number = [decimal]$Value
    return ($number -ge $Min -and $number -le $Max)
}

function Test-TuneupTweak {
    param([Parameter(Mandatory)]$Tweak)
    $errors = New-Object System.Collections.Generic.List[string]
    if ($Tweak.loadError) {
        $errors.Add([string]$Tweak.loadError)
        return $errors.ToArray()
    }
    $id = [string]$Tweak.id
    if ($id -cnotmatch '^[a-z]+(\.[a-z0-9-]+)+$') {
        $errors.Add("invalid id '$id'")
        return $errors.ToArray()
    }
    if ($Tweak.sourceFile -and ($id.Split('.')[0] + '.json') -ne $Tweak.sourceFile) {
        $errors.Add("$id does not match file $($Tweak.sourceFile)")
    }
    foreach ($field in 'title', 'why') {
        foreach ($lang in 'es', 'en') {
            if ([string]::IsNullOrWhiteSpace([string]$Tweak.$field.$lang)) { $errors.Add("$id is missing $field.$lang") }
        }
    }
    if ($script:TweakRisks -notcontains $Tweak.risk) { $errors.Add("$id has an invalid risk '$($Tweak.risk)'") }
    if ($script:TweakScopes -cnotcontains $Tweak.scope) { $errors.Add("$id has an invalid scope '$($Tweak.scope)'") }
    if ($Tweak.ask -isnot [bool]) { $errors.Add("$id ask must be true or false") }
    if ($Tweak.rebootRequired -isnot [bool]) { $errors.Add("$id rebootRequired must be true or false") }
    $signOutProperty = $Tweak.PSObject.Properties['signOutRequired']
    if ($null -ne $signOutProperty -and $signOutProperty.Value -isnot [bool]) { $errors.Add("$id signOutRequired must be true or false") }
    $requiresProperty = $Tweak.PSObject.Properties['requires']
    if ($null -ne $requiresProperty) {
        # A bare string is not a list, even though it would work as a list of one.
        $requires = @($requiresProperty.Value)
        if ($requiresProperty.Value -isnot [System.Array] -or -not $requires.Count -or @($requires | Where-Object { $_ -isnot [string] -or $script:TweakRequirements -cnotcontains $_ }).Count) {
            $errors.Add("$id has invalid requires: use a list of $($script:TweakRequirements -join ', ')")
        } elseif ($requires -ccontains 'battery' -and $requires -ccontains 'no-battery') {
            $errors.Add("$id requires both battery and no-battery")
        }
    }

    $families = @($Tweak.os.families | Where-Object { $_ })
    if (-not $families.Count -or @($families | Where-Object { $script:TweakFamilies -notcontains $_ }).Count) {
        $errors.Add("$id has invalid os.families")
    }
    $editions = @($Tweak.os.editions | Where-Object { $_ })
    if (-not $editions.Count -or @($editions | Where-Object { $script:TweakEditions -notcontains $_ }).Count) {
        $errors.Add("$id has invalid os.editions")
    }
    $minBuild = 0
    if (-not [int]::TryParse([string]$Tweak.os.minBuild, [ref]$minBuild) -or $minBuild -le 0) {
        $errors.Add("$id is missing os.minBuild")
    }
    $sources = @($Tweak.sources | Where-Object { $_ })
    if (-not $sources.Count -or @($sources | Where-Object { $_ -notmatch '^https://' }).Count) {
        $errors.Add("$id needs https sources")
    }

    $handler = Get-TuneupHandler -Type $Tweak.type
    if ($null -eq $handler) {
        $errors.Add("$id has an unsupported type '$($Tweak.type)'")
    } else {
        foreach ($problem in @(& "Test-$($handler.Name)TweakDefinition" -Tweak $Tweak)) { $errors.Add("$id $problem") }
    }
    $errors.ToArray()
}

function Test-TuneupCatalog {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Catalog)
    $seen = @{}
    foreach ($tweak in $Catalog) {
        Test-TuneupTweak -Tweak $tweak
        if ($tweak.loadError) { continue }
        $id = [string]$tweak.id
        if ($seen.ContainsKey($id)) { "duplicate id $id" } else { $seen[$id] = $true }
    }
}

function Import-TuneupProfileSet {
    param([Parameter(Mandatory)][string]$Path)
    foreach ($file in Get-ChildItem -LiteralPath $Path -Filter '*.json' | Sort-Object Name) {
        $profileData = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $profileData | Add-Member -NotePropertyName sourceFile -NotePropertyValue $file.Name -Force
        $profileData
    }
}

function Test-TuneupProfileSet {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Profiles,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Catalog
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $byId = @{}
    foreach ($tweak in $Catalog) { $byId[[string]$tweak.id] = $tweak }
    if (-not @($Profiles | Where-Object { $_.id -eq 'base' }).Count) { $errors.Add('the base profile is missing') }
    $names = @{}
    foreach ($profileData in $Profiles) {
        $profileId = [string]$profileData.id
        if ($profileId -cnotmatch '^[a-z]+$') { $errors.Add("invalid profile id '$profileId'"); continue }
        if ($profileData.sourceFile -and "$profileId.json" -ne $profileData.sourceFile) {
            $errors.Add("profile $profileId does not match file $($profileData.sourceFile)")
        }
        foreach ($name in @($profileId) + @($profileData.aliases | Where-Object { $_ })) {
            $key = ([string]$name).ToLowerInvariant()
            if ($names.ContainsKey($key)) { $errors.Add("profile name '$name' is used by $($names[$key]) and $profileId") }
            else { $names[$key] = $profileId }
        }
        foreach ($field in 'title', 'description') {
            foreach ($lang in 'es', 'en') {
                if ([string]::IsNullOrWhiteSpace([string]$profileData.$field.$lang)) { $errors.Add("profile $profileId is missing $field.$lang") }
            }
        }
        foreach ($tweakId in @($profileData.include | Where-Object { $_ }) + @($profileData.keep | Where-Object { $_ })) {
            if (-not $byId.ContainsKey($tweakId)) { $errors.Add("profile $profileId references unknown tweak $tweakId") }
        }
        foreach ($tweakId in @($profileData.include | Where-Object { $_ })) {
            if ($byId.ContainsKey($tweakId) -and $byId[$tweakId].risk -eq 'high') {
                $errors.Add("profile $profileId includes high-risk tweak $tweakId")
            }
        }
    }
    $errors.ToArray()
}
