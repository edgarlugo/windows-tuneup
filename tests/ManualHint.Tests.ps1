BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    # The lines of a hint, joined with | so that one line stays a string.
    function Get-Hint($Tweak, $State) { @(Get-TuneupManualRestoreHint -Tweak $Tweak -State $State) -join '|' }
}

Describe 'Get-TuneupManualRestoreHint' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'gives reg.exe lines that put a registry value back, or delete it, and they work' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $Key; name = 'Hint'; kind = 'DWord'; value = 1 })
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'Hint' -PropertyType DWord -Value ([int]-2) | Out-Null
        $hint = Get-Hint $tweak (Get-RegistryTweakState -Tweak $tweak)
        $hint | Should -Be 'reg.exe add "HKCU\Software\windows-tuneup-test" /v "Hint" /t REG_DWORD /d 4294967294 /f'
        Set-ItemProperty -LiteralPath $Key -Name 'Hint' -Value 7
        & cmd.exe /c $hint | Out-Null
        $LASTEXITCODE | Should -Be 0
        (Get-Item -LiteralPath $Key).GetValue('Hint') | Should -Be -2
        $absent = [pscustomobject]@{ keyExisted = $true; existingAncestor = $Key; exists = $false; kind = $null; value = $null }
        $delete = Get-Hint $tweak $absent
        $delete | Should -Be 'reg.exe delete "HKCU\Software\windows-tuneup-test" /v "Hint" /f'
        & cmd.exe /c $delete | Out-Null
        $LASTEXITCODE | Should -Be 0
        (Get-Item -LiteralPath $Key).GetValueNames() | Should -Not -Contain 'Hint'
    }

    It 'escapes a double quote inside a name or a value' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $Key; name = 'Say "hi"'; kind = 'String'; value = 'x' })
        Get-Hint $tweak ([pscustomobject]@{ exists = $true; kind = 'String'; value = 'a "b"' }) |
            Should -Be 'reg.exe add "HKCU\Software\windows-tuneup-test" /v "Say \"hi\"" /t REG_SZ /d "a \"b\"" /f'
    }

    It 'writes strings, lists and bytes in the form reg.exe takes' -TestCases @(
        @{ Kind = 'String'; Value = 'a b'; Expected = '/t REG_SZ /d "a b"' }
        @{ Kind = 'ExpandString'; Value = '%TEMP%\x'; Expected = '/t REG_EXPAND_SZ /d "%TEMP%\x"' }
        @{ Kind = 'MultiString'; Value = @('one', 'two'); Expected = '/t REG_MULTI_SZ /d "one\0two"' }
        @{ Kind = 'Binary'; Value = @(1, 171); Expected = '/t REG_BINARY /d 01ab' }
        @{ Kind = 'QWord'; Value = 5; Expected = '/t REG_QWORD /d 5' }
    ) {
        param($Kind, $Value, $Expected)
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = 'HKLM:\SOFTWARE\X'; name = 'V'; kind = $Kind; value = $Value })
        $state = [pscustomobject]@{ exists = $true; kind = $Kind; value = $Value }
        Get-Hint $tweak $state | Should -Be "reg.exe add `"HKLM\SOFTWARE\X`" /v `"V`" $Expected /f"
    }

    It 'gives the start type of a service, and starts it if it was running' {
        $tweak = New-TestTweak -Type 'service' -Scope 'machine' -Set ([pscustomobject]@{ name = 'DiagTrack'; startType = 'Disabled' })
        Get-Hint $tweak ([pscustomobject]@{ present = $true; startType = 'AutomaticDelayed'; running = $true }) | Should -Be 'sc.exe config "DiagTrack" start= delayed-auto|sc.exe start "DiagTrack"'
        Get-Hint $tweak ([pscustomobject]@{ present = $false; startType = $null; running = $false }) | Should -BeNullOrEmpty
    }

    It 'gives schtasks, DISM, winget and powercfg lines for the other types' {
        $task = New-TestTweak -Type 'task' -Scope 'machine' -Set ([pscustomobject]@{ path = '\Microsoft\Windows\X\'; name = 'Y'; state = 'Disabled' })
        Get-Hint $task ([pscustomobject]@{ present = $true; enabled = $true }) | Should -Be 'schtasks.exe /Change /TN "\Microsoft\Windows\X\Y" /ENABLE'
        $capability = New-TestTweak -Type 'capability' -Scope 'machine' -Set ([pscustomobject]@{ name = 'App.StepsRecorder~~~~0.0.1.0'; state = 'NotPresent' })
        Get-Hint $capability ([pscustomobject]@{ present = $true; state = 'Installed' }) | Should -Be 'DISM.exe /Online /Add-Capability /CapabilityName:App.StepsRecorder~~~~0.0.1.0'
        $feature = New-TestTweak -Type 'feature' -Scope 'machine' -Set ([pscustomobject]@{ name = 'WorkFolders-Client'; state = 'Disabled' })
        Get-Hint $feature ([pscustomobject]@{ present = $true; state = 'Enabled' }) | Should -Be 'DISM.exe /Online /Enable-Feature /FeatureName:WorkFolders-Client /NoRestart'
        $appx = New-TestTweak -Type 'appx' -Scope 'machine' -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' })
        Get-Hint $appx $null | Should -Be 'winget install --id 9WZDNCRFHVFW --source msstore'
        $scheme = New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]@{ kind = 'scheme'; scheme = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' })
        Get-Hint $scheme ([pscustomobject]@{ kind = 'scheme'; active = '381b4222-f694-41f0-9685-ff5bb260df2e'; exists = $true }) | Should -Be 'powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e'
        $setting = New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = 'A'; setting = 'B'; ac = 0 })
        Get-Hint $setting ([pscustomobject]@{ kind = 'setting'; scheme = 's1'; present = $true; ac = 1200; dc = 600 }) | Should -Be 'powercfg.exe /setacvalueindex s1 a b 1200|powercfg.exe /setactive SCHEME_CURRENT'
    }

    It 'points an action to the README and gives nothing without a saved state' {
        $action = New-TestTweak -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'onedrive' })
        Get-Hint $action $null | Should -Be "Restore it by hand: README (Tweak types) explains what the 'onedrive' action changes."
        Get-Hint (New-TestTweak) $null | Should -BeNullOrEmpty
    }
}
