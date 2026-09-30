BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $policySet = [pscustomobject]@{ path = 'HKLM:\SOFTWARE\Policies\Microsoft\Example'; name = 'A'; kind = 'DWord'; value = 1 }
    $script:Catalog = @(
        (New-TestTweak -Id 'ui.a'),
        (New-TestTweak -Id 'ui.b'),
        (New-TestTweak -Id 'apps.xbox'),
        (New-TestTweak -Id 'gaming.vbs-off' -Risk 'high'),
        (New-TestTweak -Id 'apps.onedrive' -Ask $true),
        (New-TestTweak -Id 'policy.example' -Scope 'machine' -Set $policySet),
        (New-TestTweak -Id 'ui.home-only' -Editions @('Home')),
        (New-TestTweak -Id 'ui.future' -MinBuild 30000)
    )
    $script:Profiles = @(
        (New-TestProfile -Id 'base' -Include @('ui.a')),
        (New-TestProfile -Id 'gaming' -Aliases @('juegos') -Include @('ui.b') -Keep @('apps.xbox')),
        (New-TestProfile -Id 'lite' -Aliases @('liviano') -Include @('apps.xbox', 'apps.onedrive', 'policy.example', 'ui.home-only', 'ui.future')),
        (New-TestProfile -Id 'unsafe' -Include @('gaming.vbs-off'))
    )
    $script:NotApplied = { param($tweak) 'not-applied' }
    function Invoke-Plan {
        param([string[]]$ProfileIds = @(), [string[]]$Include = @(), [string[]]$Exclude = @(), $Environment = (New-TestEnvironment), [scriptblock]$TestState = $NotApplied, [switch]$Interactive)
        @(New-TuneupPlan -Catalog $Catalog -Profiles $Profiles -ProfileIds $ProfileIds -Include $Include -Exclude $Exclude -Environment $Environment -TestState $TestState -Interactive:$Interactive)
    }
    function Get-Reason($Plan, [string]$Id) { ($Plan | Where-Object { $_.Id -eq $Id }).Reason }
    function Get-Action($Plan, [string]$Id) { ($Plan | Where-Object { $_.Id -eq $Id }).Action }
}

Describe 'New-TuneupPlan' {
    It 'always includes the base profile' {
        $plan = Invoke-Plan
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a'
        Get-Action $plan 'ui.a' | Should -Be 'apply'
    }

    It 'resolves profile aliases case-insensitively' {
        $plan = Invoke-Plan -ProfileIds 'JUEGOS'
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a,ui.b'
    }

    It 'throws on an unknown profile' {
        { Invoke-Plan -ProfileIds 'nope' } | Should -Throw '*nope*'
    }

    It 'throws on an unknown included tweak' {
        { Invoke-Plan -Include 'ui.nope' } | Should -Throw '*ui.nope*'
    }

    It 'lets keep win over another profile' {
        Get-Reason (Invoke-Plan -ProfileIds 'gaming', 'lite') 'apps.xbox' | Should -Be 'kept-by-profile'
    }

    It 'lets an explicit include win over keep' {
        Get-Action (Invoke-Plan -ProfileIds 'gaming', 'lite' -Include 'apps.xbox') 'apps.xbox' | Should -Be 'apply'
    }

    It 'honors -Exclude' {
        Get-Reason (Invoke-Plan -Exclude 'ui.a') 'ui.a' | Should -Be 'excluded'
    }

    It 'skips high-risk tweaks unless included by name' {
        Get-Reason (Invoke-Plan -ProfileIds 'unsafe') 'gaming.vbs-off' | Should -Be 'high-risk-not-requested'
        Get-Action (Invoke-Plan -Include 'gaming.vbs-off') 'gaming.vbs-off' | Should -Be 'apply'
    }

    It 'skips ask tweaks when not interactive unless included' {
        Get-Reason (Invoke-Plan -ProfileIds 'lite') 'apps.onedrive' | Should -Be 'needs-confirmation'
        Get-Action (Invoke-Plan -ProfileIds 'lite' -Include 'apps.onedrive') 'apps.onedrive' | Should -Be 'apply'
        Get-Action (Invoke-Plan -ProfileIds 'lite' -Interactive) 'apps.onedrive' | Should -Be 'apply'
    }

    It 'leaves policies alone on managed devices' {
        $plan = Invoke-Plan -ProfileIds 'lite' -Environment (New-TestEnvironment -IsManaged $true)
        Get-Reason $plan 'policy.example' | Should -Be 'managed-device'
    }

    It 'skips tweaks for other editions and newer builds' {
        $plan = Invoke-Plan -ProfileIds 'lite'
        Get-Reason $plan 'ui.home-only' | Should -Be 'incompatible'
        Get-Reason $plan 'ui.future' | Should -Be 'incompatible'
    }

    It 'marks tweaks that are already applied or not present' {
        $state = { param($tweak) if ($tweak.id -eq 'ui.a') { 'applied' } else { 'not-present' } }
        $plan = Invoke-Plan -ProfileIds 'gaming' -TestState $state
        Get-Reason $plan 'ui.a' | Should -Be 'already-applied'
        Get-Reason $plan 'ui.b' | Should -Be 'not-present'
    }

    It 'lists each tweak once' {
        $plan = Invoke-Plan -ProfileIds 'lite', 'liviano' -Include 'apps.xbox'
        @($plan | Where-Object { $_.Id -eq 'apps.xbox' }).Count | Should -Be 1
    }
}
