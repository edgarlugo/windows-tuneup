function Get-FixtureToggleActionState {
    param([Parameter(Mandatory)]$Tweak)
    $key = 'HKCU:\Software\windows-tuneup-test'
    $value = $null
    if (Test-Path -LiteralPath $key) { $value = (Get-ItemProperty -LiteralPath $key).Action }
    [pscustomobject]@{ value = $value }
}

function Test-FixtureToggleActionState {
    param([Parameter(Mandatory)]$Tweak)
    if ((Get-FixtureToggleActionState -Tweak $Tweak).value -eq 1) { 'applied' } else { 'not-applied' }
}

function Set-FixtureToggleActionDesired {
    param([Parameter(Mandatory)]$Tweak)
    Write-TuneupRegistryValue -Path 'HKCU:\Software\windows-tuneup-test' -Name 'Action' -Kind 'DWord' -Value 1
    New-TuneupOutcome -RebootRequired
}

function Restore-FixtureToggleActionState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    if ($null -eq $State.value) {
        Remove-TuneupRegistryValue -Path 'HKCU:\Software\windows-tuneup-test' -Name 'Action'
        return
    }
    Write-TuneupRegistryValue -Path 'HKCU:\Software\windows-tuneup-test' -Name 'Action' -Kind 'DWord' -Value $State.value
}
