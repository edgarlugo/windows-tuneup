BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Root = 'HKCU:\Software\windows-tuneup-test'
    $script:Key = "$Root\GraphicsDrivers"
    $script:Tweak = New-TestTweak -Id 'gaming.hags-on' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'gaming-hags' })
    function Set-TestMode([int]$Value) {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'HwSchMode' -PropertyType DWord -Value $Value -Force | Out-Null
    }
}

Describe 'gaming-hags action' {
    BeforeEach {
        # HwSchMode lives in HKLM; the tests write the test key instead. The support of the driver is
        # what the graphics kernel answers: bit 0 of the WDDM 2.7 capabilities, -1 when it cannot say.
        New-Item -Path $Key -Force | Out-Null
        Mock -ModuleName Tuneup Get-GamingHagsActionHelperValue { [pscustomobject]@{ path = $Key; name = 'HwSchMode' } }
        $script:Caps = @(0, 1)
        Mock -ModuleName Tuneup Get-GamingHagsActionHelperCapability { $script:Caps }
    }

    AfterEach {
        if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    }

    It 'is loaded from actions/ and passes the catalog check' {
        @(Get-TuneupActionLoadError | Where-Object { $_.name -eq 'gaming-hags' }).Count | Should -Be 0
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'is not-present when no adapter supports it, <Name>' -TestCases @(
        @{ Name = 'with a driver that says no'; Caps = @(0, 0) }
        @{ Name = 'with a driver older than WDDM 2.7'; Caps = @(-1) }
        @{ Name = 'without any adapter'; Caps = @() }
        @{ Name = 'with only the enabled bit set'; Caps = @(2) }
    ) {
        param($Caps)
        $script:Caps = $Caps
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-present'
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*No graphics adapter supports*'
        (Get-ItemProperty -LiteralPath $Key).HwSchMode | Should -BeNullOrEmpty
    }

    It 'turns it on with value 2, asks for a restart and removes the value on undo' {
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $state = Get-TuneupState -Tweak $Tweak
        $state.supported | Should -BeTrue
        (Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)).rebootRequired | Should -BeTrue
        (Get-ItemProperty -LiteralPath $Key).HwSchMode | Should -Be 2
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        (Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $state)).rebootRequired | Should -BeTrue
        @((Get-Item -LiteralPath $Key).GetValueNames()) | Should -Not -Contain 'HwSchMode'
        Test-Path -LiteralPath $Key | Should -BeTrue
    }

    It 'treats value 1 as off and puts it back on undo' {
        Set-TestMode 1
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $state = Get-TuneupState -Tweak $Tweak
        Set-TuneupDesired -Tweak $Tweak | Out-Null
        Restore-TuneupState -Tweak $Tweak -State $state | Out-Null
        (Get-ItemProperty -LiteralPath $Key).HwSchMode | Should -Be 1
    }

    It 'is applied when it is already on' {
        Set-TestMode 2
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'is applied without HwSchMode when the driver <Name>' -TestCases @(
        @{ Name = 'turns it on by default'; Caps = @(0, 5) }
        @{ Name = 'says it is on now'; Caps = @(3) }
    ) {
        param($Caps)
        $script:Caps = $Caps
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        # A value of 1 turns it off whatever the driver would do.
        Set-TestMode 1
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'does not count the bits of an adapter that does not support it' {
        $script:Caps = @(6, 1)
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'asks for a restart on undo only when the undo changes the value' {
        $state = Get-TuneupState -Tweak $Tweak
        Set-TuneupDesired -Tweak $Tweak | Out-Null
        # The user turned it off again by hand before the undo: nothing changes, so no restart.
        Set-TestMode 1
        $before = [pscustomobject]@{ keyExisted = $true; existingAncestor = $Key; exists = $true; kind = 'DWord'; value = 1; supported = $true }
        (Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $before)).rebootRequired | Should -BeFalse
        (Get-ItemProperty -LiteralPath $Key).HwSchMode | Should -Be 1
        (Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $state)).rebootRequired | Should -BeTrue
        @((Get-Item -LiteralPath $Key).GetValueNames()) | Should -Not -Contain 'HwSchMode'
        (Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $state)).rebootRequired | Should -BeFalse
    }
}

Describe 'gaming-hags support query' {
    It 'points at the graphics driver settings of the machine' {
        $value = & (Get-Module Tuneup) { Get-GamingHagsActionHelperValue }
        $value.path | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        $value.name | Should -Be 'HwSchMode'
    }

    It 'lays out the structures of the graphics kernel as Windows does, and asks KMTQAITYPE_WDDM_2_7_CAPS (70)' {
        & (Get-Module Tuneup) { Initialize-GamingHagsActionHelperNative }
        $sizes = [WindowsTuneupGpuScheduling]::Sizes()
        # D3DKMT_ADAPTERINFO, D3DKMT_ENUMADAPTERS2, D3DKMT_QUERYADAPTERINFO and D3DKMT_CLOSEADAPTER.
        $expected = $(if ([IntPtr]::Size -eq 8) { @(20, 16, 24, 4) } else { @(20, 8, 16, 4) })
        $sizes -join ',' | Should -Be ($expected -join ',')
        [WindowsTuneupGpuScheduling]::Wddm27Caps | Should -Be 70
        [WindowsTuneupGpuScheduling]::BufferTooSmall | Should -Be -1073741789
    }

    It 'asks the graphics kernel without changing anything and gets one number per adapter' {
        $caps = @(& (Get-Module Tuneup) { Get-GamingHagsActionHelperCapability })
        foreach ($value in $caps) { $value | Should -BeOfType [int] ; $value | Should -BeGreaterOrEqual -1 }
    }
}
