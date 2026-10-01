$script:CbsTimePattern = '^(?<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),'

function Select-TuneupCbsWindow {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][datetime]$Since,
        [datetime]$Until = [datetime]::MaxValue
    )
    # A line without its own time belongs to the entry above it.
    $inside = $false
    foreach ($line in $Lines) {
        if ($line -match $script:CbsTimePattern) {
            $time = [datetime]::ParseExact($Matches['time'], 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
            $inside = ($time -ge $Since -and $time -le $Until)
        }
        if ($inside) { $line }
    }
}

function Get-TuneupSfcSummary {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $ran = $false
    $repairing = 0
    $repaired = New-Object System.Collections.Generic.List[string]
    $unrepaired = New-Object System.Collections.Generic.List[string]
    $corrupt = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        if ($line -match '\[SR\] ') { $ran = $true }
        if ($line -match '\[SR\] Repairing (?<count>\d+) components') {
            $repairing += [int]$Matches['count']
        } elseif ($line -match '\[SR\] Cannot repair member file \[[^\]]*\]"(?<file>[^"]+)"') {
            if (-not $unrepaired.Contains($Matches['file'])) { $unrepaired.Add($Matches['file']) }
        } elseif ($line -match '\[SR\] Repairing corrupted file \[[^\]]*\]"(?<file>[^"]+)"') {
            if (-not $repaired.Contains($Matches['file'])) { $repaired.Add($Matches['file']) }
        } elseif ($line -match '\[Pnp\] Corrupt file: (?<file>.+?)\s*$') {
            if (-not $corrupt.Contains($Matches['file'])) { $corrupt.Add($Matches['file']) }
        } elseif ($line -match '\[Pnp\] Repaired file: (?<file>.+?)\s*$') {
            if (-not $repaired.Contains($Matches['file'])) { $repaired.Add($Matches['file']) }
        }
    }
    # A driver reported corrupt and never repaired is still damaged.
    foreach ($file in $corrupt) {
        if (-not $repaired.Contains($file) -and -not $unrepaired.Contains($file)) { $unrepaired.Add($file) }
    }
    $status = 'clean'
    if (-not $ran) { $status = 'unknown' }
    elseif ($unrepaired.Count) { $status = 'unrepaired' }
    elseif ($repaired.Count -or $repairing) { $status = 'repaired' }
    [pscustomobject]@{
        status          = $status
        repairedFiles   = [string[]]$repaired.ToArray()
        unrepairedFiles = [string[]]$unrepaired.ToArray()
    }
}

function Get-TuneupComponentStoreSummary {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $found = $null
    foreach ($line in $Lines) {
        # Every DISM check starts with this line; only the last one in the window counts.
        if ($line -match 'Checking System Update Readiness') {
            $found = @{ operation = $null; result = $null; detected = $null; repaired = $null }
            continue
        }
        if ($null -eq $found) { continue }
        if ($line -match 'Operation: (?<value>.+?)\s*$') { $found.operation = $Matches['value'] }
        elseif ($line -match 'Operation result: (?<value>0x[0-9a-fA-F]+)') { $found.result = $Matches['value'].ToLowerInvariant() }
        elseif ($line -match 'Total Detected Corruption:\s*(?<value>\d+)') { $found.detected = [int]$Matches['value'] }
        elseif ($line -match 'Total Repaired Corruption:\s*(?<value>\d+)') { $found.repaired = [int]$Matches['value'] }
    }
    if ($null -eq $found -or $null -eq $found.detected) {
        return [pscustomobject]@{ state = 'unknown'; operation = $null; result = $null; detected = $null; repaired = $null }
    }
    $repairMode = ([string]$found.operation -match 'Repair')
    if ($repairMode -and $found.result -and $found.result -ne '0x0') { $state = 'unrepairable' }
    elseif ($found.detected -eq 0) { $state = 'healthy' }
    elseif (-not $repairMode) { $state = 'repairable' }
    elseif ([int]$found.repaired -ge $found.detected) { $state = 'repaired' }
    else { $state = 'unrepairable' }
    [pscustomobject]@{
        state     = $state
        operation = $found.operation
        result    = $found.result
        detected  = $found.detected
        repaired  = $found.repaired
    }
}

