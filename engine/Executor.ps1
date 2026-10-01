function New-TuneupResult {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$Status,
        [string]$Reason,
        [string]$ErrorText,
        [string]$Detail,
        [switch]$RebootRequired
    )
    [pscustomobject]@{
        id             = $Item.Id
        title          = Get-TuneupTitle -Tweak $Item.Tweak
        status         = $Status
        reason         = $(if ($Reason) { $Reason } else { $null })
        error          = $(if ($ErrorText) { $ErrorText } else { $null })
        detail         = $(if ($Detail) { $Detail } else { $null })
        rebootRequired = ([bool]$Item.Tweak.rebootRequired -or [bool]$RebootRequired)
    }
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
