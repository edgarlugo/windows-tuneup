$script:Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false

function Get-TuneupStateRoot {
    param([string]$StateRoot, [switch]$Machine)
    if ($StateRoot) { return $StateRoot }
    $folder = $(if ($Machine) { 'CommonApplicationData' } else { 'LocalApplicationData' })
    $base = [Environment]::GetFolderPath($folder)
    if (-not $base) { throw "Cannot find the state folder: $folder is not available" }
    Join-Path $base 'windows-tuneup'
}

function Get-TuneupRootKind {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    foreach ($kind in 'machine', 'user') {
        try { $root = Get-TuneupStateRoot -Machine:($kind -eq 'machine') } catch { continue }
        $prefix = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        if ($full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $kind }
    }
    'custom'
}

function Resolve-TuneupFileRoot {
    param([Parameter(Mandatory)][string]$Path, [string]$Root)
    if ($Root -and @('machine', 'user', 'custom') -notcontains $Root) { throw "Unknown state root '$Root'" }
    # A path inside a real state folder always gets that folder's rules, whatever the caller says.
    $kind = Get-TuneupRootKind -Path $Path
    if ($kind -ne 'custom') { return $kind }
    if ($Root) { return $Root }
    'custom'
}

function Test-TuneupUserScopedTweak {
    param([AllowNull()]$Tweak)
    if ($null -eq $Tweak -or $null -eq $Tweak.set) { return $false }
    $path = $Tweak.set.path
    ($Tweak.scope -is [string]) -and ($Tweak.scope -ceq 'user') -and
    ($Tweak.type -is [string]) -and ($Tweak.type -ceq 'registry') -and
    ($path -is [string]) -and ($path -match '^HKCU:\\')
}

function Read-TuneupStateFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Root, [switch]$IgnoreUntrusted)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    if ((Resolve-TuneupFileRoot -Path $Path -Root $Root) -ne 'machine') {
        return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
    }
    try {
        $stream = Open-TuneupTrustedStream -Path $Path
    }
    catch {
        if (-not $IgnoreUntrusted) { throw }
        if ($_.Exception.GetBaseException() -is [System.IO.IOException]) {
            Write-Warning "State file $Path is in use or could not be opened; ignoring it for now"
        }
        else {
            Write-Warning "Ignoring untrusted state file $Path"
        }
        return $null
    }
    $reader = New-Object System.IO.StreamReader -ArgumentList $stream, $script:Utf8NoBom, $true
    try { $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

function Write-TuneupStateFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$Append,
        [string]$Root,
        # Fails with an IOException when the file exists, instead of replacing it.
        [switch]$CreateNew
    )
    if ((Resolve-TuneupFileRoot -Path $Path -Root $Root) -ne 'machine') {
        if ($Append) { [System.IO.File]::AppendAllText($Path, $Text, $script:Utf8NoBom) }
        elseif ($CreateNew) {
            $bytes = $script:Utf8NoBom.GetBytes($Text)
            $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try { $stream.Write($bytes, 0, $bytes.Length) }
            finally { $stream.Dispose() }
        }
        else { [System.IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom) }
        return
    }
    if ($Append -and (Test-Path -LiteralPath $Path)) {
        $stream = Open-TuneupTrustedStream -Path $Path -Append
    }
    else {
        $parent = Split-Path -Parent $Path
        if (-not (Test-TuneupTrustedItem -Path $parent)) { throw (Get-TuneupUntrustedMessage -Path $parent) }
        if (-not $CreateNew -and (Test-Path -LiteralPath $Path)) { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
        $stream = New-TuneupSecureFile -Path $Path -Security (New-TuneupStateSecurity -File)
    }
    try {
        $bytes = $script:Utf8NoBom.GetBytes($Text)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $stream.Dispose()
    }
}

function Save-TuneupJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object, [string]$Root, [switch]$CreateNew)
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    Write-TuneupStateFile -Path $Path -Text $json -Root $Root -CreateNew:$CreateNew
}

function Read-TuneupTrustedJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Root)
    $text = Read-TuneupStateFile -Path $Path -Root $Root -IgnoreUntrusted
    if (-not $text) { return $null }
    try {
        $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Ignoring unreadable state file $Path"
        $null
    }
}

function Add-TuneupJournalEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Tweak,
        [Parameter(Mandatory)][AllowNull()]$State,
        [string]$Root
    )
    if ((Resolve-TuneupFileRoot -Path $Path -Root $Root) -eq 'user' -and -not (Test-TuneupUserScopedTweak -Tweak $Tweak)) {
        throw "Cannot journal machine-scope tweak '$($Tweak.id)' in the user state folder"
    }
    $entry = [pscustomobject]@{ id = $Tweak.id; tweak = $Tweak; state = $State }
    $line = ConvertTo-Json -InputObject $entry -Depth 10 -Compress
    Write-TuneupStateFile -Path $Path -Text ($line + [Environment]::NewLine) -Append -Root $Root
}

function Read-TuneupJournal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Root)
    $kind = Resolve-TuneupFileRoot -Path $Path -Root $Root
    $text = Read-TuneupStateFile -Path $Path -Root $kind
    if ($null -eq $text) { return }
    $lines = @($text -split "`r?`n")
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
        if ($kind -eq 'user' -and -not (Test-TuneupUserScopedTweak -Tweak $entry.tweak)) {
            Write-Warning "Ignoring machine-scope entry '$($entry.id)' in user journal $Path"
            continue
        }
        $entry
    }
}
