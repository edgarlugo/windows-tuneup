$script:Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false

function Get-TuneupStateRoot {
    param([string]$StateRoot)
    if ($StateRoot) { return $StateRoot }
    Join-Path $env:ProgramData 'windows-tuneup'
}

function New-TuneupRun {
    param([string]$StateRoot)
    $runsDir = Join-Path (Get-TuneupStateRoot -StateRoot $StateRoot) 'runs'
    $baseId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $id = $baseId
    $counter = 1
    while (Test-Path -LiteralPath (Join-Path $runsDir $id)) {
        $counter++
        $id = '{0}-{1:D2}' -f $baseId, $counter
    }
    $dir = Join-Path $runsDir $id
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    [pscustomobject]@{ Id = $id; Dir = $dir }
}

function Save-TuneupJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    [System.IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)
}

function Add-TuneupJournalEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Tweak,
        [Parameter(Mandatory)][AllowNull()]$State
    )
    $entry = [pscustomobject]@{ id = $Tweak.id; tweak = $Tweak; state = $State }
    $line = ConvertTo-Json -InputObject $entry -Depth 10 -Compress
    [System.IO.File]::AppendAllText($Path, $line + [Environment]::NewLine, $script:Utf8NoBom)
}

function Read-TuneupJournal {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = [System.IO.File]::ReadAllLines($Path, $script:Utf8NoBom)
    $lastIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim()) { $lastIndex = $i }
    }
    for ($i = 0; $i -le $lastIndex; $i++) {
        if (-not $lines[$i].Trim()) { continue }
        try {
            $entry = $lines[$i] | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            if ($i -eq $lastIndex) {
                Write-Warning "Ignoring incomplete last journal line in $Path"
                return
            }
            throw "Journal $Path is corrupt at line $($i + 1)"
        }
        $entry
    }
}

function Get-TuneupRunList {
    param([string]$StateRoot)
    $runsDir = Join-Path (Get-TuneupStateRoot -StateRoot $StateRoot) 'runs'
    if (-not (Test-Path -LiteralPath $runsDir)) { return }
    $byName = @{}
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($dir in Get-ChildItem -LiteralPath $runsDir -Directory) {
        if ($dir.Name -cmatch '^[0-9]{8}-[0-9]{6}(-[0-9]{2})?$') {
            $byName[$dir.Name] = $dir
            $names.Add($dir.Name)
        }
    }
    $names.Sort([System.StringComparer]::Ordinal)
    foreach ($name in $names) {
        [pscustomobject]@{
            Id     = $name
            Dir    = $byName[$name].FullName
            Undone = (Test-Path -LiteralPath (Join-Path $byName[$name].FullName 'undone.json'))
        }
    }
}

function Resolve-TuneupRun {
    param([string]$StateRoot, [Parameter(Mandatory)][string]$RunId)
    $runs = @(Get-TuneupRunList -StateRoot $StateRoot |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.Dir 'snapshot.jsonl') })
    if ($RunId -eq 'last') {
        return ($runs | Where-Object { -not $_.Undone } | Select-Object -Last 1)
    }
    $runs | Where-Object { $_.Id -eq $RunId } | Select-Object -First 1
}
