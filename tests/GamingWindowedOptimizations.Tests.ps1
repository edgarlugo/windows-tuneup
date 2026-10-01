BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Root = 'HKCU:\Software\windows-tuneup-test'
    $script:Key = "$Root\DirectX\UserGpuPreferences"
    $script:Tweak = New-TestTweak -Id 'gaming.windowed-optimizations' -Type 'action' -Scope 'machine' `
        -Set ([pscustomobject]@{ script = 'gaming-windowed-optimizations' })
    function Get-TestValue { (Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue).DirectXUserGlobalSettings }
}

Describe 'gaming-windowed-optimizations action' {
    BeforeEach {
        # The real value is in the user's DirectX preferences; the tests use the test key instead.
        Mock -ModuleName Tuneup Get-GamingWindowedOptimizationsActionHelperValue { [pscustomobject]@{ path = $Key; name = 'DirectXUserGlobalSettings' } }
    }

    AfterEach {
        if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    }

    It 'is loaded from actions/ and passes the catalog check' {
        @(Get-TuneupActionLoadError | Where-Object { $_.name -eq 'gaming-windowed-optimizations' }).Count | Should -Be 0
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'creates the value when it does not exist and removes it, with the key it created, on undo' {
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $state = Get-TuneupState -Tweak $Tweak
        Set-TuneupDesired -Tweak $Tweak
        Get-TestValue | Should -BeExactly 'SwapEffectUpgradeEnable=1;'
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        Restore-TuneupState -Tweak $Tweak -State $state
        Test-Path -LiteralPath "$Root\DirectX" | Should -BeFalse
    }

    It 'keeps the other choices and their order, and gives back the exact text on undo' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=0;AutoHDREnable=1;' | Out-Null
        $state = Get-TuneupState -Tweak $Tweak
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        Set-TuneupDesired -Tweak $Tweak
        Get-TestValue | Should -BeExactly 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;AutoHDREnable=1;'
        Restore-TuneupState -Tweak $Tweak -State $state
        Get-TestValue | Should -BeExactly 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=0;AutoHDREnable=1;'
    }

    It 'adds its choice at the end of a list without it' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'VRROptimizeEnable=0' | Out-Null
        Set-TuneupDesired -Tweak $Tweak
        Get-TestValue | Should -BeExactly 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;'
    }

    It 'is applied when the choice is already on, whatever else the list holds' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'AutoHDREnable=1; SwapEffectUpgradeEnable=1 ;' | Out-Null
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'leaves a value that is not text alone instead of guessing' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType DWord -Value 1 | Out-Null
        { Test-TuneupState -Tweak $Tweak } | Should -Throw '*not text*'
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*not text*'
        (Get-ItemProperty -LiteralPath $Key).DirectXUserGlobalSettings | Should -Be 1
    }
}

Describe 'gaming-windowed-optimizations target' {
    It 'points at the DirectX preferences of the current user' {
        $value = & (Get-Module Tuneup) { Get-GamingWindowedOptimizationsActionHelperValue }
        $value.path | Should -Be 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
        $value.name | Should -Be 'DirectXUserGlobalSettings'
    }
}
