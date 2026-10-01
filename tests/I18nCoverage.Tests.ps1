BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:I18nRoot = Join-Path $Repo 'i18n'
    $script:Strings = @{}
    foreach ($lang in 'es', 'en') {
        $json = Get-Content -LiteralPath (Join-Path $I18nRoot "$lang.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:Strings[$lang] = @($json.PSObject.Properties.Name)
    }
    # The first part of every key that has one (err, plan, health, ...): a quoted literal that starts
    # with one of them and a dot is read as a text key.
    $script:Namespaces = @($Strings['en'] | Where-Object { $_.Contains('.') } | ForEach-Object { $_.Split('.')[0] } | Sort-Object -Unique)

    # Every text key that the code of the engine can ask for through a literal: the keys it names, and
    # the keys that its reason and status values stand for (the reports look them up as reason.<value>,
    # status.<value>, and so on). A value that the code starts to emit without a text in each language
    # fails here instead of printing its raw key to a person.
    function Get-EmittedI18nKey {
        param([Parameter(Mandatory)][string]$Path)
        $name = Split-Path $Path -Leaf
        # Lines end in LF whatever the checkout used, so that $ in a pattern means the end of a line.
        $text = (Get-Content -LiteralPath $Path -Raw -Encoding UTF8) -replace "`r`n", "`n"
        # Lowercase kebab words only: 'Running' or 'Stop' are values of the system, not ours.
        $word = "'((?-i:[a-z][a-z0-9-]*))'"
        $found = New-Object System.Collections.Generic.List[object]
        $add = {
            param([string]$Kind, [string]$Key)
            $found.Add([pscustomobject]@{ File = $name; Kind = $Kind; Key = $Key })
        }
        $collect = {
            param([string]$Kind, [string]$Prefix, [string]$Pattern, [string]$Options = 'IgnoreCase, Multiline')
            foreach ($match in [regex]::Matches($text, $Pattern, $Options)) { & $add $Kind "$Prefix$($match.Groups[1].Value)" }
        }
        # Literals between braces on the lines that assign from an if/else or a switch.
        $braced = {
            param([string]$Kind, [string]$Prefix, [string]$LinePattern)
            foreach ($line in [regex]::Matches($text, $LinePattern, 'IgnoreCase, Multiline')) {
                foreach ($match in [regex]::Matches($line.Value, "\{\s*$word\s*\}")) { & $add $Kind "$Prefix$($match.Groups[1].Value)" }
            }
        }

        # Reasons (a plan item, a result, a measurement note).
        $reasonPrefix = $(if ($name -eq 'Measure.ps1') { 'measure.reason.' } else { 'reason.' })
        & $collect 'reason' $reasonPrefix "-Reason\s+$word"
        & $collect 'reason' $reasonPrefix "\b(?:reason|note)\s*=\s*$word"
        & $collect 'reason' $reasonPrefix "\b(?:reason|note)\s+-c?(?:eq|ne)\s+$word"
        & $braced 'reason' $reasonPrefix '^[^\r\n]*\$reason\s*=\s*\$\(if[^\r\n]*$'
        # An undo result is built with positional arguments: status, then reason.
        & $collect 'status' 'status.' "\`$newResult\b[^\r\n]*?$word\s+(?:'|\`$)"
        & $collect 'reason' $reasonPrefix "\`$newResult\b[^\r\n]*?'[a-z-]+'\s+$word"

        # Statuses of a result, a status line and an item of -Status.
        if ($name -ne 'Health.ps1') {
            & $collect 'status' 'status.' "-Status\s+$word"
            & $collect 'status' 'status.' "\bstatus\s*=\s*$word"
            & $collect 'status' 'status.' "(?<!sfc)\.status\s+-c?(?:eq|ne)\s+$word"
            & $braced 'status' 'status.' '^[^\r\n]*\$status\s*=\s*switch[^\r\n]*$'
        }

        # The tool results of -Health, restore points and the phases that -Health announces.
        if ($name -eq 'Health.ps1') {
            & $collect 'health sfc' 'health.sfc.' "\bstatus\s*=\s*$word"
            & $collect 'health store' 'health.store.' "\bstate\s*=\s*$word"
            & $collect 'health recommendation' 'health.recommendation.' "\breturn\s+$word"
            & $collect 'health recommendation' 'health.recommendation.' "^\s+$word\s*$"
            & $collect 'health phase' 'health.phase.' "\`$OnPhase\s+'([A-Za-z]+)'"
        }
        if ($name -eq 'RestorePoint.ps1') {
            & $collect 'restore point' 'restore.' "(?:\breturn\s+|\{\s*)$word"
        }

        # Keys named in the code: -Key '...' (a count key also needs its singular), and any literal of a known namespace.
        & $collect 'key' '' "-Key\s+'([^']+)'"
        foreach ($match in [regex]::Matches($text, "Get-TuneupCountKey\s+-Key\s+'([^']+)'")) { & $add 'key' "$($match.Groups[1].Value).one" }
        $namespaced = "'((?:$($Namespaces -join '|'))\.[A-Za-z0-9._-]+)'"
        foreach ($line in [regex]::Matches($text, '^[^\r\n]*$', 'Multiline')) {
            $isCount = $line.Value.Contains('Get-TuneupCountKey')
            foreach ($match in [regex]::Matches($line.Value, $namespaced)) {
                # A file name such as run.json starts like a key but is not one.
                if ($match.Groups[1].Value -match '\.jsonl?$') { continue }
                & $add 'key' $match.Groups[1].Value
                if ($isCount) { & $add 'key' "$($match.Groups[1].Value).one" }
            }
        }
        $found.ToArray()
    }

    function Get-MissingI18nKey {
        param([Parameter(Mandatory)][object[]]$Found)
        foreach ($item in $Found) {
            foreach ($lang in 'es', 'en') {
                if ($Strings[$lang] -cnotcontains $item.Key) { "$($item.File): $($item.Kind) '$($item.Key)' has no text in $lang" }
            }
        }
    }

    $script:Files = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'engine') -Filter '*.ps1' -File) +
        @(Get-ChildItem -LiteralPath (Join-Path $Repo 'engine\handlers') -Filter '*.ps1' -File)
    # Action scripts report their own reasons (a refusal, a reinstall), which the reports look up too.
    $actionsFolder = Join-Path $Repo 'actions'
    if (Test-Path -LiteralPath $actionsFolder) { $script:Files += @(Get-ChildItem -LiteralPath $actionsFolder -Filter '*.ps1' -File) }
    $script:AllFound = @($Files | ForEach-Object { Get-EmittedI18nKey -Path $_.FullName })
}

