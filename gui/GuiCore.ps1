# The window of windows-tuneup without the window (design, section 17): what it asks the engine, how it reads
# what comes back, what it tells people about an error, and its log. Nothing here touches WPF, so it is tested
# with Pester. Every action is tuneup.ps1 of the same copy, run as a process of its own with -Json: the window
# never changes the system itself.

$script:GuiRoot = Split-Path $PSScriptRoot -Parent
$script:GuiUtf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:GuiLogEncoding = New-Object System.Text.UTF8Encoding -ArgumentList $true
$script:GuiStrings = @{}
$script:GuiLang = 'en'
$script:GuiLogFolder = $null
$script:GuiLogLines = New-Object System.Collections.Generic.List[object]
$script:GuiLogListener = $null
$script:GuiLogKeep = 30
# What an id given to the engine can hold: the ids of tweaks, runs, startup entries and clean rules, and
# result ids. Anything else never reaches a command line.
$script:GuiIdPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'

function Initialize-TuneupGuiText {
    param([string]$Lang)
    if (-not $Lang) { $Lang = $(if ((Get-UICulture).TwoLetterISOLanguageName -eq 'es') { 'es' } else { 'en' }) }
    if (@('es', 'en') -notcontains $Lang) { $Lang = 'en' }
    $file = Join-Path $script:GuiRoot "i18n\$Lang.json"
    $json = [System.IO.File]::ReadAllText($file, $script:GuiUtf8) | ConvertFrom-Json
    $script:GuiStrings = @{}
    foreach ($property in $json.PSObject.Properties) { $script:GuiStrings[$property.Name] = [string]$property.Value }
    $script:GuiLang = $Lang
}

function Get-TuneupGuiLang { $script:GuiLang }

# A text of the window in its language; the key itself when there is none, so a missing text shows up.
function Get-TuneupGuiText {
    param([Parameter(Mandatory)][string]$Key, [object[]]$Format = @())
    $text = $script:GuiStrings[$Key]
    if ($null -eq $text) { return $Key }
    if ($Format.Count) { return ($text -f $Format) }
    $text
}

# A count in a text: the key with .one for exactly one, when the language has it.
function Get-TuneupGuiCountText {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][int]$Count, [object[]]$Format = @())
    $chosen = $(if ($Count -eq 1 -and $script:GuiStrings.ContainsKey("$Key.one")) { "$Key.one" } else { $Key })
    Get-TuneupGuiText -Key $chosen -Format (@($Count) + @($Format))
}

function Test-TuneupGuiId {
    param([AllowEmptyString()][string]$Id)
    $Id -cmatch $script:GuiIdPattern
}

# The arguments of tuneup.ps1 for one action of the window. -Options names what the action takes; ids are
# checked so that nothing else reaches the command line. -Json and -Lang are always added.
function New-TuneupGuiArgument {
    param([Parameter(Mandatory)][string]$Action, [hashtable]$Options = @{})
    $ids = {
        param([string]$Name)
        $values = @($Options[$Name] | Where-Object { $_ })
        foreach ($value in $values) { if (-not (Test-TuneupGuiId -Id ([string]$value))) { throw "Not a valid id for -$Name`: $value" } }
        $values -join ','
    }
    $plan = $(if ($Options.PlanOnly) { '-WhatIf' } else { '-Yes' })
    $arguments = switch ($Action) {
        'list' { @('-List') }
        'suggest' { @('-Suggest') }
        'status' { @('-Status') }
        'reapply' {
            @('-Status', '-Reapply', $plan)
            if ($Options.Include) { '-Include'; & $ids 'Include' }
        }
        'apply' {
            $profiles = & $ids 'Profile'
            if (-not $profiles) { throw 'Applying needs at least one profile' }
            @('-Profile', $profiles)
            if ($Options.Include) { '-Include'; & $ids 'Include' }
            if ($Options.Exclude) { '-Exclude'; & $ids 'Exclude' }
            $plan
        }
        'undo' {
            $run = [string]$Options.Run
            if ($run -ne 'last' -and -not (Test-TuneupGuiId -Id $run)) { throw "Not a valid run: $run" }
            @('-Undo', $run)
            if ($Options.Tweak) { '-Tweak'; & $ids 'Tweak' }
        }
        'health' {
            '-Health'
            if ($Options.Repair) { '-Repair' }
        }
        'measure' {
            '-Measure'
            if ($Options.IdleSeconds) { '-IdleSeconds'; [string][int]$Options.IdleSeconds }
            if ($Options.Compare) { '-Compare'; & $ids 'Compare' }
        }
        'startup' { @('-Startup') }
        'startup-disable' { @('-Startup', '-Disable', (& $ids 'Disable'), $plan) }
        'clean' {
            '-Clean'
            if ($Options.Large) { '-Large' }
        }
        'clean-remove' { @('-Clean', '-Remove', (& $ids 'Remove'), $plan) }
        'read-result' { @('-ReadResult', (& $ids 'ResultId')) }
        default { throw "Unknown action $Action" }
    }
    $arguments = @($arguments)
    if ($Options.ResultId -and $Action -ne 'read-result') { $arguments += @('-ResultId', (& $ids 'ResultId')) }
    $arguments + @('-Json', '-Lang', $script:GuiLang)
}

