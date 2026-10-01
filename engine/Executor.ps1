function New-TuneupResult {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$Status,
        [string]$Reason,
        [string]$ErrorText,
        [string]$Detail,
        [switch]$RebootRequired,
        [switch]$Refused
    )
    # signOutRequired is optional in the catalog: the change shows once the user signs in again.
    # A tweak that was skipped or refused changed nothing, so it asks for neither a restart nor a sign-out.
    $signOut = $Item.Tweak.PSObject.Properties['signOutRequired']
    $changed = ($Status -ne 'skipped')
    [pscustomobject]@{
        id              = $Item.Id
        title           = Get-TuneupTitle -Tweak $Item.Tweak
        status          = $Status
        reason          = $(if ($Reason) { $Reason } else { $null })
        error           = $(if ($ErrorText) { $ErrorText } else { $null })
        detail          = $(if ($Detail) { $Detail } else { $null })
        rebootRequired  = ($changed -and ([bool]$Item.Tweak.rebootRequired -or [bool]$RebootRequired))
        signOutRequired = ($changed -and $null -ne $signOut -and $signOut.Value -eq $true)
        refused         = [bool]$Refused
    }
}

# A refused tweak changed nothing, so it is noted with the tweaks already undone. If the note cannot
# be written, an undo calls its restore, which leaves it as it is (handlers that can refuse restore
# only what differs from the saved state).
function Add-TuneupRefusedMark {
    param([Parameter(Mandatory)][string]$RunDir, [Parameter(Mandatory)]$Tweak)
    try {
        Write-TuneupStateFile -Path (Join-Path $RunDir 'undone-tweaks.txt') -Append -Text ([string]$Tweak.id + [Environment]::NewLine)
    } catch {
        Write-Warning "Tweak $($Tweak.id) changed nothing, but that could not be noted for -Undo: $($_.Exception.Message)"
    }
}

# True when the tweak's state now is the one that was journaled before Set. A state that cannot be
# read again counts as changed: a refusal is only believed when it can be checked.
function Test-TuneupStateUnchanged {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)][AllowNull()]$Before)
    try {
        $after = Get-TuneupState -Tweak $Tweak
    } catch {
        return $false
    }
    (ConvertTo-Json -InputObject $Before -Depth 10 -Compress) -ceq (ConvertTo-Json -InputObject $after -Depth 10 -Compress)
}

function Invoke-TuneupPlan {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory)][string]$RunDir
    )
    $journal = Join-Path $RunDir 'snapshot.jsonl'
    $journalError = $null
    foreach ($item in $Plan) {
        if ($item.Action -ne 'apply') {
            New-TuneupResult -Item $item -Status 'skipped' -Reason $item.Reason
            continue
        }
        if ($journalError) {
            New-TuneupResult -Item $item -Status 'skipped' -Reason 'journal-error' -ErrorText $journalError
            continue
        }
        $tweak = $item.Tweak
        try {
            $state = Get-TuneupState -Tweak $tweak
        } catch {
            New-TuneupResult -Item $item -Status 'failed' -ErrorText $_.Exception.Message
            continue
        }
        try {
            Add-TuneupJournalEntry -Path $journal -Tweak $tweak -State $state
        } catch {
            $journalError = $_.Exception.Message
            New-TuneupResult -Item $item -Status 'skipped' -Reason 'journal-error' -ErrorText $journalError
            continue
        }
        try {
            # Set may report through New-TuneupOutcome that it changed something but could not finish
            # (partial) or that Windows asked for a restart; any other output is ignored.
            $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $tweak)
            if ($outcome.refused) {
                # A refusal is only believed when nothing changed: the state is read again and compared
                # with the one that was journaled. If it differs, the tweak is not noted as needing no
                # undo (-Undo can still restore it) and the run reports a failure.
                if (Test-TuneupStateUnchanged -Tweak $tweak -Before $state) {
                    # Its journal entry stays (it was written first), and the tweak is noted as needing
                    # no undo, so -Undo never calls its restore.
                    Add-TuneupRefusedMark -RunDir $RunDir -Tweak $tweak
                    New-TuneupResult -Item $item -Status 'skipped' -Reason $outcome.reason -Detail $outcome.detail -Refused
                } else {
                    New-TuneupResult -Item $item -Status 'failed' -ErrorText 'refused after changing; undo can restore it' -Detail $outcome.detail
                }
                continue
            }
            if ($outcome.partial) {
                $status = 'partial'
            } elseif ((Test-TuneupState -Tweak $tweak) -eq 'applied') {
                $status = 'applied'
            } else {
                $status = 'not-applied'
            }
            New-TuneupResult -Item $item -Status $status -Reason $outcome.reason -Detail $outcome.detail -RebootRequired:$outcome.rebootRequired
        } catch {
            New-TuneupResult -Item $item -Status 'failed' -ErrorText $_.Exception.Message
        }
    }
}
