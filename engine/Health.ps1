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

# CSI writes a file as [l:11]'name' (newer builds), [l:7]"name" (older ones) or as a bare path.
function ConvertTo-TuneupCbsFilePath {
    param([Parameter(Mandatory)][string]$Text)
    $path = $Text.Trim() -replace '^\[[^\]]*\]', ''
    if ($path -match '^[''"](?<quoted>[^''"]+)[''"]') { $path = $Matches['quoted'] }
    else { $path = $path -replace '\s+from store\s*$', '' }
    # \??\ is the NT prefix of a drive path.
    $path -replace '^\\\?\?\\', ''
}

function Get-TuneupSfcSummary {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $all = @($Lines)
    # Only the latest completed SFC run counts. It checks the components in many "Verifying" batches
    # and ends with "Repair complete"; the driver lines follow it. Whatever comes after that (an
    # interrupted run, background [SR] work) and the [SR] lines before its first "Verifying" are noise.
    $done = @(for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -match '\[SR\] Repair complete') { $i } })
    $start = -1
    if ($done.Count) {
        $last = $done[-1]
        $previousEnd = $(if ($done.Count -ge 2) { $done[-2] } else { -1 })
        for ($i = $previousEnd + 1; $i -le $last -and $start -lt 0; $i++) {
            if ($all[$i] -match '\[SR\] Verifying \d+ components') { $start = $i }
        }
    }
    if ($start -lt 0) {
        return [pscustomobject]@{ status = 'unknown'; repairedFiles = [string[]]@(); unrepairedFiles = [string[]]@() }
    }
    $run = New-Object System.Collections.Generic.List[string]
    for ($i = $start; $i -le $last; $i++) { $run.Add($all[$i]) }
    for ($i = $last + 1; $i -lt $all.Count -and $all[$i] -notmatch '\[SR\] '; $i++) {
        if ($all[$i] -match '\[Pnp\] ') { $run.Add($all[$i]) }
    }
    $repairing = 0
    $repaired = New-Object System.Collections.Generic.List[string]
    $cannot = New-Object System.Collections.Generic.List[object]
    $reprojected = New-Object System.Collections.Generic.List[string]
    $corrupt = New-Object System.Collections.Generic.List[string]
    foreach ($line in $run) {
        if ($line -match '\[SR\] Repairing (?<count>\d+) components') {
            $repairing = [int]$Matches['count']
        } elseif ($line -match '\[SR\] Cannot repair member file \[[^\]]*\][''"](?<file>[^''"]+)[''"](?: of (?<component>[^,]+),(?: version [^,]+,)? arch (?<arch>[^,]+),)?') {
            $entry = [pscustomobject]@{ file = $Matches['file']; component = $Matches['component']; arch = $Matches['arch'] }
            $entry | Add-Member -NotePropertyName key -NotePropertyValue "$($entry.file)|$($entry.component)|$($entry.arch)"
            if (-not @($cannot | Where-Object { $_.key -eq $entry.key }).Count) { $cannot.Add($entry) }
        } elseif ($line -match '\[SR\] Could not reproject corrupted file (?<raw>[^;]+?)\s*(?:;|$)') {
            $path = ConvertTo-TuneupCbsFilePath -Text $Matches['raw']
            if (-not $reprojected.Contains($path)) { $reprojected.Add($path) }
        } elseif ($line -match '\[SR\] Repairing corrupted file (?<raw>.+?)\s*$') {
            $path = ConvertTo-TuneupCbsFilePath -Text $Matches['raw']
            if (-not $repaired.Contains($path)) { $repaired.Add($path) }
        } elseif ($line -match '\[Pnp\] Corrupt file: (?<file>.+?)\s*$') {
            if (-not $corrupt.Contains($Matches['file'])) { $corrupt.Add($Matches['file']) }
        } elseif ($line -match '\[Pnp\] Repaired file: (?<file>.+?)\s*$') {
            if (-not $repaired.Contains($Matches['file'])) { $repaired.Add($Matches['file']) }
        }
    }
    $unrepaired = New-Object System.Collections.Generic.List[string]
    # "Cannot repair" gives the file name and its component; when SFC also gives the full path, that is used.
    foreach ($entry in $cannot) {
        $leaf = $entry.file
        if (@($reprojected | Where-Object { [System.IO.Path]::GetFileName($_) -eq $leaf }).Count) { continue }
        $label = $(if ($entry.component) { "$($entry.file) ($($entry.component), $($entry.arch))" } else { $entry.file })
        if (-not $unrepaired.Contains($label)) { $unrepaired.Add($label) }
    }
    # A driver reported corrupt and never repaired is still damaged.
    foreach ($file in (@($reprojected) + @($corrupt))) {
        if (-not $repaired.Contains($file) -and -not $unrepaired.Contains($file)) { $unrepaired.Add($file) }
    }
    $status = 'clean'
    if ($unrepaired.Count) { $status = 'unrepaired' }
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
    $failed = ($found.result -and $found.result -ne '0x0')
    if ($repairMode -and $failed) { $state = 'unrepairable' }
    # A scan that failed and counted nothing did not look at anything.
    elseif ($failed -and $found.detected -eq 0) { $state = 'unknown' }
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

