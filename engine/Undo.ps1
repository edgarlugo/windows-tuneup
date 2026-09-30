function Invoke-TuneupUndo {
    param([Parameter(Mandatory)]$Run, [string]$TweakId)
    Assert-TuneupRunUndoable -Run $Run
    $journal = Get-TuneupRunJournal -Run $Run
    $entries = @($journal.Entries)
    if ($TweakId) {
        $entries = @($entries | Where-Object { $_.id -eq $TweakId })
        if (-not $entries.Count) { throw (Get-TuneupText -Key 'err.tweakNotInRun' -Format $TweakId) }
    } else {
        $alreadyUndone = @(Get-TuneupUndoneTweakId -Run $Run)
        $entries = @($entries | Where-Object { $alreadyUndone -notcontains $_.id })
    }
    [array]::Reverse($entries)
    $results = @(foreach ($entry in $entries) {
        try {
            Restore-TuneupState -Tweak $entry.tweak -State $entry.state
            [pscustomobject]@{ id = $entry.id; title = Get-TuneupTitle -Tweak $entry.tweak; status = 'restored'; error = $null }
        } catch {
            [pscustomobject]@{ id = $entry.id; title = Get-TuneupTitle -Tweak $entry.tweak; status = 'failed'; error = $_.Exception.Message }
        }
    })
    # The values are already restored; an unrecorded undo would leave the run pending, so it is reported.
    # A run that still holds another user's entries stays pending for that user: only the tweaks
    # restored here are marked, never the whole run.
    $restoredIds = @($results | Where-Object { $_.status -eq 'restored' } | ForEach-Object { $_.id })
    try {
        if ($TweakId -or @($journal.Skipped).Count) {
            if ($restoredIds.Count) {
                Write-TuneupStateFile -Path (Join-Path $Run.Dir 'undone-tweaks.txt') -Root $Run.Root -Append `
                    -Text (($restoredIds -join [Environment]::NewLine) + [Environment]::NewLine)
            }
        } else {
            Save-TuneupJson -Path (Join-Path $Run.Dir 'undone.json') -Root $Run.Root `
                -Object ([pscustomobject]@{ undoneAt = (Get-Date).ToString('s'); results = $results })
        }
    } catch {
        $results += [pscustomobject]@{ id = $null; title = "run $($Run.Id)"; status = 'failed'; error = "The undo could not be recorded: $($_.Exception.Message)" }
    }
    $results
}

function Get-TuneupStatus {
    param([string]$StateRoot)
    $latest = [ordered]@{}
    foreach ($run in @(Get-TuneupRunList -StateRoot $StateRoot)) {
        if ($run.Undone) { continue }
        $undoneIds = @(Get-TuneupUndoneTweakId -Run $run)
        $touchedIds = $null
        $result = Read-TuneupTrustedJson -Path (Join-Path $run.Dir 'result.json') -Root $run.Root
        if ($null -ne $result) {
            $touchedIds = @($result.results | Where-Object { $_.status -eq 'applied' -or $_.status -eq 'not-applied' } | ForEach-Object { $_.id })
        }
        foreach ($entry in @(Read-TuneupRunJournal -Run $run)) {
            if ($undoneIds -contains $entry.id) { continue }
            if ($null -ne $touchedIds -and $touchedIds -notcontains $entry.id) { continue }
            $latest[[string]$entry.id] = [pscustomobject]@{ tweak = $entry.tweak; runId = $run.Id }
        }
    }
    foreach ($id in @($latest.Keys)) {
        $item = $latest[$id]
        try {
            $state = Test-TuneupState -Tweak $item.tweak
            $status = switch ($state) { 'applied' { 'ok' } 'not-applied' { 'drift' } default { 'not-present' } }
        } catch {
            $status = 'unknown'
        }
        [pscustomobject]@{ id = $id; title = Get-TuneupTitle -Tweak $item.tweak; status = $status; runId = $item.runId }
    }
}
