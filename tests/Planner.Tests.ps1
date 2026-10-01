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
        (New-TestTweak -Id 'ui.future' -MinBuild 30000),
        (New-TestTweak -Id 'ui.edge-build' -MinBuild 26100),
        (New-TestTweak -Id 'ui.only-11' -Families @('11')),
        (New-TestTweak -Id 'svc.policy-path' -Type 'service' -Scope 'machine' -Set ([pscustomobject]@{ path = 'HKLM:\SOFTWARE\Policies\Microsoft\Example'; name = 'Spooler'; startup = 'Disabled' })),
        (New-TestTweak -Id 'power.on-battery' -Requires @('battery')),
        (New-TestTweak -Id 'power.plugged-in' -Requires @('no-battery')),
        (New-TestTweak -Id 'power.old-laptop' -Requires @('battery') -Editions @('Home'))
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
    It 'applies a tweak whose minBuild equals the current build' {
        Get-Action (Invoke-Plan -Include 'ui.edge-build' -Environment (New-TestEnvironment -Build 26100)) 'ui.edge-build' | Should -Be 'apply'
        Get-Reason (Invoke-Plan -Include 'ui.edge-build' -Environment (New-TestEnvironment -Build 26099)) 'ui.edge-build' | Should -Be 'incompatible'
    }

    It 'skips a tweak whose OS family does not match' {
        Get-Reason (Invoke-Plan -Include 'ui.only-11' -Environment (New-TestEnvironment -Family '10' -Build 19045)) 'ui.only-11' | Should -Be 'incompatible'
        Get-Action (Invoke-Plan -Include 'ui.only-11') 'ui.only-11' | Should -Be 'apply'
    }

    It 'resolves a profile name with surrounding spaces' {
        ((Invoke-Plan -ProfileIds ' gaming ') | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a,ui.b'
    }

    It 'reports excluded when a tweak is both excluded and kept' {
        Get-Reason (Invoke-Plan -ProfileIds 'gaming', 'lite' -Exclude 'apps.xbox') 'apps.xbox' | Should -Be 'excluded'
    }

    It 'treats ids case-insensitively and lists each tweak once' {
        $plan = Invoke-Plan -Include 'UI.A'
        @($plan).Count | Should -Be 1
        $plan[0].Id | Should -Be 'ui.a'
        Get-Reason (Invoke-Plan -Exclude 'UI.A') 'ui.a' | Should -Be 'excluded'
        Get-Action (Invoke-Plan -ProfileIds 'gaming', 'lite' -Include 'APPS.XBOX') 'apps.xbox' | Should -Be 'apply'
        $plan = Invoke-Plan -ProfileIds 'gaming' -Include 'Ui.B'
        @($plan | Where-Object { $_.Id -eq 'ui.b' }).Count | Should -Be 1
    }

    It 'ignores blank entries' {
        $plan = Invoke-Plan -ProfileIds '', ' ' -Include '', '  ' -Exclude ''
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a'
    }

    It 'skips a tweak whose state cannot be read instead of aborting the plan' {
        $state = { param($tweak) if ($tweak.id -eq 'ui.b') { throw 'boom' } else { 'not-applied' } }
        $plan = Invoke-Plan -ProfileIds 'gaming' -TestState $state
        Get-Action $plan 'ui.b' | Should -Be 'skip'
        Get-Reason $plan 'ui.b' | Should -Be 'state-unreadable'
        Get-Action $plan 'ui.a' | Should -Be 'apply'
    }

    It 'reports the current state before high-risk and confirmation reasons' {
        $applied = { param($tweak) 'applied' }
        Get-Reason (Invoke-Plan -ProfileIds 'unsafe' -TestState $applied) 'gaming.vbs-off' | Should -Be 'already-applied'
        $absent = { param($tweak) 'not-present' }
        Get-Reason (Invoke-Plan -ProfileIds 'lite' -TestState $absent) 'apps.onedrive' | Should -Be 'not-present'
    }
    It 'lists a tweak that only arrives through -Include' {
        $plan = Invoke-Plan -Include 'UI.B'
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a,ui.b'
        Get-Action $plan 'ui.b' | Should -Be 'apply'
    }

    It 'trims spaces around -Include entries' {
        $plan = Invoke-Plan -Include ' ui.b '
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'ui.a,ui.b'
    }

    It 'does not treat non-registry tweaks as policies on managed devices' {
        $plan = Invoke-Plan -Include 'svc.policy-path' -Environment (New-TestEnvironment -IsManaged $true)
        Get-Action $plan 'svc.policy-path' | Should -Be 'apply'
    }
}

