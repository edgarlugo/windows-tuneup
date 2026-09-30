BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function New-RegTweak([string]$Path, [string]$Name, $Kind, $Value) {
        New-TestTweak -Set ([pscustomobject]@{ path = $Path; name = $Name; kind = $Kind; value = $Value })
    }
}

Describe 'Registry handler' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'captures a missing value and the nearest existing ancestor' {
        $tweak = New-RegTweak "$Key\Sub" 'A' 'DWord' 1
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'not-applied'
        $state = Get-RegistryTweakState -Tweak $tweak
        $state.exists | Should -BeFalse
        $state.keyExisted | Should -BeFalse
        $state.existingAncestor | Should -Be 'HKCU:\Software'
    }

    It 'applies a DWord and reports it as applied' {
        $tweak = New-RegTweak "$Key\Sub" 'A' 'DWord' 1
        Set-RegistryTweakDesired -Tweak $tweak
        (Get-ItemProperty -LiteralPath "$Key\Sub").A | Should -Be 1
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'applied'
    }

    It 'handles DWord values above 2^31' {
        $tweak = New-RegTweak $Key 'Big' 'DWord' 4294967295
        Set-RegistryTweakDesired -Tweak $tweak
        (Get-Item -LiteralPath $Key).GetValue('Big') | Should -Be -1
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'applied'
    }

    It 'treats a different kind as not applied' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'A' -PropertyType String -Value '1' | Out-Null
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'A' 'DWord' 1) | Should -Be 'not-applied'
    }

    It 'removes the keys it created when restoring a value that did not exist' {
        $tweak = New-RegTweak "$Key\Sub\Deep" 'A' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak
        Set-RegistryTweakDesired -Tweak $tweak
        Restore-RegistryTweakState -Tweak $tweak -State $state
        Test-Path -LiteralPath $Key | Should -BeFalse
    }

    It 'restores the previous value and kind after a JSON round trip' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'A' -PropertyType String -Value 'old' | Out-Null
        $tweak = New-RegTweak $Key 'A' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        Set-RegistryTweakDesired -Tweak $tweak
        Restore-RegistryTweakState -Tweak $tweak -State $state
        $item = Get-Item -LiteralPath $Key
        $item.GetValueKind('A') | Should -Be 'String'
        $item.GetValue('A') | Should -Be 'old'
    }

    It 'keeps a key that existed before' {
        New-Item -Path $Key -Force | Out-Null
        $tweak = New-RegTweak $Key 'A' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak
        Set-RegistryTweakDesired -Tweak $tweak
        Restore-RegistryTweakState -Tweak $tweak -State $state
        Test-Path -LiteralPath $Key | Should -BeTrue
        (Get-Item -LiteralPath $Key).GetValueNames() -contains 'A' | Should -BeFalse
    }

    It 'removes a value when the desired value is null and restores it' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'A' -PropertyType DWord -Value 7 | Out-Null
        $tweak = New-RegTweak $Key 'A' $null $null
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'not-applied'
        $state = Get-RegistryTweakState -Tweak $tweak
        Set-RegistryTweakDesired -Tweak $tweak
        Test-RegistryTweakState -Tweak $tweak | Should -Be 'applied'
        Restore-RegistryTweakState -Tweak $tweak -State $state
        (Get-ItemProperty -LiteralPath $Key).A | Should -Be 7
    }

    It 'does not equate a MultiString element that contains a space with two elements' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'M' -PropertyType MultiString -Value @('a b') | Out-Null
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'M' 'MultiString' @('a', 'b')) | Should -Be 'not-applied'
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'M' 'MultiString' @('a b')) | Should -Be 'applied'
    }

    It 'compares Binary values byte by byte' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'B' -PropertyType Binary -Value ([byte[]]@(1, 2, 3)) | Out-Null
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'B' 'Binary' @(1, 2, 3)) | Should -Be 'applied'
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'B' 'Binary' @(1, 2)) | Should -Be 'not-applied'
        Test-RegistryTweakState -Tweak (New-RegTweak $Key 'B' 'Binary' @(1, 2, 4)) | Should -Be 'not-applied'
    }

    It 'restores a REG_NONE value with its kind and bytes after a JSON round trip' {
        $hive = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\windows-tuneup-test')
        $hive.SetValue('N', [byte[]]@(1, 2, 3), [Microsoft.Win32.RegistryValueKind]::None)
        $hive.Close()
        $tweak = New-RegTweak $Key 'N' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $state.kind | Should -Be 'None'
        Set-RegistryTweakDesired -Tweak $tweak
        (Get-Item -LiteralPath $Key).GetValueKind('N') | Should -Be 'DWord'
        Restore-RegistryTweakState -Tweak $tweak -State $state
        $item = Get-Item -LiteralPath $Key
        $item.GetValueKind('N') | Should -Be 'None'
        ($item.GetValue('N') -join ',') | Should -Be '1,2,3'
    }
}