Describe 'i18n coverage of what the engine emits' {
    It 'has a text in es and en for every key, reason and status that the engine code names' {
        @(Get-MissingI18nKey -Found $AllFound | Sort-Object -Unique) -join "`n" | Should -BeNullOrEmpty
    }

    It 'has a text for every metric and every risk' {
        $metrics = @(& (Get-Module Tuneup) { Get-TuneupMetricName })
        $risks = @(& (Get-Module Tuneup) { $script:TweakRisks })
        $keys = @($metrics | ForEach-Object { [pscustomobject]@{ File = 'Measure.ps1'; Kind = 'metric'; Key = "metric.$_" } }) +
            @($risks | ForEach-Object { [pscustomobject]@{ File = 'Catalog.ps1'; Kind = 'risk'; Key = "risk.$_" } })
        $metrics.Count | Should -BeGreaterThan 5
        $risks.Count | Should -Be 3
        @(Get-MissingI18nKey -Found $keys) -join "`n" | Should -BeNullOrEmpty
    }

    It 'finds the values it is meant to check, so it cannot go blind' {
        $keys = @($AllFound | ForEach-Object { $_.Key })
        foreach ($expected in 'reason.already-applied', 'reason.journal-error', 'reason.other-user', 'reason.already-undone', 'reason.reinstalled',
            'reason.installed-for-other-users', 'reason.unverified-needs-admin', 'measure.reason.needs-admin', 'measure.reason.not-recorded-yet',
            'status.applied', 'status.partial', 'status.restored', 'status.drift', 'status.needs-admin', 'status.unknown',
            'health.sfc.unrepaired', 'health.store.repairable', 'health.phase.dismRestore', 'health.recommendation.check-logs',
            'restore.skipped-recent', 'health.group.one', 'plan.header', 'err.runAlreadyUndone') {
            $keys | Should -Contain $expected
        }
        $AllFound.Count | Should -BeGreaterThan 60
    }

    It 'reports a reason, a status and a key that have no text' {
        $dir = Join-Path $TestDrive 'scan'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $path = Join-Path $dir 'Sample.ps1'
        [System.IO.File]::WriteAllText($path, @'
New-TuneupResult -Item $item -Status 'melted' -Reason 'no-such-reason'
$status = 'half-done'
$reason = $(if ($x) { 'left-over' } else { 'already-applied' })
Write-Host (Get-TuneupText -Key 'no.such.key')
'@)
        $missing = @(Get-MissingI18nKey -Found @(Get-EmittedI18nKey -Path $path))
        $missing -join "`n" | Should -BeLike "*status 'status.melted'*"
        $missing -join "`n" | Should -BeLike "*reason 'reason.no-such-reason'*"
        $missing -join "`n" | Should -BeLike "*status 'status.half-done'*"
        $missing -join "`n" | Should -BeLike "*reason 'reason.left-over'*"
        $missing -join "`n" | Should -BeLike "*key 'no.such.key'*"
        $missing -join "`n" | Should -Not -BeLike "*'reason.already-applied'*"
    }
}