Describe 'New-TuneupPlan with state that needs elevation to read' {
    BeforeAll {
        $appSet = [pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' }
        $script:AppCatalog = @(
            (New-TestTweak -Id 'apps.news' -Type 'appx' -Scope 'machine' -Set $appSet),
            (New-TestTweak -Id 'apps.risky' -Type 'appx' -Scope 'machine' -Risk 'high' -Set $appSet)
        )
        $script:AppProfiles = @(New-TestProfile -Id 'base' -Include @('apps.news', 'apps.risky'))
        $script:UserEnvironment = New-TestEnvironment
        $script:UserEnvironment.IsAdmin = $false
    }

    It 'plans it as unverified without reading it when not elevated' {
        $plan = @(New-TuneupPlan -Catalog $AppCatalog -Profiles $AppProfiles -Environment $UserEnvironment -TestState { throw 'must not read' })
        $plan[0].Action | Should -Be 'apply'
        $plan[0].Reason | Should -Be 'unverified-needs-admin'
    }

    It 'still leaves out an unverified high-risk tweak that was not requested' {
        $plan = @(New-TuneupPlan -Catalog $AppCatalog -Profiles $AppProfiles -Environment $UserEnvironment -TestState { throw 'must not read' })
        $plan[1].Action | Should -Be 'skip'
        $plan[1].Reason | Should -Be 'high-risk-not-requested'
    }

    It 'reads it when elevated' {
        $plan = @(New-TuneupPlan -Catalog $AppCatalog -Profiles $AppProfiles -Environment (New-TestEnvironment) -TestState { 'applied' })
        $plan[0].Action | Should -Be 'skip'
        $plan[0].Reason | Should -Be 'already-applied'
    }
}

Describe 'New-TuneupPlan with hardware requirements' {
    It 'skips a tweak for machines with a battery on a machine without one' {
        $plan = Invoke-Plan -Include 'power.on-battery', 'power.plugged-in' -Environment (New-TestEnvironment -HasBattery $false)
        Get-Reason $plan 'power.on-battery' | Should -Be 'not-applicable-hardware'
        Get-Action $plan 'power.plugged-in' | Should -Be 'apply'
    }

    It 'skips a tweak for machines without a battery on a laptop' {
        $plan = Invoke-Plan -Include 'power.on-battery', 'power.plugged-in' -Environment (New-TestEnvironment -HasBattery $true)
        Get-Action $plan 'power.on-battery' | Should -Be 'apply'
        Get-Reason $plan 'power.plugged-in' | Should -Be 'not-applicable-hardware'
    }

    It 'reports the edition before the hardware (a battery-only tweak of another edition, on a machine without a battery)' {
        $plan = Invoke-Plan -Include 'power.old-laptop' -Environment (New-TestEnvironment -HasBattery $false)
        Get-Reason $plan 'power.old-laptop' | Should -Be 'incompatible'
    }

    It 'reports the hardware before reading the state' {
        $plan = Invoke-Plan -Include 'power.plugged-in' -Environment (New-TestEnvironment -HasBattery $true) -TestState { throw 'must not read' }
        Get-Reason $plan 'power.plugged-in' | Should -Be 'not-applicable-hardware'
    }

    It 'has a text for the new reason in both languages' {
        foreach ($lang in 'es', 'en') {
            Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang $lang
            Get-TuneupText -Key 'reason.not-applicable-hardware' | Should -Not -Be 'reason.not-applicable-hardware'
        }
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    }
}
