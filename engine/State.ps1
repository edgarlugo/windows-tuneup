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
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
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
    foreach ($line in [System.IO.File]::ReadAllLines($Path, $script:Utf8NoBom)) {
        if ($line.Trim()) { $line | ConvertFrom-Json }
    }
}

function Get-TuneupRunList {
    param([string]$StateRoot)
    $runsDir = Join-Path (Get-TuneupStateRoot -StateRoot $StateRoot) 'runs'
    if (-not (Test-Path -LiteralPath $runsDir)) { return }
    foreach ($dir in Get-ChildItem -LiteralPath $runsDir -Directory | Sort-Object Name) {
        [pscustomobject]@{
            Id     = $dir.Name
            Dir    = $dir.FullName
            Undone = (Test-Path -LiteralPath (Join-Path $dir.FullName 'undone.json'))
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
