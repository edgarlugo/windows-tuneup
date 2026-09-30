$script:TuneupLang = 'en'
$script:TuneupStrings = @{}

function Initialize-TuneupI18n {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Lang
    )
    if (-not $Lang) {
        $Lang = $(if ((Get-UICulture).TwoLetterISOLanguageName -eq 'es') { 'es' } else { 'en' })
    }
    $file = Join-Path $Root "$Lang.json"
    if (-not (Test-Path -LiteralPath $file)) {
        $Lang = 'en'
        $file = Join-Path $Root 'en.json'
    }
    $json = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:TuneupStrings = @{}
    foreach ($property in $json.PSObject.Properties) {
        $script:TuneupStrings[$property.Name] = [string]$property.Value
    }
    $script:TuneupLang = $Lang
}

function Get-TuneupLang {
    $script:TuneupLang
}

function Get-TuneupText {
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$Format = @()
    )
    $text = $script:TuneupStrings[$Key]
    if ($null -eq $text) { return $Key }
    if ($Format.Count) { return ($text -f $Format) }
    $text
}

function Get-TuneupTitle {
    param([Parameter(Mandatory)]$Tweak)
    $title = $Tweak.title.($script:TuneupLang)
    if (-not $title) { $title = $Tweak.title.en }
    if (-not $title) { $title = $Tweak.id }
    $title
}
