$script:ScStartArguments = @{
    Automatic        = 'auto'
    AutomaticDelayed = 'delayed-auto'
    Manual           = 'demand'
    Disabled         = 'disabled'
}

function Invoke-TuneupSc {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Start)
    $sc = Join-Path $env:SystemRoot 'System32\sc.exe'
    $output = & $sc config $Name start= $Start 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe config $Name start= $Start failed with exit code ${LASTEXITCODE}: $output"
    }
}

function Set-TuneupServiceStartType {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$StartType)
    Invoke-TuneupSc -Name $Name -Start $script:ScStartArguments[$StartType]
}

function Get-ServiceTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.name
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (-not (Test-Path -LiteralPath $registryPath)) {
        return [pscustomobject]@{ present = $false; startType = $null; running = $false }
    }
    $properties = Get-ItemProperty -LiteralPath $registryPath
    $startType = switch ([int]$properties.Start) {
        0 { 'Boot' }
        1 { 'System' }
        2 { if ($properties.DelayedAutostart -eq 1) { 'AutomaticDelayed' } else { 'Automatic' } }
        3 { 'Manual' }
        4 { 'Disabled' }
        default { "Unknown$($properties.Start)" }
    }
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    [pscustomobject]@{
        present   = $true
        startType = $startType
        running   = [bool]($service -and $service.Status -eq 'Running')
    }
}

function Test-ServiceTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $state = Get-ServiceTweakState -Tweak $Tweak
    if (-not $state.present) { return 'not-present' }
    if ($state.startType -eq $Tweak.set.startType) { return 'applied' }
    'not-applied'
}

function Set-ServiceTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    Set-TuneupServiceStartType -Name $Tweak.set.name -StartType $Tweak.set.startType
    if ($Tweak.set.stop) { Stop-Service -Name $Tweak.set.name -Force -ErrorAction SilentlyContinue }
}

function Restore-ServiceTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if (-not $State.present) { return }
    if ($script:ScStartArguments.ContainsKey([string]$State.startType)) {
        Set-TuneupServiceStartType -Name $Tweak.set.name -StartType $State.startType
    }
    if ($State.running) { Start-Service -Name $Tweak.set.name -ErrorAction SilentlyContinue }
}