# Compressed CbsPersist_*.cab logs are not read: Windows only compresses logs that are older than a scan.
function Get-TuneupCbsLogFile {
    param([Parameter(Mandatory)][datetime]$Since, [string]$Folder = (Join-Path $env:SystemRoot 'Logs\CBS'))
    # Windows moves CBS.log to CbsPersist_<time>.log when it grows, so a long scan can span both.
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return }
    Get-ChildItem -LiteralPath $Folder -Filter 'CbsPersist_*.log' -File |
        Where-Object { $_.LastWriteTime -ge $Since } | Sort-Object LastWriteTime | ForEach-Object { $_.FullName }
    $current = Join-Path $Folder 'CBS.log'
    if (Test-Path -LiteralPath $current -PathType Leaf) { $current }
}

function Read-TuneupCbsLogFile {
    param([Parameter(Mandatory)][string]$Path)
    # TrustedInstaller keeps CBS.log open for writing, so it is read sharing read and write.
    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]'ReadWrite, Delete')
    $reader = New-Object System.IO.StreamReader -ArgumentList $stream, ([System.Text.Encoding]::UTF8), $true
    try { $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Read-TuneupCbsLog {
    param(
        [Parameter(Mandatory)][datetime]$Since,
        [datetime]$Until = [datetime]::MaxValue,
        [string]$Folder = (Join-Path $env:SystemRoot 'Logs\CBS')
    )
    $texts = $null
    # A log can rotate between listing and opening it: the listing is made again once.
    for ($attempt = 1; $attempt -le 2 -and $null -eq $texts; $attempt++) {
        try {
            $texts = @(foreach ($path in @(Get-TuneupCbsLogFile -Since $Since -Folder $Folder)) { Read-TuneupCbsLogFile -Path $path })
        } catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException] {
            if ($attempt -eq 2) { throw }
        }
    }
    foreach ($text in $texts) {
        Select-TuneupCbsWindow -Lines @($text -split "`r?`n" | Where-Object { $_ }) -Since $Since -Until $Until
    }
}

function ConvertFrom-TuneupToolOutput {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [ValidateSet('Auto', 'Unicode', 'Oem')][string]$Encoding = 'Auto'
    )
    if (-not $Bytes.Length) { return '' }
    # sfc writes UTF-16 when its output is redirected; DISM writes in the OEM code page. Auto guesses
    # from the zero bytes of UTF-16 text, for a tool whose encoding is not known.
    $unicode = ($Encoding -eq 'Unicode')
    if ($Encoding -eq 'Auto') { $unicode = (@($Bytes | Where-Object { $_ -eq 0 }).Count * 4 -ge $Bytes.Length) }
    if ($unicode) {
        $text = [System.Text.Encoding]::Unicode.GetString($Bytes)
    } else {
        $text = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage).GetString($Bytes)
    }
    $lines = @($text.TrimStart([char]0xFEFF) -split '[\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    ($lines | Select-Object -Last 15) -join [Environment]::NewLine
}

function Invoke-TuneupHealthTool {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [ValidateSet('Auto', 'Unicode', 'Oem')][string]$Encoding = 'Auto'
    )
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
        [pscustomobject]@{ ExitCode = $process.ExitCode; Output = (ConvertFrom-TuneupToolOutput -Bytes $buffer.ToArray() -Encoding $Encoding) }
    } finally {
        $process.Dispose()
        $buffer.Dispose()
    }
}

# A 32-bit PowerShell on 64-bit Windows would be sent to the 32-bit sfc and DISM, which refuse to run.
function Get-TuneupSystemToolPath {
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem,
        [bool]$Is64BitProcess = [Environment]::Is64BitProcess
    )
    $folder = $(if ($Is64BitOperatingSystem -and -not $Is64BitProcess) { 'Sysnative' } else { 'System32' })
    Join-Path $env:SystemRoot "$folder\$Name"
}

function Invoke-TuneupSfc {
    Invoke-TuneupHealthTool -FilePath (Get-TuneupSystemToolPath -Name 'sfc.exe') -Arguments @('/scannow') -Encoding Unicode
}

function Invoke-TuneupDism {
    param([Parameter(Mandatory)][ValidateSet('ScanHealth', 'RestoreHealth')][string]$Operation)
    Invoke-TuneupHealthTool -FilePath (Get-TuneupSystemToolPath -Name 'Dism.exe') -Arguments @('/Online', '/Cleanup-Image', "/$Operation", '/English') -Encoding Oem
}