# One command line for Windows: each argument quoted when it has a space (ids never do; the script path can).
function ConvertTo-TuneupGuiCommandLine {
    param([Parameter(Mandatory)][string[]]$Argument)
    (@($Argument) | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
}

function Get-TuneupGuiPowerShell {
    [System.IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell\v1.0\powershell.exe')
}

# Starts tuneup.ps1 with the arguments of an action. Without -Elevated: a hidden process whose output is
# read while it runs. With -Elevated: through UAC, hidden, with a result id, since its output cannot be read;
# the result is read afterwards with -ReadResult. A declined UAC prompt gives Declined, not an error.
function Start-TuneupGuiJob {
    param([Parameter(Mandatory)][string]$Action, [hashtable]$Options = @{}, [switch]$Elevated, [string]$Label)
    $options = @{} + $Options
    if ($Elevated) { $options.ResultId = [guid]::NewGuid().ToString() }
    $arguments = New-TuneupGuiArgument -Action $Action -Options $options
    $script = Join-Path $script:GuiRoot 'tuneup.ps1'
    $all = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script) + $arguments
    $job = [pscustomobject]@{
        Action    = $Action
        Label     = $(if ($Label) { $Label } else { $Action })
        Arguments = $arguments
        Elevated  = [bool]$Elevated
        ResultId  = $options.ResultId
        Process   = $null
        Output    = $null
        ErrorText = $null
        Started   = [datetime]::Now
        Declined  = $false
    }
    Write-TuneupGuiLog -Level INFO -Text ((Get-TuneupGuiText -Key 'gui.log.start' -Format $job.Label) + ' tuneup.ps1 ' + ($arguments -join ' '))
    if ($Elevated) {
        try {
            $job.Process = Start-Process -FilePath (Get-TuneupGuiPowerShell) -ArgumentList (ConvertTo-TuneupGuiCommandLine -Argument $all) -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
        } catch {
            # ERROR_CANCELLED: the person said no to the UAC prompt.
            $native = $_.Exception.InnerException
            if ($null -eq $native) { $native = $_.Exception }
            if ($native -is [System.ComponentModel.Win32Exception] -and $native.NativeErrorCode -eq 1223) {
                $job.Declined = $true
                Write-TuneupGuiLog -Level WARN -Text (Get-TuneupGuiText -Key 'gui.log.declined' -Format $job.Label)
                return $job
            }
            throw
        }
        return $job
    }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = Get-TuneupGuiPowerShell
    $info.Arguments = ConvertTo-TuneupGuiCommandLine -Argument $all
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.Encoding]::ASCII
    $info.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $job.Process = [System.Diagnostics.Process]::Start($info)
    # Read while it runs, so a long output never fills the pipe and stops the process.
    $job.Output = $job.Process.StandardOutput.ReadToEndAsync()
    $job.ErrorText = $job.Process.StandardError.ReadToEndAsync()
    $job
}

function Test-TuneupGuiJobDone {
    param([Parameter(Mandatory)]$Job)
    if ($Job.Declined) { return $true }
    $Job.Process.HasExited -and ($null -eq $Job.Output -or ($Job.Output.IsCompleted -and $Job.ErrorText.IsCompleted))
}

# Stops a job that only reads (the window never offers it for one that changes something).
function Stop-TuneupGuiJob {
    param([Parameter(Mandatory)]$Job)
    if ($Job.Process -and -not $Job.Process.HasExited) {
        try { $Job.Process.Kill() } catch [System.InvalidOperationException] { Write-Verbose 'The process had already ended' }
    }
    Write-TuneupGuiLog -Level WARN -Text (Get-TuneupGuiText -Key 'gui.log.cancelled' -Format $Job.Label)
}

