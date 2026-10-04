BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    function New-RegTweak([string]$Path, [string]$Name, $Kind, $Value) {
        New-TestTweak -Set ([pscustomobject]@{ path = $Path; name = $Name; kind = $Kind; value = $Value })
    }
    # Denies the current user writing values in the test key only. The key is opened for its ACL
    # alone: Set-Acl would ask for write access, which the deny itself blocks.
    function Set-TestSetValueDeny([switch]$Remove) {
        $item = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\windows-tuneup-test',
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]'ReadPermissions, ChangePermissions')
        try {
            $acl = $item.GetAccessControl()
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule -ArgumentList `
                ([Security.Principal.WindowsIdentity]::GetCurrent().User), 'SetValue', 'None', 'None', 'Deny'
            if ($Remove) { [void]$acl.RemoveAccessRule($rule) } else { $acl.AddAccessRule($rule) }
            $item.SetAccessControl($acl)
        } finally {
            $item.Close()
        }
    }
}

Describe 'Registry handler' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) {
            Set-TestSetValueDeny -Remove
            Remove-Item -LiteralPath $Key -Recurse -Force
        }
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

    It 'fails when a value it created cannot be removed on restore' {
        $tweak = New-RegTweak $Key 'A' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak
        Set-RegistryTweakDesired -Tweak $tweak
        Set-TestSetValueDeny
        { Restore-RegistryTweakState -Tweak $tweak -State $state } | Should -Throw
        (Get-ItemProperty -LiteralPath $Key).A | Should -Be 1
    }

    It 'refuses, changing nothing, a value that cannot be removed for a null desired value' {
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name 'A' -PropertyType DWord -Value 7 | Out-Null
        Set-TestSetValueDeny
        $outcome = Get-TuneupOutcome -Output @(Set-RegistryTweakDesired -Tweak (New-RegTweak $Key 'A' $null $null))
        $outcome.refused | Should -BeTrue
        $outcome.reason | Should -Be 'protected-by-windows'
        (Get-ItemProperty -LiteralPath $Key).A | Should -Be 7
    }

    # Windows keeps some values from scripts even for an administrator (AllowNewsAndInterests on build
    # 26300): writing them is access denied while other values of the same key can be written.
    It 'refuses a value that Windows does not let it write, changing nothing' {
        New-Item -Path $Key -Force | Out-Null
        Set-TestSetValueDeny
        $tweak = New-RegTweak $Key 'A' 'DWord' 1
        $before = Get-RegistryTweakState -Tweak $tweak | ConvertTo-Json -Compress
        $outcome = Get-TuneupOutcome -Output @(Set-RegistryTweakDesired -Tweak $tweak)
        $outcome.refused | Should -BeTrue
        $outcome.reason | Should -Be 'protected-by-windows'
        $outcome.detail | Should -BeLike "*$Key\A*"
        Get-RegistryTweakState -Tweak $tweak | ConvertTo-Json -Compress | Should -Be $before
    }

    It 'removes the keys it created for a value it could not write, and names where to change it by hand' {
        Mock -ModuleName Tuneup New-ItemProperty { throw (New-Object System.UnauthorizedAccessException -ArgumentList 'Attempted to perform an unauthorized operation.') }
        $tweak = New-RegTweak "$Key\Sub\Deep" 'A' 'DWord' 1
        $tweak | Add-Member -NotePropertyName manualSetting -NotePropertyValue ([pscustomobject]@{ es = 'Configuracion > Widgets'; en = 'Settings > Widgets' })
        $before = Get-RegistryTweakState -Tweak $tweak | ConvertTo-Json -Compress
        $outcome = Get-TuneupOutcome -Output @(Set-RegistryTweakDesired -Tweak $tweak)
        $outcome.refused | Should -BeTrue
        $outcome.detail | Should -BeLike '*Settings > Widgets*'
        Test-Path -LiteralPath $Key | Should -BeFalse
        Get-RegistryTweakState -Tweak $tweak | ConvertTo-Json -Compress | Should -Be $before
    }

    It 'still fails on access denied to a machine value without elevation' {
        Mock -ModuleName Tuneup Test-TuneupAdmin { $false }
        Mock -ModuleName Tuneup New-Item { throw (New-Object System.UnauthorizedAccessException -ArgumentList 'denied') }
        $tweak = New-TestTweak -Scope 'machine' -Set ([pscustomobject]@{ path = 'HKLM:\SOFTWARE\windows-tuneup-test-missing'; name = 'A'; kind = 'DWord'; value = 1 })
        { Set-RegistryTweakDesired -Tweak $tweak } | Should -Throw '*denied*'
    }

    It 'restores a value whose empty key cannot be removed, saying the key is left' {
        $tweak = New-RegTweak "$Key\Sub" 'A' 'DWord' 1
        $state = Get-RegistryTweakState -Tweak $tweak
        New-Item -Path "$Key\Sub" -Force | Out-Null
        Mock -ModuleName Tuneup Remove-Item { throw (New-Object System.UnauthorizedAccessException -ArgumentList 'denied') }
        $outcome = Get-TuneupOutcome -Output @(Restore-RegistryTweakState -Tweak $tweak -State $state)
        $outcome.detail | Should -BeLike "*$Key\Sub*denied*"
        (Get-Item -LiteralPath "$Key\Sub").GetValueNames() -contains 'A' | Should -BeFalse
    }

    It 'treats removing an absent value or key as done' {
        { Set-RegistryTweakDesired -Tweak (New-RegTweak "$Key\Missing" 'A' $null $null) } | Should -Not -Throw
        New-Item -Path $Key -Force | Out-Null
        Set-TestSetValueDeny
        { Set-RegistryTweakDesired -Tweak (New-RegTweak $Key 'A' $null $null) } | Should -Not -Throw
        $state = [pscustomobject]@{ keyExisted = $true; existingAncestor = $Key; exists = $false; kind = $null; value = $null }
        { Restore-RegistryTweakState -Tweak (New-RegTweak $Key 'A' 'DWord' 1) -State $state } | Should -Not -Throw
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
