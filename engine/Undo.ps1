function Invoke-TuneupUndo {
    param([Parameter(Mandatory)]$Run, [string]$TweakId)
    Assert-TuneupRunUndoable -Run $Run
    # A run object built before the undo carries no Undone flag, so the marker itself decides.
    if ($Run.Undone -or (Test-TuneupRunMarker -Dir $Run.Dir -Name 'undone.json' -Root $Run.Root)) {
        throw (Get-TuneupText -Key 'err.runAlreadyUndone' -Format $Run.Id)
    }
    # With -TweakId the run is read as usual: a tweak noted as undone answers already-undone.
    if (-not $TweakId -and (Test-TuneupRunAllNotedUndone -Run $Run)) {
        throw (Get-TuneupText -Key 'err.runAlreadyUndone' -Format $Run.Id)
    }
    $journal = Get-TuneupRunJournal -Run $Run
    $alreadyUndone = @(Get-TuneupUndoneTweakId -Run $Run)
    $entries = @($journal.Entries)
    # Entries of another user are reported as skipped: they stay pending for their owner.
    $foreign = @($journal.SkippedEntries)
    $newResult = {
        param($entry, [string]$status, $reason, $errorText, $outcome)
        # A restored tweak that shows only after signing in again says so, like when it was applied. A
        # failed one carries what a person can run to restore it by hand.
        $signOut = $entry.tweak.PSObject.Properties['signOutRequired']
        [pscustomobject]@{
            id              = $entry.id
            title           = Get-TuneupTitle -Tweak $entry.tweak
            status          = $status
            reason          = $reason
            error           = $errorText
            detail          = $(if ($outcome) { $outcome.detail } else { $null })
            rebootRequired  = $(if ($outcome) { [bool]$outcome.rebootRequired } else { $false })
            signOutRequired = ($status -eq 'restored' -and $null -ne $signOut -and $signOut.Value -eq $true)
            manual          = [string[]]@(if ($status -eq 'failed') { Get-TuneupManualRestoreHint -Tweak $entry.tweak -State $entry.state })
        }
    }
    if ($TweakId) {
        $entries = @($entries | Where-Object { $_.id -eq $TweakId })
        $foreign = @($foreign | Where-Object { $_.id -eq $TweakId })
        if (-not $entries.Count -and -not $foreign.Count) { throw (Get-TuneupText -Key 'err.tweakNotInRun' -Format $TweakId) }
        if ($alreadyUndone -contains $TweakId) {
            # Restoring again would overwrite whatever the tweak holds now with a stale value.
            return (& $newResult (@($entries) + @($foreign))[0] 'skipped' 'already-undone' $null $null)
        }
        if (-not $entries.Count) { return (& $newResult $foreign[0] 'skipped' 'other-user' $null $null) }
    } else {
        $entries = @($entries | Where-Object { $alreadyUndone -notcontains $_.id })
        $foreign = @($foreign | Where-Object { $alreadyUndone -notcontains $_.id })
    }
    [array]::Reverse($entries)
    [array]::Reverse($foreign)
    $results = @(foreach ($entry in $entries) {
        try {
            # A restore can add a note (for example, reinstalled from the Store) and ask for a restart.
            $outcome = Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $entry.tweak -State $entry.state)
            & $newResult $entry 'restored' $outcome.reason $null $outcome
        } catch {
            & $newResult $entry 'failed' $null $_.Exception.Message $null
        }
    })
    $results += @(foreach ($entry in $foreign) { & $newResult $entry 'skipped' 'other-user' $null $null })
    # The values are already restored; an unrecorded undo would leave the run pending, so it is reported.
    # The whole run is marked only when every one of its tweaks is restored. Anything left (a failed
    # restore, or entries of another user) keeps the run pending, and only the tweaks restored here are
    # noted, so a retry or the other user picks up the rest.
    $restoredIds = @($results | Where-Object { $_.status -eq 'restored' } | ForEach-Object { $_.id })
    $doneIds = @($alreadyUndone) + $restoredIds
    $runIds = @(@($journal.Entries | ForEach-Object { $_.id }) + @($journal.Skipped))
    $pendingIds = @($runIds | Where-Object { $doneIds -notcontains $_ })
    try {
        if ($pendingIds.Count -eq 0) {
            Save-TuneupJson -Path (Join-Path $Run.Dir 'undone.json') -Root $Run.Root `
                -Object ([pscustomobject]@{ undoneAt = (Get-Date).ToString('s'); results = $results })
        } elseif ($restoredIds.Count) {
            Write-TuneupStateFile -Path (Join-Path $Run.Dir 'undone-tweaks.txt') -Root $Run.Root -Append `
                -Text (($restoredIds -join [Environment]::NewLine) + [Environment]::NewLine)
        }
    } catch {
        $results += [pscustomobject]@{ id = $null; title = "run $($Run.Id)"; status = 'failed'; reason = $null; error = "The undo could not be recorded: $($_.Exception.Message)"; detail = $null; rebootRequired = $false; signOutRequired = $false; manual = [string[]]@() }
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
            $touchedIds = @($result.results | Where-Object { $_.status -eq 'applied' -or $_.status -eq 'partial' -or $_.status -eq 'not-applied' } | ForEach-Object { $_.id })
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
            if ((Test-TuneupHandlerReadNeedsAdmin -Tweak $item.tweak) -and -not (Test-TuneupAdmin)) {
                $status = 'needs-admin'
            } else {
                $state = Test-TuneupState -Tweak $item.tweak
                $status = switch ($state) { 'applied' { 'ok' } 'not-applied' { 'drift' } default { 'not-present' } }
            }
        } catch {
            $status = 'unknown'
        }
        [pscustomobject]@{ id = $id; title = Get-TuneupTitle -Tweak $item.tweak; status = $status; runId = $item.runId }
    }
}
