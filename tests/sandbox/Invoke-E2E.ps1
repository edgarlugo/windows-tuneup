<#
.SYNOPSIS
    End-to-end test of every profile, inside Windows Sandbox (design, section 6, layer 5).
.DESCRIPTION
    Runs as the logon command of tests/sandbox/e2e.wsb, elevated, with the repository mapped read-only.
    It uses the real state folders of the sandbox (no -StateRoot), so the hardened folder is tested
    too. For each profile: snapshot, apply with -Yes (the tweaks that ask first are asked for by
    name), -Status (all in place), apply again (nothing left to apply), -Undo last, snapshot again and
    compare: no difference may remain. When a profile fails, or its second apply changed something,
    every run that -Undo last still finds is undone before the next profile, so it starts clean (the
    report says what was undone, and which run could not be). Then a re-apply check: a tweak of base is put back as it was,
    -Status shows the drift, -Status -Reapply applies it again, and two undos leave no difference.
    Store apps and OneDrive are left out: the sandbox has no Store and no winget, so their undo cannot
    run here (docs/es/vm-checklist.md covers them in a virtual machine). Writes e2e-report.json and
    e2e-report.md to -Output, then shuts the sandbox down unless -KeepOpen.
#>
param(
    [string]$Repo = 'C:\windows-tuneup',
    [string]$Output = 'C:\e2e-out',
    [string[]]$Profiles = @('base', 'dev', 'gaming', 'privacy', 'laptop', 'legacy', 'work', 'lite'),
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$Profiles = @($Profiles -split ',' | Where-Object { $_ })
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$tuneup = Join-Path $Repo 'tuneup.ps1'
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$log = Join-Path $Output 'e2e.log'
function Write-E2ELog([string]$Text) { Add-Content -LiteralPath $log -Value "$((Get-Date).ToString('s')) $Text" -Encoding UTF8 }

# One command of the tool, with -Json: its exit code and its document.
function Invoke-E2ETuneup([string[]]$Arguments) {
    Write-E2ELog "tuneup.ps1 $($Arguments -join ' ')"
    $text = & $powershell -NoProfile -ExecutionPolicy Bypass -File $tuneup -Lang en -Json @Arguments | Out-String
    $code = $LASTEXITCODE
    $document = $null
    try { $document = $text | ConvertFrom-Json } catch { Write-E2ELog "not JSON: $text" }
    [pscustomobject]@{ ExitCode = $code; Document = $document }
}

# Undoes, newest first, every run that -Undo last still finds, so the next profile starts from the
# state of the sandbox and not from what a failed profile (or a second apply that changed something)
# left behind. Stops at a run that an undo does not take off the list (it could not restore all of
# it): gives the undos made and that run, if any.
function Invoke-E2ECleanup {
    $undone = @()
    $maxUndos = 20
    for ($i = 0; $i -lt $maxUndos; $i++) {
        $run = Resolve-TuneupRun -RunId 'last'
        if (-not $run) { break }
        $undo = Invoke-E2ETuneup @('-Undo', $run.Id)
        $undone += "$($run.Id): exit $($undo.ExitCode)"
        $next = Resolve-TuneupRun -RunId 'last'
        if ($next -and $next.Id -eq $run.Id) {
            return [pscustomobject]@{ undone = $undone; left = $run.Id }
        }
    }
    $left = Resolve-TuneupRun -RunId 'last'
    [pscustomobject]@{ undone = $undone; left = $(if ($left) { $left.Id } else { $null }) }
}

function Get-E2EProblem($Result) {
    @($Result.Document.results | Where-Object { $_.status -in 'failed', 'partial', 'not-applied' } |
        ForEach-Object { "$($_.id): $($_.status) $($_.error) $($_.detail)".Trim() })
}

$report = [ordered]@{ startedAt = (Get-Date).ToString('s'); passed = $false; error = $null; environment = $null; systemRestore = $null; profiles = @(); reapply = $null }
try {
    Import-Module (Join-Path $Repo 'engine\Tuneup.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'E2E.psm1') -Force
    Initialize-TuneupI18n -Root (Join-Path $Repo 'i18n') -Lang en
    $environment = Get-TuneupEnvironment
    $report.environment = ConvertTo-TuneupEnvironmentView -Environment $environment
    if (-not $environment.IsAdmin) { throw 'The logon command of the sandbox is not elevated.' }
    $report.systemRestore = Get-TuneupSystemRestoreState
    $catalog = @(Import-TuneupCatalog -Path (Join-Path $Repo 'catalog'))
    $profileSet = @(Import-TuneupProfileSet -Path (Join-Path $Repo 'profiles'))
    $left = @($catalog | Where-Object { $_.type -eq 'appx' -or ($_.type -eq 'action' -and $_.set.script -eq 'onedrive') } | ForEach-Object { [string]$_.id })
    $initial = Get-E2ESnapshot -Catalog $catalog -SkipTypes @('appx')
    $initial | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Output 'snapshot-initial.json') -Encoding UTF8

    foreach ($profileId in $Profiles) {
        Write-E2ELog "profile $profileId"
        $profileData = $profileSet | Where-Object { $_.id -eq $profileId }
        $base = $profileSet | Where-Object { $_.id -eq 'base' }
        $ask = @(@($base.include) + @($profileData.include) | Where-Object { $_ } | Sort-Object -Unique |
            Where-Object { $id = $_; $tweak = $catalog | Where-Object { $_.id -eq $id }; $tweak.ask -and $left -notcontains $id })
        $arguments = @('-Profile', $profileId, '-Yes')
        if ($left.Count) { $arguments += @('-Exclude', ($left -join ',')) }
        if ($ask.Count) { $arguments += @('-Include', ($ask -join ',')) }
        $apply = Invoke-E2ETuneup $arguments
        $status = Invoke-E2ETuneup @('-Status')
        $again = Invoke-E2ETuneup $arguments
        $undo = Invoke-E2ETuneup @('-Undo', 'last')
        $after = Get-E2ESnapshot -Catalog $catalog -SkipTypes @('appx')
        $differences = @(Compare-E2ESnapshot -Before $initial -After $after)
        $entry = [ordered]@{
            profile        = $profileId
            applyExitCode  = $apply.ExitCode
            applied        = $apply.Document.summary.applied
            refused        = @($apply.Document.results | Where-Object { $_.refused } | ForEach-Object { "$($_.id): $($_.reason)" })
            problems       = @(Get-E2EProblem $apply)
            notInPlace     = @($status.Document.items | Where-Object { $_.status -ne 'ok' } | ForEach-Object { "$($_.id): $($_.status)" })
            secondApply    = $(if ($again.Document.command -eq 'plan') { $again.Document.summary.apply } else { "ran again: $($again.Document.command)" })
            undoExitCode   = $undo.ExitCode
            undoProblems   = @($undo.Document.results | Where-Object { $_.status -eq 'failed' } | ForEach-Object { "$($_.id): $($_.error)" })
            differences    = @($differences | Where-Object { -not $_.volatile })
            volatile       = @($differences | Where-Object { $_.volatile })
        }
        $entry.passed = ($apply.ExitCode -eq 0 -and $entry.notInPlace.Count -eq 0 -and $entry.secondApply -eq 0 -and
            $undo.ExitCode -eq 0 -and $entry.differences.Count -eq 0)
        # A second apply that changed something left two runs and -Undo last only undid one of them.
        $entry.cleanup = $null
        if (-not $entry.passed -or $again.Document.command -eq 'apply') {
            Write-E2ELog "cleanup after $profileId"
            $entry.cleanup = Invoke-E2ECleanup
        }
        $report.profiles += [pscustomobject]$entry
    }

    # Re-apply: one registry tweak of base put back as it was before, as if Windows had reverted it.
    Write-E2ELog 'reapply'
    Invoke-E2ETuneup @('-Profile', 'base', '-Yes') | Out-Null
    $run = Resolve-TuneupRun -RunId 'last'
    $entry = @(Read-TuneupRunJournal -Run $run | Where-Object { $_.tweak.type -eq 'registry' })[0]
    Restore-TuneupState -Tweak $entry.tweak -State $entry.state | Out-Null
    $drift = Invoke-E2ETuneup @('-Status')
    $reapply = Invoke-E2ETuneup @('-Status', '-Reapply', '-Yes')
    $statusAfter = Invoke-E2ETuneup @('-Status')
    $undoReapply = Invoke-E2ETuneup @('-Undo', 'last')
    $undoBase = Invoke-E2ETuneup @('-Undo', 'last')
    $differences = @(Compare-E2ESnapshot -Before $initial -After (Get-E2ESnapshot -Catalog $catalog -SkipTypes @('appx')))
    $report.reapply = [pscustomobject]@{
        tweak       = $entry.id
        drifted     = @($drift.Document.items | Where-Object { $_.status -eq 'drift' } | ForEach-Object { $_.id })
        reapplied   = @($reapply.Document.results | Where-Object { $_.status -eq 'applied' } | ForEach-Object { $_.id })
        notInPlace  = @($statusAfter.Document.items | Where-Object { $_.status -ne 'ok' } | ForEach-Object { $_.id })
        undoCodes   = @($undoReapply.ExitCode, $undoBase.ExitCode)
        differences = @($differences | Where-Object { -not $_.volatile })
    }
    $report.reapply | Add-Member -NotePropertyName passed -NotePropertyValue (
        (@($report.reapply.drifted) -join ',') -eq $entry.id -and (@($report.reapply.reapplied) -join ',') -eq $entry.id -and
        $report.reapply.notInPlace.Count -eq 0 -and (@($report.reapply.undoCodes) -join ',') -eq '0,0' -and $report.reapply.differences.Count -eq 0)
    $report.passed = (@($report.profiles | Where-Object { -not $_.passed }).Count -eq 0) -and $report.reapply.passed
} catch {
    $report.error = "$($_.Exception.Message) $($_.ScriptStackTrace)"
    Write-E2ELog "error: $($report.error)"
}
$report.finishedAt = (Get-Date).ToString('s')
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Output 'e2e-report.json') -Encoding UTF8

