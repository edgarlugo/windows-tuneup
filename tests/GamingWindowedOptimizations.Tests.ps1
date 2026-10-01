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
        Mock -ModuleName Tuneup Test-TuneupSessionUser { $true }
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

    It 'refuses, changing nothing, when the process does not run as the account at this desktop' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'AutoHDREnable=1;' | Out-Null
        Mock -ModuleName Tuneup Test-TuneupSessionUser { $false }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.refused | Should -BeTrue
        $outcome.reason | Should -Be 'session-user'
        $outcome.detail | Should -BeLike '*nothing was changed*'
        Get-TestValue | Should -BeExactly 'AutoHDREnable=1;'
        foreach ($lang in 'es', 'en') {
            Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang $lang
            Get-TuneupText -Key 'reason.session-user' | Should -Not -Be 'reason.session-user'
        }
    }

    It 'saves whose setting it is, so the undo of another account leaves it for its owner' {
        (Get-TuneupState -Tweak $Tweak).currentUserSid | Should -Be (Get-TestCurrentSid)
    }

    It 'reads the list as Windows does: <Name>' -TestCases @(
        @{ Name = 'any case and spaces around the name'; Text = 'AutoHDREnable=1; swapeffectupgradeenable = 1 ;'; Expected = 'applied' }
        @{ Name = 'the last copy wins when it is on'; Text = 'SwapEffectUpgradeEnable=0;;SwapEffectUpgradeEnable=1;'; Expected = 'applied' }
        @{ Name = 'the last copy wins when it is off'; Text = 'SwapEffectUpgradeEnable=1;SwapEffectUpgradeEnable=0;'; Expected = 'not-applied' }
        @{ Name = 'another value is not on'; Text = 'SwapEffectUpgradeEnable=10;'; Expected = 'not-applied' }
        @{ Name = 'a name that only starts the same is another choice'; Text = 'SwapEffectUpgradeEnableX=1;'; Expected = 'not-applied' }
    ) {
        param($Text, $Expected)
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value $Text | Out-Null
        Test-TuneupState -Tweak $Tweak | Should -Be $Expected
    }

    It 'writes one copy of its choice in place of the first and keeps how the others are written' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'AutoHDREnable=1; swapeffectupgradeenable = 0 ;;VRROptimizeEnable=0 ;SwapEffectUpgradeEnable=0;' | Out-Null
        Set-TuneupDesired -Tweak $Tweak
        Get-TestValue | Should -BeExactly 'AutoHDREnable=1;SwapEffectUpgradeEnable=1;;VRROptimizeEnable=0 ;'
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'AutoHDREnable=1; VRROptimizeEnable=0 ;' -Force | Out-Null
        Set-TuneupDesired -Tweak $Tweak
        Get-TestValue | Should -BeExactly 'AutoHDREnable=1; VRROptimizeEnable=0 ;SwapEffectUpgradeEnable=1;'
    }

    It 'gives back only its own choice on undo, keeping what changed in the others since' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=0;AutoHDREnable=1;' | Out-Null
        $state = Get-TuneupState -Tweak $Tweak
        Set-TuneupDesired -Tweak $Tweak
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;AutoHDREnable=0;' -Force | Out-Null
        Restore-TuneupState -Tweak $Tweak -State $state | Out-Null
        Get-TestValue | Should -BeExactly 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=0;AutoHDREnable=0;'
    }

    It 'takes out its choice on undo when it was not there, keeping a choice added since' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'VRROptimizeEnable=0;' | Out-Null
        $state = Get-TuneupState -Tweak $Tweak
        Set-TuneupDesired -Tweak $Tweak
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;AutoHDREnable=1;' -Force | Out-Null
        Restore-TuneupState -Tweak $Tweak -State $state | Out-Null
        Get-TestValue | Should -BeExactly 'VRROptimizeEnable=0;AutoHDREnable=1;'
    }

    It 'keeps the value and its key on undo when a choice was added to a value it created' {
        $state = Get-TuneupState -Tweak $Tweak
        Set-TuneupDesired -Tweak $Tweak
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'SwapEffectUpgradeEnable=1;AutoHDREnable=1;' -Force | Out-Null
        Restore-TuneupState -Tweak $Tweak -State $state | Out-Null
        Get-TestValue | Should -BeExactly 'AutoHDREnable=1;'
    }

    It 'leaves its choice on undo when the user changed it since' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'SwapEffectUpgradeEnable=0;AutoHDREnable=1;' | Out-Null
        $state = Get-TuneupState -Tweak $Tweak
        Set-TuneupDesired -Tweak $Tweak
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'SwapEffectUpgradeEnable=2;AutoHDREnable=1;' -Force | Out-Null
        $outcome = Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $state)
        Get-TestValue | Should -BeExactly 'SwapEffectUpgradeEnable=2;AutoHDREnable=1;'
        $outcome.detail | Should -BeLike '*changed after*left as it is*'
    }

    It 'restores a state saved before the user field existed' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'AutoHDREnable=1;' | Out-Null
        $state = [pscustomobject]@{ keyExisted = $true; existingAncestor = $Key; exists = $true; kind = 'String'; value = 'AutoHDREnable=1;' }
        Set-TuneupDesired -Tweak $Tweak
        Restore-TuneupState -Tweak $Tweak -State $state | Out-Null
        Get-TestValue | Should -BeExactly 'AutoHDREnable=1;'
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
