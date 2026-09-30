$script:TweakRisks = @('low', 'medium', 'high')
$script:TweakScopes = @('machine', 'user')
$script:TweakFamilies = @('10', '11')
$script:TweakEditions = @('Home', 'Pro', 'Enterprise', 'Education')
$script:RegistryKinds = @('DWord', 'QWord', 'String', 'ExpandString')
$script:ServiceStartTypes = @('Automatic', 'AutomaticDelayed', 'Manual', 'Disabled')
$script:TaskStates = @('Enabled', 'Disabled')

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

function Test-TuneupRegistryValue {
    param([string]$Kind, $Value)
    if ($Value -is [array]) { return $false }
    switch ($Kind) {
        'DWord' { return (Test-TuneupIntegerInRange -Value $Value -Min -2147483648 -Max 4294967295) }
        'QWord' { return (Test-TuneupIntegerInRange -Value $Value -Min -9223372036854775808 -Max 9223372036854775807) }
        default { return ($Value -is [string]) }
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
    if ($script:TweakScopes -notcontains $Tweak.scope) { $errors.Add("$id has an invalid scope '$($Tweak.scope)'") }
    if ($Tweak.ask -isnot [bool]) { $errors.Add("$id ask must be true or false") }
    if ($Tweak.rebootRequired -isnot [bool]) { $errors.Add("$id rebootRequired must be true or false") }

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

    $set = $Tweak.set
    switch ($Tweak.type) {
        'registry' {
            if ([string]$set.path -notmatch '^(HKLM|HKCU):\\.+') {
                $errors.Add("$id has an invalid registry path")
            } elseif (([string]$set.path -match '^HKCU:') -ne ($Tweak.scope -eq 'user')) {
                $errors.Add("$id scope does not match its registry hive")
            }
            if ([string]::IsNullOrEmpty([string]$set.name)) { $errors.Add("$id is missing set.name") }
            if ($null -ne $set.value) {
                if ($script:RegistryKinds -notcontains $set.kind) {
                    $errors.Add("$id has an invalid registry kind '$($set.kind)'")
                } elseif (-not (Test-TuneupRegistryValue -Kind $set.kind -Value $set.value)) {
                    $errors.Add("$id has a value that does not match kind $($set.kind)")
                }
            }
        }
        'service' {
            if ([string]::IsNullOrEmpty([string]$set.name)) { $errors.Add("$id is missing set.name") }
            if ($script:ServiceStartTypes -notcontains $set.startType) { $errors.Add("$id has an invalid startType '$($set.startType)'") }
            if ($set.stop -isnot [bool]) { $errors.Add("$id set.stop must be true or false") }
            if ($Tweak.scope -ne 'machine') { $errors.Add("$id must use scope machine") }
        }
        'task' {
            if ([string]$set.path -notmatch '^\\(.*\\)?$') { $errors.Add("$id task path must start and end with a backslash") }
            if ([string]::IsNullOrEmpty([string]$set.name)) { $errors.Add("$id is missing set.name") }
            if (([string]$set.name + [string]$set.path) -match '[*?\[\]]') { $errors.Add("$id task name and path cannot contain wildcard characters") }
            if ($script:TaskStates -notcontains $set.state) { $errors.Add("$id has an invalid task state '$($set.state)'") }
            if ($Tweak.scope -ne 'machine') { $errors.Add("$id must use scope machine") }
        }
        default { $errors.Add("$id has an unsupported type '$($Tweak.type)'") }
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