$lines = @("# windows-tuneup end-to-end ($(if ($report.passed) { 'PASS' } else { 'FAIL' }))", '',
    "Build $($report.environment.build).$($report.environment.ubr), $($report.environment.edition); System Restore: $($report.systemRestore)", '')
if ($report.error) { $lines += @("Error: $($report.error)", '') }
$lines += '| Profile | Result | Applied | Apply exit | Not in place | Second apply | Undo exit | Differences |'
$lines += '|---|---|---|---|---|---|---|---|'
foreach ($entry in $report.profiles) {
    $lines += "| $($entry.profile) | $(if ($entry.passed) { 'PASS' } else { 'FAIL' }) | $($entry.applied) | $($entry.applyExitCode) | $($entry.notInPlace.Count) | $($entry.secondApply) | $($entry.undoExitCode) | $($entry.differences.Count) |"
}
foreach ($entry in $report.profiles | Where-Object { -not $_.passed }) {
    $lines += @('', "## $($entry.profile)")
    foreach ($line in @($entry.problems) + @($entry.notInPlace) + @($entry.undoProblems)) { $lines += "- $line" }
    foreach ($difference in $entry.differences) { $lines += "- $($difference.kind) $($difference.name): $($difference.before) -> $($difference.after)" }
    if ($entry.cleanup) {
        $lines += "- cleanup: $(if (@($entry.cleanup.undone).Count) { @($entry.cleanup.undone) -join '; ' } else { 'nothing to undo' })"
        if ($entry.cleanup.left) { $lines += "- run $($entry.cleanup.left) could not be fully undone: the profiles after this one did not start clean" }
    }
}
if ($report.reapply) { $lines += @('', "Re-apply of $($report.reapply.tweak): $(if ($report.reapply.passed) { 'PASS' } else { 'FAIL' })") }
Set-Content -LiteralPath (Join-Path $Output 'e2e-report.md') -Value $lines -Encoding UTF8
Write-E2ELog 'done'
if (-not $KeepOpen) { & shutdown.exe /s /t 5 }
