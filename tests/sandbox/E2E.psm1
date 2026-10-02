# Helpers of the end-to-end test in Windows Sandbox (Invoke-E2E.ps1 runs inside it, Start-E2E.ps1 on the
# host). They need the engine module loaded first: tweak states are read with the same handlers as the
# tool.
$ErrorActionPreference = 'Stop'

# What windows-tuneup can touch, read before and after: the state of every catalog tweak (minus the
# types left out), the start type of every service, whether every scheduled task is enabled, and the
# Store apps of all users. -Parts limits what is read (the host tests read only tweaks).
function Get-E2ESnapshot {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Catalog,
        [string[]]$SkipTypes = @(),
        [ValidateSet('Tweaks', 'Services', 'Tasks', 'Apps')][string[]]$Parts = @('Tweaks', 'Services', 'Tasks', 'Apps')
    )
    $tweaks = [ordered]@{}
    if ($Parts -contains 'Tweaks') {
        foreach ($tweak in @($Catalog | Sort-Object -Property id)) {
            if ($SkipTypes -contains $tweak.type) { continue }
            try {
                $tweaks[[string]$tweak.id] = [pscustomobject]@{ type = [string]$tweak.type; state = (ConvertTo-Json -InputObject (Get-TuneupState -Tweak $tweak) -Depth 10 -Compress) }
            } catch {
                $tweaks[[string]$tweak.id] = [pscustomobject]@{ type = [string]$tweak.type; state = "unreadable: $($_.Exception.Message)" }
            }
        }
    }
    $services = [ordered]@{}
    if ($Parts -contains 'Services') {
        foreach ($key in @(Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services' | Sort-Object -Property PSChildName)) {
            $values = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if ($null -ne $values -and $null -ne $values.Start) { $services[$key.PSChildName] = "start=$($values.Start) delayed=$([int]$values.DelayedAutostart)" }
        }
    }
    $tasks = [ordered]@{}
    if ($Parts -contains 'Tasks') {
        foreach ($task in @(Get-ScheduledTask | Sort-Object -Property TaskPath, TaskName)) {
            $tasks["$($task.TaskPath)$($task.TaskName)"] = ([string]$task.State -ne 'Disabled')
        }
    }
    $apps = @()
    if ($Parts -contains 'Apps') {
        $apps = @(Get-AppxPackage -AllUsers | ForEach-Object { $_.PackageFullName } | Sort-Object -Unique)
    }
    [pscustomobject]@{ takenAt = (Get-Date).ToString('s'); tweaks = $tweaks; services = $services; tasks = $tasks; apps = $apps }
}

# A service tweak's state also says whether the service is running, which Windows changes on its own
# (trigger-started services): a difference only there is reported as volatile, not as a failure.
function Test-E2EVolatileDifference {
    param([Parameter(Mandatory)][string]$Type, [AllowNull()][string]$Before, [AllowNull()][string]$After)
    if ($Type -ne 'service' -or -not $Before -or -not $After) { return $false }
    try {
        $one = $Before | ConvertFrom-Json
        $two = $After | ConvertFrom-Json
    } catch {
        return $false
    }
    $one.present -eq $two.present -and $one.startType -eq $two.startType
}

function Compare-E2EMap {
    param([Parameter(Mandatory)][string]$Kind, $Before, $After, [scriptblock]$Volatile)
    $names = @(@($Before.Keys) + @($After.Keys) | Sort-Object -Unique)
    foreach ($name in $names) {
        $one = $(if ($Before.Contains($name)) { $Before[$name] } else { $null })
        $two = $(if ($After.Contains($name)) { $After[$name] } else { $null })
        $oneText = $(if ($null -ne $one -and $one.PSObject.Properties['state']) { $one.state } else { [string]$one })
        $twoText = $(if ($null -ne $two -and $two.PSObject.Properties['state']) { $two.state } else { [string]$two })
        if ($oneText -ceq $twoText) { continue }
        $isVolatile = $(if ($Volatile) { [bool](& $Volatile $one $two) } else { $false })
        [pscustomobject]@{ kind = $Kind; name = $name; before = $oneText; after = $twoText; volatile = $isVolatile }
    }
}

# Every difference between two snapshots; zero non-volatile differences is the goal after an undo.
function Compare-E2ESnapshot {
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After)
    $serviceVolatile = {
        param($one, $two)
        $type = $(if ($null -ne $one) { $one.type } elseif ($null -ne $two) { $two.type } else { '' })
        Test-E2EVolatileDifference -Type $type -Before $(if ($one) { $one.state }) -After $(if ($two) { $two.state })
    }
    Compare-E2EMap -Kind 'tweak' -Before $Before.tweaks -After $After.tweaks -Volatile $serviceVolatile
    Compare-E2EMap -Kind 'service' -Before $Before.services -After $After.services
    Compare-E2EMap -Kind 'task' -Before $Before.tasks -After $After.tasks
    foreach ($app in @($Before.apps | Where-Object { @($After.apps) -notcontains $_ })) {
        [pscustomobject]@{ kind = 'app'; name = $app; before = 'installed'; after = 'missing'; volatile = $false }
    }
    foreach ($app in @($After.apps | Where-Object { @($Before.apps) -notcontains $_ })) {
        [pscustomobject]@{ kind = 'app'; name = $app; before = 'missing'; after = 'installed'; volatile = $false }
    }
}

# The .wsb file for a run: the repository mapped read-only, the output folder writable, and the logon
# command that starts Invoke-E2E.ps1. Paths are escaped for XML.
function New-E2EConfiguration {
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Output,
        [AllowEmptyString()][string]$Arguments = ''
    )
    $text = $Template.Replace('__REPO__', [Security.SecurityElement]::Escape($Repo)).
        Replace('__OUTPUT__', [Security.SecurityElement]::Escape($Output)).
        Replace('__ARGUMENTS__', [Security.SecurityElement]::Escape($Arguments))
    [xml]$text | Out-Null
    $text
}

Export-ModuleMember -Function Get-E2ESnapshot, Compare-E2ESnapshot, Test-E2EVolatileDifference, New-E2EConfiguration