function Get-TuneupCorruptComponentGroup {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $block = $null
    foreach ($line in $Lines) {
        if ($line -match 'Checking System Update Readiness') {
            $block = New-Object System.Collections.Generic.List[string]
            continue
        }
        if ($null -ne $block) { $block.Add($line) }
    }
    if ($null -eq $block) { return }
    $counts = @{}
    foreach ($line in $block) {
        # (Fixed) marks what a repair already fixed; the rest is still damaged.
        if ($line -notmatch '\(p\)\s+CSI Payload Corrupt\s+\([a-z]\)\s+(?<fixed>\(Fixed\)\s+)?(?<component>\S+)') { continue }
        if ($Matches['fixed']) { continue }
        $component = $Matches['component']
        if ($component -match '^(?:amd64|wow64|x86|msil|arm64|arm)_(?<name>.+?)_[0-9a-f]{16}_') { $name = $Matches['name'] }
        else { $name = ($component -split '\\')[0] }
        if ($counts.ContainsKey($name)) { $counts[$name]++ } else { $counts[$name] = 1 }
    }
    $counts.GetEnumerator() |
        Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key }; Descending = $false } |
        ForEach-Object { [pscustomobject]@{ name = $_.Key; files = $_.Value } }
}

function Get-TuneupCbsLogFile {
    param([Parameter(Mandatory)][datetime]$Since, [string]$Folder = (Join-Path $env:SystemRoot 'Logs\CBS'))
    # Windows moves CBS.log to CbsPersist_<time>.log when it grows, so a long scan can span both.
    Get-ChildItem -LiteralPath $Folder -Filter 'CbsPersist_*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since } | Sort-Object LastWriteTime | ForEach-Object { $_.FullName }
    $current = Join-Path $Folder 'CBS.log'
    if (Test-Path -LiteralPath $current -PathType Leaf) { $current }
}

function Read-TuneupCbsLog {
    param(
        [Parameter(Mandatory)][datetime]$Since,
        [datetime]$Until = [datetime]::MaxValue,
        [string]$Folder = (Join-Path $env:SystemRoot 'Logs\CBS')
    )
    foreach ($path in @(Get-TuneupCbsLogFile -Since $Since -Folder $Folder)) {
        # TrustedInstaller keeps CBS.log open for writing, so it is read sharing read and write.
        $stream = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]'ReadWrite, Delete')
        $reader = New-Object System.IO.StreamReader -ArgumentList $stream, ([System.Text.Encoding]::UTF8), $true
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        Select-TuneupCbsWindow -Lines @($text -split "`r?`n" | Where-Object { $_ }) -Since $Since -Until $Until
    }
}

function ConvertFrom-TuneupToolOutput {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    if (-not $Bytes.Length) { return '' }
    # sfc writes UTF-16 when its output is redirected; DISM writes in the OEM code page.
    $zeros = @($Bytes | Where-Object { $_ -eq 0 }).Count
    if ($zeros * 4 -ge $Bytes.Length) {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes)
    } else {
        $text = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage).GetString($Bytes)
    }
    $lines = @($text.TrimStart([char]0xFEFF) -split '[\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    ($lines | Select-Object -Last 15) -join [Environment]::NewLine
}

function Invoke-TuneupHealthTool {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = $Arguments -join ' '
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.CreateNoWindow = $true
    # The raw bytes are kept and decoded afterwards: the tool picks the encoding, not the console.
    $buffer = New-Object System.IO.MemoryStream
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $process.StandardOutput.BaseStream.CopyTo($buffer)
        $process.WaitForExit()
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = (ConvertFrom-TuneupToolOutput -Bytes $buffer.ToArray()) }
    } finally {
        $process.Dispose()
        $buffer.Dispose()
    }
}

function Invoke-TuneupSfc {
    Invoke-TuneupHealthTool -FilePath (Join-Path $env:SystemRoot 'System32\sfc.exe') -Arguments @('/scannow')
}

function Invoke-TuneupDism {
    param([Parameter(Mandatory)][ValidateSet('ScanHealth', 'RestoreHealth')][string]$Operation)
    Invoke-TuneupHealthTool -FilePath (Join-Path $env:SystemRoot 'System32\Dism.exe') -Arguments @('/Online', '/Cleanup-Image', "/$Operation", '/English')
}