# What a finished job gave: its exit code and its document, or why there is none. An elevated job gives
# NeedsRead: its document comes from -ReadResult, which the caller starts as another job.
function Complete-TuneupGuiJob {
    param([Parameter(Mandatory)]$Job)
    $result = [pscustomobject]@{ ExitCode = $null; Document = $null; Problem = $null; NeedsRead = $false; Declined = $Job.Declined; Seconds = [int]([datetime]::Now - $Job.Started).TotalSeconds }
    if ($Job.Declined) { return $result }
    $result.ExitCode = $Job.Process.ExitCode
    if ($Job.Elevated) {
        $result.NeedsRead = $true
        return $result
    }
    $text = [string]$Job.Output.Result
    $stderr = [string]$Job.ErrorText.Result
    try {
        $result.Document = ConvertFrom-TuneupGuiDocument -Text $text
    } catch {
        $result.Problem = $_.Exception.Message
        if ($stderr.Trim()) { $result.Problem += ' ' + $stderr.Trim() }
    }
    Write-TuneupGuiJobLog -Job $Job -Result $result
    $result
}

function ConvertFrom-TuneupGuiDocument {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw (Get-TuneupGuiText -Key 'gui.err.noOutput') }
    try {
        $document = $Text | ConvertFrom-Json
    } catch {
        throw (Get-TuneupGuiText -Key 'gui.err.notJson')
    }
    if ($null -eq $document -or -not $document.PSObject.Properties['command']) { throw (Get-TuneupGuiText -Key 'gui.err.notJson') }
    $document
}

# What the log keeps of a job: its exit code, how long it took, its warnings and its error.
function Write-TuneupGuiJobLog {
    param([Parameter(Mandatory)]$Job, [Parameter(Mandatory)]$Result)
    $document = $Result.Document
    if ($null -ne $document) {
        foreach ($warning in @($document.warnings | Where-Object { $_ })) { Write-TuneupGuiLog -Level WARN -Text $warning }
        if ($document.command -eq 'error') {
            $reason = $(if ($document.PSObject.Properties['reason'] -and $document.reason) { " ($($document.reason))" } else { '' })
            Write-TuneupGuiLog -Level ERROR -Text ("$($Job.Label): $($document.message)$reason")
            foreach ($detail in @($document.details | Where-Object { $_ })) { Write-TuneupGuiLog -Level ERROR -Text "  $detail" }
        }
    }
    if ($Result.Problem) { Write-TuneupGuiLog -Level ERROR -Text "$($Job.Label): $($Result.Problem)" }
    Write-TuneupGuiLog -Level INFO -Text (Get-TuneupGuiText -Key 'gui.log.end' -Format $Job.Label, $Result.ExitCode, $Result.Seconds)
}

# What people see of an error document: what happened (the message of the engine, already in the language
# of the window), the lines of details, and what the window offers to do, from the reason.
function Get-TuneupGuiErrorView {
    param([Parameter(Mandatory)]$Document)
    $reason = $(if ($Document.PSObject.Properties['reason']) { [string]$Document.reason } else { '' })
    $action = switch ($reason) {
        'needs-admin' { 'elevate' }
        'session-user' { 'unelevated' }
        { @('result-missing', 'result-incomplete', 'result-untrusted') -contains $_ } { 'log' }
        default { 'copy' }
    }
    [pscustomobject]@{
        Title   = Get-TuneupGuiText -Key $(if ($reason) { "gui.error.$reason" } else { 'gui.error.generic' })
        Message = [string]$Document.message
        Details = [string[]]@($Document.details | Where-Object { $_ })
        Reason  = $reason
        Action  = $action
    }
}

# The folder of the log of the window: %LOCALAPPDATA%\windows-tuneup\gui\logs, created when needed.
function Initialize-TuneupGuiLog {
    param([string]$Folder)
    if (-not $Folder) { $Folder = [System.IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'windows-tuneup\gui\logs') }
    if (-not [System.IO.Directory]::Exists($Folder)) { [void][System.IO.Directory]::CreateDirectory($Folder) }
    $script:GuiLogFolder = $Folder
    $script:GuiLogLines.Clear()
    # The newest files stay; the rest goes.
    $old = @(Get-ChildItem -LiteralPath $Folder -Filter 'gui-*.log' -File | Where-Object { $_.Name -match '^gui-\d{8}\.log$' } | Sort-Object Name -Descending | Select-Object -Skip $script:GuiLogKeep)
    foreach ($file in $old) {
        try { $file.Delete() } catch [System.IO.IOException], [System.UnauthorizedAccessException] { Write-Verbose "Could not remove the old log $($file.Name)" }
    }
    $Folder
}

function Get-TuneupGuiLogFolder { $script:GuiLogFolder }

