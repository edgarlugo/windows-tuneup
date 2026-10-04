<#
.SYNOPSIS
    Writes docs/es/catalog.md and docs/en/catalog.md from the catalog, the profiles and
    catalog/notes/excluded.json. The texts of the page come from build/catalog-doc.labels.json.
.PARAMETER OutDir
    Folder that receives es/catalog.md and en/catalog.md. By default the docs folder of the repository;
    the tests write to a temporary folder and compare.
#>
param([string]$OutDir)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $root 'docs' }
$categories = @('privacy', 'ads', 'ui', 'ai', 'edge', 'services', 'tasks', 'performance', 'power', 'gaming', 'dev', 'apps')
$profileOrder = @('base', 'dev', 'gaming', 'privacy', 'laptop', 'legacy', 'work', 'lite')

function Read-DocJson {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Format-DocCell {
    param([AllowNull()][string]$Text)
    ([string]$Text).Replace('|', '\|')
}

$labels = Read-DocJson -Path (Join-Path $PSScriptRoot 'catalog-doc.labels.json')
$excluded = Read-DocJson -Path (Join-Path $root 'catalog\notes\excluded.json')
$tweaksByCategory = [ordered]@{}
foreach ($category in $categories) {
    $file = Join-Path $root "catalog\$category.json"
    $tweaksByCategory[$category] = @($(if (Test-Path -LiteralPath $file) { (Read-DocJson -Path $file).tweaks }))
}
$allTweaks = @($tweaksByCategory.Values | ForEach-Object { $_ })
$profiles = @($profileOrder | ForEach-Object {
        $file = Join-Path $root "profiles\$_.json"
        if (Test-Path -LiteralPath $file) { Read-DocJson -Path $file }
    })

function Get-DocProfileList {
    param([Parameter(Mandatory)][string]$TweakId, [Parameter(Mandatory)][string]$Field, [Parameter(Mandatory)]$Text)
    $names = @($profiles | Where-Object { @($_.$Field) -contains $TweakId } | ForEach-Object { '`' + $_.id + '`' })
    $(if ($names.Count) { $names -join ', ' } else { $Text.none })
}

function New-DocPage {
    param([Parameter(Mandatory)][string]$Lang)
    $text = $labels.$Lang
    $lines = New-Object System.Collections.Generic.List[string]
    $add = { param([string]$Line) $lines.Add($Line) }

    & $add "# $($text.heading)"
    & $add ''
    & $add $text.generated
    & $add ''
    & $add $text.otherLanguage
    & $add ''
    & $add "## $($text.summary)"
    & $add ''
    & $add "| $($text.category) | $($text.tweaks) |"
    & $add '|---|---|'
    foreach ($category in $categories) {
        & $add "| $($text."category.$category") (``$category``) | $($tweaksByCategory[$category].Count) |"
    }
    & $add "| **$($text.total)** | **$($allTweaks.Count)** |"
    & $add ''
    & $add "## $($text.profiles)"
    & $add ''
    & $add "| $($text.profile) | $($text.aliases) | $($text.includes) | $($text.keeps) |"
    & $add '|---|---|---|---|'
    foreach ($profileData in $profiles) {
        $aliases = @($profileData.aliases | ForEach-Object { '`' + $_ + '`' }) -join ', '
        & $add "| ``$($profileData.id)`` $(Format-DocCell $profileData.title.$Lang) | $aliases | $(@($profileData.include).Count) | $(@($profileData.keep).Count) |"
    }
    & $add ''

    & $add "## $($text.askHeading)"
    & $add ''
    & $add $text.askIntro
    & $add ''
    foreach ($tweak in $allTweaks | Where-Object { $_.ask }) { & $add "- ``$($tweak.id)``: $($tweak.title.$Lang)" }
    & $add ''
    & $add "## $($text.highHeading)"
    & $add ''
    & $add $text.highIntro
    & $add ''
    foreach ($tweak in $allTweaks | Where-Object { $_.risk -eq 'high' }) { & $add "- ``$($tweak.id)``: $($tweak.title.$Lang)" }
    & $add ''
    & $add "## $($text.homeHeading)"
    & $add ''
    & $add $text.homeIntro
    & $add ''
    & $add "| $($text.id) | $($text.title) | $($text.editions) |"
    & $add '|---|---|---|'
    foreach ($tweak in $allTweaks | Where-Object { @($_.os.editions) -notcontains 'Home' }) {
        & $add "| ``$($tweak.id)`` | $(Format-DocCell $tweak.title.$Lang) | $(@($tweak.os.editions) -join ', ') |"
    }
    & $add ''

    foreach ($category in $categories) {
        & $add "## $($text."category.$category") (``catalog/$category.json``)"
        & $add ''
        foreach ($tweak in $tweaksByCategory[$category]) {
            & $add "### ``$($tweak.id)``"
            & $add ''
            & $add "**$($tweak.title.$Lang)**"
            & $add ''
            & $add $tweak.why.$Lang
            & $add ''
            & $add "- **$($text.type):** ``$($tweak.type)``; **$($text.scope):** $($text."scope.$($tweak.scope)"); **$($text.risk):** $($text."risk.$($tweak.risk)"); **$($text.ask):** $(if ($tweak.ask) { $text.yes } else { $text.no })"
            & $add "- **$($text.inProfiles):** $(Get-DocProfileList -TweakId $tweak.id -Field 'include' -Text $text); **$($text.keptBy):** $(Get-DocProfileList -TweakId $tweak.id -Field 'keep' -Text $text)"
            $build = $text.build -f $tweak.os.minBuild
            & $add "- **$($text.windows):** $(@($tweak.os.families) -join ', '), $build; **$($text.editions):** $(@($tweak.os.editions) -join ', ')"
            if ($null -ne $tweak.PSObject.Properties['requires']) {
                & $add "- **$($text.requires):** $(@($tweak.requires | ForEach-Object { $text."requires.$_" }) -join ', ')"
            }
            $after = @()
            if ($tweak.rebootRequired) { $after += $text.'after.reboot' }
            if ($null -ne $tweak.PSObject.Properties['signOutRequired'] -and $tweak.signOutRequired) { $after += $text.'after.signOut' }
            if (-not $after.Count) { $after = @($text.'after.nothing') }
            & $add "- **$($text.afterApplying):** $($after -join ', ')"
            if ($null -ne $tweak.PSObject.Properties['manualSetting']) {
                & $add "- **$($text.manualSetting):** $($tweak.manualSetting.$Lang)"
            }
            & $add "- **$($text.sources):** $(@($tweak.sources | ForEach-Object { "<$_>" }) -join ', ')"
            & $add ''
        }
    }

    & $add "## $($text.excludedHeading)"
    & $add ''
    & $add $text.excludedIntro
    & $add ''
    foreach ($group in $excluded.groups) {
        & $add "### $($group.title.$Lang)"
        & $add ''
        & $add $group.intro.$Lang
        & $add ''
        foreach ($item in $group.items) {
            # A product name is the same in both languages unless the notes give one per language.
            $name = $(if ($item.name -is [string]) { $item.name } else { $item.name.$Lang })
            $package = $(if ($item.appx) { " (``$($item.appx)``)" } else { '' })
            & $add "- **$name**$($package): $($item.why.$Lang)"
        }
        & $add ''
    }
    # One trailing line break, CRLF like every text file of the repository.
    ($lines.ToArray() -join "`r`n").TrimEnd() + "`r`n"
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
foreach ($lang in 'es', 'en') {
    $folder = Join-Path $OutDir $lang
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    $path = Join-Path $folder 'catalog.md'
    [System.IO.File]::WriteAllText($path, (New-DocPage -Lang $lang), $utf8)
    Write-Output "Wrote $path"
}
