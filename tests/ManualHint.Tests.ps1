BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    # The lines of a hint, joined with | so that one line stays a string.
    function Get-Hint($Tweak, $State) { @(Get-TuneupManualRestoreHint -Tweak $Tweak -State $State) -join '|' }
    # Runs one line of a hint in its own PowerShell, like a person pasting it. The line goes encoded, so
    # nothing but the line itself decides what runs. Gives the exit code and what it wrote.
    function Invoke-HintLine([string]$Line) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('$ErrorActionPreference = ''Stop''; ' + $Line))
        $output = & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
    }
    function Get-StoredValue([string]$Name) { (Get-Item -LiteralPath $Key).GetValue($Name, $null, 'DoNotExpandEnvironmentNames') }
}

Describe 'Get-TuneupManualRestoreHint' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'gives PowerShell lines that put a registry value back, or delete it, and they work' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $Key; name = 'Hint'; kind = 'DWord'; value = 1 })
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'Hint' -PropertyType DWord -Value ([int]-2) | Out-Null
        $hint = Get-Hint $tweak (Get-RegistryTweakState -Tweak $tweak)
        $hint | Should -Be "New-ItemProperty -LiteralPath 'HKCU:\Software\windows-tuneup-test' -Name 'Hint' -PropertyType DWord -Value -2 -Force | Out-Null"
        Set-ItemProperty -LiteralPath $Key -Name 'Hint' -Value 7
        (Invoke-HintLine $hint).Code | Should -Be 0
        Get-StoredValue 'Hint' | Should -Be -2
        $absent = [pscustomobject]@{ keyExisted = $true; existingAncestor = $Key; exists = $false; kind = $null; value = $null }
        $delete = Get-Hint $tweak $absent
        $delete | Should -Be "Remove-ItemProperty -LiteralPath 'HKCU:\Software\windows-tuneup-test' -Name 'Hint'"
        (Invoke-HintLine $delete).Code | Should -Be 0
        (Get-Item -LiteralPath $Key).GetValueNames() | Should -Not -Contain 'Hint'
    }

    It 'gives back exactly the value that was saved, whatever characters it has' -TestCases @(
        @{ Kind = 'DWord'; Value = -2; Expected = -2 }
        @{ Kind = 'DWord'; Value = 1; Expected = 1 }
        @{ Kind = 'QWord'; Value = 5000000000; Expected = 5000000000 }
        @{ Kind = 'String'; Value = 'a b'; Expected = 'a b' }
        @{ Kind = 'String'; Value = 'C:\Program Files\x\'; Expected = 'C:\Program Files\x\' }
        @{ Kind = 'String'; Value = ''; Expected = '' }
        @{ Kind = 'String'; Value = 'it''s "quoted"'; Expected = 'it''s "quoted"' }
        @{ Kind = 'String'; Value = 'a & b | c % d $env:USERNAME $(1+1) ; `n'; Expected = 'a & b | c % d $env:USERNAME $(1+1) ; `n' }
        @{ Kind = 'String'; Value = ('x' + [char]0x2019 + 'y' + [char]0x2018 + 'z'); Expected = ('x' + [char]0x2019 + 'y' + [char]0x2018 + 'z') }
        @{ Kind = 'String'; Value = "line1`r`nline2"; Expected = "line1`r`nline2" }
        @{ Kind = 'ExpandString'; Value = '%TEMP%\x $env:TEMP'; Expected = '%TEMP%\x $env:TEMP' }
        @{ Kind = 'MultiString'; Value = @('one', 'two'); Expected = 'one|two' }
        @{ Kind = 'MultiString'; Value = @('it''s', '$x', 'a & b'); Expected = 'it''s|$x|a & b' }
        @{ Kind = 'MultiString'; Value = @(); Expected = '' }
        @{ Kind = 'Binary'; Value = @(1, 171, 255); Expected = '1|171|255' }
        @{ Kind = 'Binary'; Value = @(7); Expected = '7' }
        @{ Kind = 'Binary'; Value = @(); Expected = '' }
        @{ Kind = 'None'; Value = @(1, 2); Expected = '1|2' }
    ) {
        param($Kind, $Value, $Expected)
        $name = 'Say ''hi'' & "bye" $x'
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $Key; name = $name; kind = 'String'; value = 'x' })
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name $name -PropertyType String -Value 'something else' | Out-Null
        $hint = Get-Hint $tweak ([pscustomobject]@{ keyExisted = $true; existingAncestor = $Key; exists = $true; kind = $Kind; value = $Value })
        $result = Invoke-HintLine $hint
        $result.Code | Should -Be 0 -Because $result.Output
        $item = Get-Item -LiteralPath $Key
        $item.GetValueKind($name).ToString() | Should -Be $Kind
        $stored = $item.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
        $item.Close()
        if ($Kind -in 'MultiString', 'Binary', 'None') { ($stored -join '|') | Should -Be $Expected }
        else { $stored | Should -Be $Expected }
    }

    It 'removes the keys that the tweak created, only while they are empty' {
        $deep = "$Key\a\b"
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = $deep; name = 'Hint'; kind = 'DWord'; value = 1 })
        $state = [pscustomobject]@{ keyExisted = $false; existingAncestor = $Key; exists = $false; kind = $null; value = $null }
        $lines = @(Get-TuneupManualRestoreHint -Tweak $tweak -State $state)
        $lines.Count | Should -Be 3
        $lines[1] | Should -BeLike "*'HKCU:\Software\windows-tuneup-test\a\b'*"
        $lines[2] | Should -BeLike "*'HKCU:\Software\windows-tuneup-test\a'*"
        New-Item -Path $deep -Force | Out-Null
        New-ItemProperty -LiteralPath $deep -Name 'Hint' -PropertyType DWord -Value 1 | Out-Null
        foreach ($line in $lines) { (Invoke-HintLine $line).Code | Should -Be 0 }
        Test-Path -LiteralPath "$Key\a" | Should -BeFalse
        Test-Path -LiteralPath $Key | Should -BeTrue
        # A key that holds something else stays, and the line says so.
        New-Item -Path $deep -Force | Out-Null
        New-ItemProperty -LiteralPath $deep -Name 'Hint' -PropertyType DWord -Value 1 | Out-Null
        New-ItemProperty -LiteralPath "$Key\a" -Name 'Other' -PropertyType DWord -Value 1 | Out-Null
        $outputs = @(foreach ($line in $lines) { (Invoke-HintLine $line).Output })
        Test-Path -LiteralPath $deep | Should -BeFalse
        Test-Path -LiteralPath "$Key\a" | Should -BeTrue
        $outputs -join '' | Should -Match 'Not removed'
    }

    It 'only removes the value when it does not know which keys the tweak created' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = "$Key\a"; name = 'Hint'; kind = 'DWord'; value = 1 })
        $old = [pscustomobject]@{ exists = $false }
        @(Get-TuneupManualRestoreHint -Tweak $tweak -State $old).Count | Should -Be 1
    }

    It 'doubles every quote of a literal and writes a line break as a character' {
        ConvertTo-TuneupPsLiteral -Text 'a''b' | Should -Be '''a''''b'''
        ConvertTo-TuneupPsLiteral -Text ('a' + [char]0x2019 + 'b') | Should -Be ('''a' + [char]0x2019 + [char]0x2019 + 'b''')
        ConvertTo-TuneupPsLiteral -Text "a`r`nb" | Should -Be "('a' + [char]13 + '' + [char]10 + 'b')"
        ConvertTo-TuneupPsLiteral -Text '' | Should -Be ''''''
    }

    It 'writes a value of an unknown kind with the .NET call, and nothing for a kind it cannot write' {
        $tweak = New-TestTweak -Set ([pscustomobject]@{ path = 'HKLM:\SOFTWARE\X'; name = 'V'; kind = 'Binary'; value = @(1) })
        Get-Hint $tweak ([pscustomobject]@{ exists = $true; kind = 'Unknown'; value = @(1, 2) }) |
            Should -Be "[Microsoft.Win32.Registry]::SetValue('HKEY_LOCAL_MACHINE\SOFTWARE\X', 'V', ([byte[]](0x01,0x02)), [Microsoft.Win32.RegistryValueKind]::None)"
        Get-Hint $tweak ([pscustomobject]@{ exists = $true; kind = 'Mystery'; value = 1 }) | Should -BeNullOrEmpty
    }

    It 'gives the start type of a service, and starts it if it was running' {
        $tweak = New-TestTweak -Type 'service' -Scope 'machine' -Set ([pscustomobject]@{ name = 'DiagTrack'; startType = 'Disabled' })
        Get-Hint $tweak ([pscustomobject]@{ present = $true; startType = 'AutomaticDelayed'; running = $true }) | Should -Be "sc.exe config 'DiagTrack' start= delayed-auto|Start-Service -Name 'DiagTrack'"
        Get-Hint $tweak ([pscustomobject]@{ present = $true; startType = 'Manual'; running = $false }) | Should -Be "Set-Service -Name 'DiagTrack' -StartupType Manual"
        Get-Hint $tweak ([pscustomobject]@{ present = $true; startType = 'Automatic'; running = $false }) | Should -Be "Set-Service -Name 'DiagTrack' -StartupType Automatic"
        Get-Hint $tweak ([pscustomobject]@{ present = $true; startType = 'Disabled'; running = $false }) | Should -Be "Set-Service -Name 'DiagTrack' -StartupType Disabled"
        Get-Hint $tweak ([pscustomobject]@{ present = $false; startType = $null; running = $false }) | Should -BeNullOrEmpty
    }

    It 'gives sc.exe only for a service name it can take as one word' {
        $odd = New-TestTweak -Type 'service' -Scope 'machine' -Set ([pscustomobject]@{ name = 'Odd$(1) name'; startType = 'Disabled' })
        Get-Hint $odd ([pscustomobject]@{ present = $true; startType = 'AutomaticDelayed'; running = $false }) | Should -BeNullOrEmpty
        Get-Hint $odd ([pscustomobject]@{ present = $true; startType = 'Manual'; running = $false }) | Should -Be "Set-Service -Name 'Odd`$(1) name' -StartupType Manual"
    }

    It 'gives the task, capability and feature lines, in both directions' {
        $task = New-TestTweak -Type 'task' -Scope 'machine' -Set ([pscustomobject]@{ path = '\Microsoft\Windows\X\'; name = 'Y'; state = 'Disabled' })
        Get-Hint $task ([pscustomobject]@{ present = $true; enabled = $true }) | Should -Be "Enable-ScheduledTask -TaskPath '\Microsoft\Windows\X\' -TaskName 'Y'"
        Get-Hint $task ([pscustomobject]@{ present = $true; enabled = $false }) | Should -Be "Disable-ScheduledTask -TaskPath '\Microsoft\Windows\X\' -TaskName 'Y'"
        Get-Hint $task ([pscustomobject]@{ present = $false; enabled = $null }) | Should -BeNullOrEmpty
        $capability = New-TestTweak -Type 'capability' -Scope 'machine' -Set ([pscustomobject]@{ name = 'App.StepsRecorder~~~~0.0.1.0'; state = 'NotPresent' })
        Get-Hint $capability ([pscustomobject]@{ present = $true; state = 'Installed' }) | Should -Be "Add-WindowsCapability -Online -Name 'App.StepsRecorder~~~~0.0.1.0'"
        Get-Hint $capability ([pscustomobject]@{ present = $true; state = 'NotPresent' }) | Should -Be "Remove-WindowsCapability -Online -Name 'App.StepsRecorder~~~~0.0.1.0'"
        $feature = New-TestTweak -Type 'feature' -Scope 'machine' -Set ([pscustomobject]@{ name = 'WorkFolders-Client'; state = 'Disabled' })
        Get-Hint $feature ([pscustomobject]@{ present = $true; state = 'Enabled' }) | Should -Be "Enable-WindowsOptionalFeature -Online -FeatureName 'WorkFolders-Client' -NoRestart"
        Get-Hint $feature ([pscustomobject]@{ present = $true; state = 'Disabled' }) | Should -Be "Disable-WindowsOptionalFeature -Online -FeatureName 'WorkFolders-Client' -NoRestart"
    }

    It 'gives the powercfg lines only for GUIDs and numbers, and one winget line from the same source as the undo notes' {
        $scheme = New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]@{ kind = 'scheme'; scheme = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' })
        Get-Hint $scheme ([pscustomobject]@{ kind = 'scheme'; active = '381b4222-f694-41f0-9685-ff5bb260df2e'; exists = $true }) | Should -Be 'powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e'
        Get-Hint $scheme ([pscustomobject]@{ kind = 'scheme'; active = '1; calc'; exists = $true }) | Should -BeNullOrEmpty
        $subgroup = '4f971e89-eebd-4455-a8de-9e59040e7347'
        $setting = '5ca83367-6e45-459f-a27b-476b1d01c936'
        $both = New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $subgroup.ToUpper(); setting = $setting; ac = 0; dc = 1 })
        Get-Hint $both ([pscustomobject]@{ kind = 'setting'; scheme = '381b4222-f694-41f0-9685-ff5bb260df2e'; present = $true; ac = 1200; dc = 600 }) |
            Should -Be "powercfg.exe /setacvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e $subgroup $setting 1200|powercfg.exe /setdcvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e $subgroup $setting 600|powercfg.exe /setactive SCHEME_CURRENT"
        $acOnly = New-TestTweak -Type 'powercfg' -Scope 'machine' -Set ([pscustomobject]@{ kind = 'setting'; scheme = 'SCHEME_CURRENT'; subgroup = $subgroup; setting = $setting; ac = 0 })
        Get-Hint $acOnly ([pscustomobject]@{ kind = 'setting'; scheme = '381b4222-f694-41f0-9685-ff5bb260df2e'; present = $true; ac = 1200; dc = 600 }) |
            Should -Be "powercfg.exe /setacvalueindex 381b4222-f694-41f0-9685-ff5bb260df2e $subgroup $setting 1200|powercfg.exe /setactive SCHEME_CURRENT"
        Get-Hint $acOnly ([pscustomobject]@{ kind = 'setting'; scheme = 'x; y'; present = $true; ac = 1; dc = 1 }) | Should -BeNullOrEmpty
        $appx = New-TestTweak -Type 'appx' -Scope 'machine' -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' })
        Get-Hint $appx $null | Should -Be 'winget install --id 9WZDNCRFHVFW --source msstore'
        Get-Hint $appx $null | Should -Be (Get-TuneupWingetManualCommand -StoreId '9WZDNCRFHVFW')
        $badId = New-TestTweak -Type 'appx' -Scope 'machine' -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZ; calc'; action = 'remove' })
        Get-Hint $badId $null | Should -BeNullOrEmpty
    }

    It 'points an action to the README and gives nothing without a saved state' {
        $action = New-TestTweak -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'onedrive' })
        Get-Hint $action $null | Should -Be "Restore it by hand: README (Tweak types) explains what the 'onedrive' action changes."
        Get-Hint (New-TestTweak) $null | Should -BeNullOrEmpty
    }
}