function Get-TuneupLogTime {
    # CBS.log has one-second resolution.
    $now = Get-Date
    $now.AddTicks(-($now.Ticks % [TimeSpan]::TicksPerSecond))
}

function Format-TuneupExitCodeHex {
    param([Parameter(Mandatory)][int]$ExitCode)
    '0x{0:x}' -f $ExitCode
}

function New-TuneupHealthScan {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)]$SfcRun,
        [Parameter(Mandatory)]$DismRun
    )
    $sfc = Get-TuneupSfcSummary -Lines $Lines
    $store = Get-TuneupComponentStoreSummary -Lines $Lines
    [pscustomobject]@{
        sfc               = [pscustomobject]@{
            exitCode        = $SfcRun.ExitCode
            exitCodeHex     = Format-TuneupExitCodeHex -ExitCode $SfcRun.ExitCode
            status          = $sfc.status
            repairedFiles   = $sfc.repairedFiles
            unrepairedFiles = $sfc.unrepairedFiles
            output          = $(if ($SfcRun.ExitCode) { $SfcRun.Output } else { $null })
        }
        componentStore    = [pscustomobject]@{
            exitCode        = $DismRun.ExitCode
            exitCodeHex     = Format-TuneupExitCodeHex -ExitCode $DismRun.ExitCode
            state           = $store.state
            operation       = $store.operation
            operationResult = $store.result
            detected        = $store.detected
            repaired        = $store.repaired
            output          = $(if ($DismRun.ExitCode) { $DismRun.Output } else { $null })
        }
        corruptComponents = @(Get-TuneupCorruptComponentGroup -Lines $Lines)
    }
}

# An unknown result is not repaired blindly: the logs have to be checked first.
function Test-TuneupHealthNeedsRepair {
    param([Parameter(Mandatory)]$Scan)
    ($Scan.componentStore.state -eq 'repairable') -or ($Scan.componentStore.state -eq 'unrepairable') -or ($Scan.sfc.status -eq 'unrepaired')
}

function Get-TuneupHealthRecommendation {
    param([Parameter(Mandatory)]$Scan, [switch]$RepairRan)
    $store = $Scan.componentStore.state
    $sfc = $Scan.sfc.status
    if ($store -eq 'unrepairable') { return 'manual-repair' }
    # Known damage comes before an unreadable result of the other tool.
    if ($store -eq 'repairable' -or $sfc -eq 'unrepaired') {
        if ($RepairRan) { return 'manual-repair' }
        return 'run-repair'
    }
    # SFC exit codes are not documented, so only DISM's decides; SFC's result comes from CBS.log.
    if ($store -eq 'unknown' -or $sfc -eq 'unknown' -or $Scan.componentStore.exitCode) { return 'check-logs' }
    'none'
}

function Invoke-TuneupHealth {
    param([switch]$Repair, [scriptblock]$OnPhase)
    $started = Get-TuneupLogTime
    if ($OnPhase) { & $OnPhase 'sfc' }
    $sfcRun = Invoke-TuneupSfc
    if ($OnPhase) { & $OnPhase 'dismScan' }
    $dismRun = Invoke-TuneupDism -Operation 'ScanHealth'
    $scanned = Get-TuneupLogTime
    $before = New-TuneupHealthScan -Lines @(Read-TuneupCbsLog -Since $started -Until $scanned) -SfcRun $sfcRun -DismRun $dismRun
    $after = $null
    if ($Repair -and (Test-TuneupHealthNeedsRepair -Scan $before)) {
        if ($OnPhase) { & $OnPhase 'dismRestore' }
        $restoreRun = Invoke-TuneupDism -Operation 'RestoreHealth'
        if ($OnPhase) { & $OnPhase 'sfcAgain' }
        $sfcAgain = Invoke-TuneupSfc
        $after = New-TuneupHealthScan -Lines @(Read-TuneupCbsLog -Since $scanned) -SfcRun $sfcAgain -DismRun $restoreRun
    }
    $final = $(if ($null -ne $after) { $after } else { $before })
    $repaired = @(@($before, $after) | Where-Object { $null -ne $_ -and ($_.sfc.status -eq 'repaired' -or $_.componentStore.state -eq 'repaired') })
    [pscustomobject]@{
        schemaVersion     = 1
        command           = 'health'
        startedAt         = $started.ToString('s')
        finishedAt        = (Get-Date).ToString('s')
        repairRequested   = [bool]$Repair
        repairRan         = ($null -ne $after)
        before            = $before
        after             = $after
        recommendation    = Get-TuneupHealthRecommendation -Scan $final -RepairRan:($null -ne $after)
        rebootRecommended = ($repaired.Count -gt 0)
    }
}

# 0: no problems left. 2: problems remain or the result could not be confirmed.
function Get-TuneupHealthExitCode {
    param([Parameter(Mandatory)]$Report)
    if ($Report.recommendation -eq 'none') { return 0 }
    2
}
