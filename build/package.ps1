<#
.SYNOPSIS
    Builds the files of a release in -OutputPath.
.DESCRIPTION
    windows-tuneup-<version>.zip holds what runs (tuneup.ps1, engine, i18n, catalog, profiles,
    actions) and what people read (docs/es, docs/en, README.md, LICENSE) under one folder,
    windows-tuneup-<version>. In a git checkout only tracked files go in (git ls-files -z, read as
    UTF-8, so names with spaces or letters outside ASCII are not quoted). Entries are sorted and carry
    the date of the last commit, so the same commit gives the same zip on the same machine. The files
    are read from the working tree: with -Release (the release workflow) it must be a git checkout
    without changes that are not committed, so what goes in is the commit and nothing else.
    install.ps1 is the installer of the repository with the version and the SHA256 of the zip written
    in, SHA256SUMS lists both, and release-notes.md is build/release-notes.md with the version and the
    hashes filled in.
#>
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$Version,
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$root = Split-Path $PSScriptRoot -Parent
if (-not $Version) {
    Import-Module (Join-Path $root 'engine\Tuneup.psm1') -Force
    $Version = Get-TuneupVersion
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid version '$Version': expected major.minor.patch" }

# What goes in, as paths relative to the repository with forward slashes.
$patterns = @(
    '^tuneup\.ps1$', '^README\.md$', '^LICENSE$',
    '^engine/[^/]+\.(ps1|psm1)$', '^engine/handlers/[^/]+\.ps1$',
    '^i18n/[^/]+\.json$', '^catalog/[^/]+\.json$', '^profiles/[^/]+\.json$', '^actions/[^/]+\.ps1$',
    '^docs/(es|en)/[^/]+\.md$'
)
# git runs as a process of its own: its output is read as UTF-8 (PowerShell would decode it with the code
# page of the console) and what it writes on standard error outside a checkout is not an error here; its
# exit code decides. -z separates the names with NUL and leaves them unquoted.
function Invoke-PackageGit {
    param([Parameter(Mandatory)][string]$Git, [Parameter(Mandatory)][string[]]$Arguments)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Git
    $info.Arguments = $Arguments -join ' '
    $info.WorkingDirectory = $root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    $process = [System.Diagnostics.Process]::Start($info)
    $errors = $process.StandardError.ReadToEndAsync()
    $output = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    [void]$errors.Result
    [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
}
$inGit = $false
$tracked = @()
$git = @(Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if ($git) {
    $listed = Invoke-PackageGit -Git $git[0] -Arguments @('ls-files', '-z')
    $tracked = @($listed.Output.Split([char]0) | Where-Object { $_ })
    $inGit = ($listed.ExitCode -eq 0 -and $tracked.Count -gt 0)
}
if ($Release) {
    if (-not $inGit) { throw '-Release builds from a git checkout: this folder is not one (or git is not installed).' }
    $changes = Invoke-PackageGit -Git $git[0] -Arguments @('status', '--porcelain', '-z', '--untracked-files=no')
    if ($changes.ExitCode -ne 0) { throw "git status failed with exit code $($changes.ExitCode)" }
    if ($changes.Output) { throw "-Release builds what is committed: the checkout has changes that are not committed ($($changes.Output.Split([char]0)[0].Trim()))." }
}
if (-not $inGit) {
    $prefix = $root.TrimEnd('\') + '\'
    $tracked = @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { $_.FullName.Substring($prefix.Length).Replace('\', '/') })
}
$files = @($tracked | Where-Object { $path = $_; @($patterns | Where-Object { $path -cmatch $_ }).Count -gt 0 } | Sort-Object -CaseSensitive)
foreach ($required in 'tuneup.ps1', 'engine/Tuneup.psm1', 'LICENSE', 'README.md') {
    if ($files -notcontains $required) { throw "$required is missing from the package" }
}

$timestamp = [datetime]'2026-01-01T00:00:00'
if ($inGit) {
    $last = Invoke-PackageGit -Git $git[0] -Arguments @('log', '-1', '--format=%cI')
    if ($last.ExitCode -eq 0 -and $last.Output.Trim()) { $timestamp = ([datetimeoffset]::Parse($last.Output.Trim())).UtcDateTime }
}

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$OutputPath = (Resolve-Path -LiteralPath $OutputPath).ProviderPath
$top = "windows-tuneup-$Version"
$zipPath = Join-Path $OutputPath "$top.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$stream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
try {
    $archive = New-Object System.IO.Compression.ZipArchive -ArgumentList $stream, ([System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $entry = $archive.CreateEntry("$top/$file", [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $timestamp
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $root ($file.Replace('/', '\'))))
            $writer = $entry.Open()
            try { $writer.Write($bytes, 0, $bytes.Length) } finally { $writer.Dispose() }
        }
    } finally {
        $archive.Dispose()
    }
} finally {
    $stream.Dispose()
}
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

# The installer of this release knows its version and the SHA256 of its zip.
$installer = [System.IO.File]::ReadAllText((Join-Path $root 'install.ps1'))
foreach ($placeholder in "'__TUNEUP_VERSION__'", "'__TUNEUP_ZIP_SHA256__'") {
    if (-not $installer.Contains($placeholder)) { throw "install.ps1 has no $placeholder to fill in" }
}
$installer = $installer.Replace("'__TUNEUP_VERSION__'", "'$Version'").Replace("'__TUNEUP_ZIP_SHA256__'", "'$zipHash'")
$installerPath = Join-Path $OutputPath 'install.ps1'
[System.IO.File]::WriteAllText($installerPath, $installer, (New-Object System.Text.UTF8Encoding -ArgumentList $false))
$installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()

# The format of sha256sum: the hash, two spaces and the name; one line each, LF.
$sumsPath = Join-Path $OutputPath 'SHA256SUMS'
[System.IO.File]::WriteAllText($sumsPath, "$zipHash  $top.zip`n$installerHash  install.ps1`n", (New-Object System.Text.UTF8Encoding -ArgumentList $false))

$notes = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'release-notes.md'), [System.Text.Encoding]::UTF8)
$notes = $notes.Replace('{{VERSION}}', $Version).Replace('{{ZIP_SHA256}}', $zipHash).Replace('{{INSTALLER_SHA256}}', $installerHash)
$notesPath = Join-Path $OutputPath 'release-notes.md'
[System.IO.File]::WriteAllText($notesPath, $notes, (New-Object System.Text.UTF8Encoding -ArgumentList $false))

[pscustomobject]@{
    Version         = $Version
    Zip             = $zipPath
    ZipSha256       = $zipHash
    Installer       = $installerPath
    InstallerSha256 = $installerHash
    Sums            = $sumsPath
    Notes           = $notesPath
    Files           = $files.Count
}