# The profile folder in a text written to the log becomes %USERPROFILE%, so the log can be shared.
function Hide-TuneupGuiProfile {
    param([AllowEmptyString()][string]$Text)
    $profileFolder = [Environment]::GetFolderPath('UserProfile')
    if (-not $profileFolder) { return $Text }
    [regex]::Replace($Text, [regex]::Escape($profileFolder), '%USERPROFILE%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Write-TuneupGuiLog {
    param([Parameter(Mandatory)][ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $now = [datetime]::Now
    $clean = Hide-TuneupGuiProfile -Text ([regex]::Replace($Text, '\p{Cc}', ' '))
    $entry = [pscustomobject]@{ Time = $now.ToString('HH:mm:ss'); Level = $Level; Text = $clean }
    $script:GuiLogLines.Add($entry)
    if ($script:GuiLogFolder) {
        $file = Join-Path $script:GuiLogFolder ('gui-' + $now.ToString('yyyyMMdd') + '.log')
        try {
            # With a byte order mark, so Notepad and Windows PowerShell read the accents right.
            [System.IO.File]::AppendAllText($file, ('{0} {1,-5} {2}' -f $now.ToString('yyyy-MM-dd HH:mm:ss'), $Level, $clean) + [Environment]::NewLine, $script:GuiLogEncoding)
        } catch [System.IO.IOException], [System.UnauthorizedAccessException] {
            Write-Verbose "Could not write the log: $($_.Exception.Message)"
        }
    }
    # The window shows each line as it comes; nothing goes to the output of the caller.
    if ($null -ne $script:GuiLogListener) { & $script:GuiLogListener $entry }
}

# A script block that gets each new line of the log (the Registro section of the window), or $null.
function Set-TuneupGuiLogListener {
    param([scriptblock]$Listener)
    $script:GuiLogListener = $Listener
}

function Get-TuneupGuiLogLine { $script:GuiLogLines.ToArray() }

# A size for people, in the number format of the language: 1,4 GB, 350 MB, 12 KB.
function Format-TuneupGuiSize {
    param([long]$Bytes)
    $format = $(if ($script:GuiLang -eq 'es') { [System.Globalization.CultureInfo]::GetCultureInfo('es-ES') } else { [System.Globalization.CultureInfo]::InvariantCulture })
    if ($Bytes -ge 1GB) { return ([math]::Round($Bytes / 1GB, 1)).ToString('0.0', $format) + ' GB' }
    if ($Bytes -ge 1MB) { return ([math]::Round($Bytes / 1MB)).ToString('0', $format) + ' MB' }
    ([math]::Ceiling($Bytes / 1KB)).ToString('0', $format) + ' KB'
}

# A run id (yyyyMMdd-HHmmss) as a date for people; the id itself when it is not one.
function Format-TuneupGuiRunId {
    param([Parameter(Mandatory)][string]$Id)
    $culture = $(if ($script:GuiLang -eq 'es') { [System.Globalization.CultureInfo]::GetCultureInfo('es-ES') } else { [System.Globalization.CultureInfo]::GetCultureInfo('en-US') })
    $date = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Id.Substring(0, [math]::Min(15, $Id.Length)), 'yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$date)) { return $Id }
    $date.ToString('d MMM yyyy, HH:mm:ss', $culture)
}

# The settings of the window (language and theme), in %LOCALAPPDATA%\windows-tuneup\gui\settings.json.
function Get-TuneupGuiSettingsPath {
    [System.IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'windows-tuneup\gui\settings.json')
}

function Read-TuneupGuiSetting {
    param([string]$Path = (Get-TuneupGuiSettingsPath))
    $settings = [pscustomobject]@{ lang = $null; theme = 'system' }
    if (-not [System.IO.File]::Exists($Path)) { return $settings }
    try {
        $read = [System.IO.File]::ReadAllText($Path, $script:GuiUtf8) | ConvertFrom-Json
        if (@('es', 'en') -contains [string]$read.lang) { $settings.lang = [string]$read.lang }
        if (@('system', 'light', 'dark') -contains [string]$read.theme) { $settings.theme = [string]$read.theme }
    } catch {
        Write-Verbose "Settings not read: $($_.Exception.Message)"
    }
    $settings
}

function Save-TuneupGuiSetting {
    param([Parameter(Mandatory)]$Settings, [string]$Path = (Get-TuneupGuiSettingsPath))
    $folder = Split-Path $Path -Parent
    if (-not [System.IO.Directory]::Exists($folder)) { [void][System.IO.Directory]::CreateDirectory($folder) }
    [System.IO.File]::WriteAllText($Path, ($Settings | ConvertTo-Json), $script:GuiUtf8)
}

# Light or dark: the choice of the settings, or what Windows uses for apps.
function Get-TuneupGuiTheme {
    param([Parameter(Mandatory)][string]$Choice)
    if ($Choice -eq 'light' -or $Choice -eq 'dark') { return $Choice }
    try {
        $value = Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop
        if ($value -eq 0) { return 'dark' }
    } catch {
        Write-Verbose 'No theme setting of Windows; light'
    }
    'light'
}

function Test-TuneupGuiAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
