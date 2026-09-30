BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:AdminSid = 'S-1-5-32-544'
    $script:OtherSid = 'S-1-5-21-1000000000-2000000000-3000000000-1001'
    $script:TrustedInstallerSid = 'S-1-5-80-956008885-3425145150-2718476148-1766412592'
    $script:MeSid = Get-TestCurrentSid
}

Describe 'State folder ACL' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    It 'builds a protected ACL owned by Administrators from well-known SIDs' {
        $security = New-TuneupStateSecurity
        $security | Should -BeOfType [System.Security.AccessControl.DirectorySecurity]
        $security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $AdminSid
        $security.AreAccessRulesProtected | Should -BeTrue
        $rules = Get-TestAccessRule $security
        $rules.Count | Should -Be 4
        $expected = @{
            'S-1-5-18'     = [System.Security.AccessControl.FileSystemRights]::FullControl
            'S-1-5-32-544' = [System.Security.AccessControl.FileSystemRights]::FullControl
            'S-1-5-32-545' = [System.Security.AccessControl.FileSystemRights]'ReadAndExecute, Synchronize'
            'S-1-3-4'      = [System.Security.AccessControl.FileSystemRights]'ReadAndExecute, Synchronize'
        }
        foreach ($rule in $rules) {
            $sid = $rule.IdentityReference.Value
            $expected.ContainsKey($sid) | Should -BeTrue -Because $sid
            $rule.FileSystemRights | Should -Be $expected[$sid] -Because $sid
            $rule.AccessControlType | Should -Be 'Allow'
            $rule.InheritanceFlags | Should -Be ([System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit')
            $rule.PropagationFlags | Should -Be ([System.Security.AccessControl.PropagationFlags]::None)
            $rule.IsInherited | Should -BeFalse
        }
    }

    It 'builds the same ACL for files without inheritance flags' {
        $security = New-TuneupStateSecurity -File
        $security | Should -BeOfType [System.Security.AccessControl.FileSecurity]
        $security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $AdminSid
        $security.AreAccessRulesProtected | Should -BeTrue
        $rules = Get-TestAccessRule $security
        ($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ',' | Should -Be 'S-1-3-4,S-1-5-18,S-1-5-32-544,S-1-5-32-545'
        @($rules | Where-Object { $_.InheritanceFlags -ne 'None' }).Count | Should -Be 0
    }

    It 'builds the ACL for injected SIDs' {
        $security = New-TuneupStateSecurity -OwnerSid $OtherSid -TrustedSids @($OtherSid)
        $security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $OtherSid
        ((Get-TestAccessRule $security) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ',' |
            Should -Be "S-1-3-4,$OtherSid,S-1-5-32-545"
    }

    It 'applies that ACL with Set-Acl' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Mock -ModuleName Tuneup Set-Acl { }
        Set-TuneupStateSecurity -Path $Folder
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq $Folder -and $AclObject.AreAccessRulesProtected -and
            $AclObject.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544' -and
            @($AclObject.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])).Count -eq 4
        }
    }

    It 'keeps the SACL out of Set-Acl when the folder is already protected' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Mock -ModuleName Tuneup Get-Acl {
            $current = New-Object System.Security.AccessControl.DirectorySecurity
            $current.SetAccessRuleProtection($true, $false)
            $current
        }
        Mock -ModuleName Tuneup Set-Acl { }
        Set-TuneupStateSecurity -Path $Folder
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $AclObject.AreAuditRulesProtected }
    }

    It 'reports the folder as not trusted when Set-Acl fails' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Mock -ModuleName Tuneup Set-Acl { throw 'Access denied' }
        { Set-TuneupStateSecurity -Path $Folder } |
            Should -Throw -ExpectedMessage "State folder $Folder is not trusted. Delete it as administrator and run again."
    }

    It 'hardens a real folder with injected SIDs' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Set-TuneupStateSecurity -Path $Folder -OwnerSid $MeSid -TrustedSids @($MeSid)
        $acl = Get-Acl -LiteralPath $Folder
        $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $MeSid
        $acl.AreAccessRulesProtected | Should -BeTrue
        $rules = Get-TestAccessRule $acl
        ($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ',' | Should -Be "S-1-3-4,$MeSid,S-1-5-32-545"
        ($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-3-4' }).FileSystemRights |
            Should -Be ([System.Security.AccessControl.FileSystemRights]'ReadAndExecute, Synchronize')
        @($rules | Where-Object { $_.IsInherited }).Count | Should -Be 0
        Test-TuneupTrustedItem -Path $Folder -TrustedSids @($MeSid) | Should -BeTrue
    }
}

Describe 'Base folder' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $Folder | Out-Null
    }

    It 'accepts the real CommonApplicationData folder' {
        Test-TuneupBaseFolder -Path ([Environment]::GetFolderPath('CommonApplicationData')) | Should -BeTrue
    }

    It 'rejects a real folder owned by a user' {
        Test-TuneupBaseFolder -Path $Folder | Should -BeFalse
    }

    It 'accepts the C:\ProgramData ACL owned by <Name>' -TestCases @(
        @{ Name = 'SYSTEM'; Owner = 'SY' }
        @{ Name = 'TrustedInstaller'; Owner = 'S-1-5-80-956008885-3425145150-2718476148-1766412592' }
        @{ Name = 'Administrators'; Owner = 'BA' }
    ) {
        # The default ACL of C:\ProgramData: CREATOR OWNER inherit-only full control and Users create/append.
        $security = New-SddlSecurity "O:${Owner}D:PAI(A;OICIIO;GA;;;CO)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)(A;CI;DCLCRPCR;;;BU)"
        Mock -ModuleName Tuneup Get-Acl { $security }
        Test-TuneupBaseFolder -Path $Folder | Should -BeTrue
    }

    It 'rejects a folder that grants <Name> to Users' -TestCases @(
        @{ Name = 'Delete'; Mask = '0x10000' }
        @{ Name = 'DeleteSubdirectoriesAndFiles'; Mask = '0x40' }
        @{ Name = 'ChangePermissions'; Mask = '0x40000' }
        @{ Name = 'TakeOwnership'; Mask = '0x80000' }
        @{ Name = 'GenericAll'; Mask = 'GA' }
    ) {
        $security = New-SddlSecurity "O:SYD:P(A;OICI;FA;;;SY)(A;;$Mask;;;BU)"
        Mock -ModuleName Tuneup Get-Acl { $security }
        Test-TuneupBaseFolder -Path $Folder | Should -BeFalse
    }

    It 'rejects a folder owned by a user even with a clean ACL' {
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        Test-TuneupBaseFolder -Path $Folder | Should -BeFalse
    }

    It 'rejects a junction' {
        $junction = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Junction -Path $junction -Value $Folder | Out-Null
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-18' }
        Test-TuneupBaseFolder -Path $junction | Should -BeFalse
    }
}

Describe 'State root initialization' {
    BeforeEach {
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'creates a missing machine folder and its runs folder with the ACL already in place' {
        Use-CurrentUserAsTrusted
        $root = New-TestMachineRoot
        Mock -ModuleName Tuneup Set-Acl { }
        Initialize-TuneupStateRoot -Path $root
        foreach ($path in $root, (Join-Path $root 'runs')) {
            $acl = Get-Acl -LiteralPath $path
            $acl.AreAccessRulesProtected | Should -BeTrue -Because $path
            $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $MeSid
            @(Get-TestAccessRule $acl | Where-Object { $_.IdentityReference.Value -eq 'S-1-3-4' }).Count | Should -Be 1
        }
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'refuses to create the machine folder in an untrusted base folder' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        $root = Join-Path $Folder 'windows-tuneup'
        { Initialize-TuneupStateRoot -Path $root } | Should -Throw -ExpectedMessage "Folder $Folder is not trusted to hold the machine state folder"
        Test-Path -LiteralPath $root | Should -BeFalse
    }

    It 're-applies the ACL to an existing folder owned by Administrators' {
        New-Item -ItemType Directory -Path (Join-Path $Folder 'runs') -Force | Out-Null
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        Mock -ModuleName Tuneup Set-Acl { }
        Initialize-TuneupStateRoot -Path $Folder
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'refuses an existing folder that someone else owns without touching it' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' } -ParameterFilter { $LiteralPath -eq $Folder }
        Mock -ModuleName Tuneup Set-Acl { }
        { Initialize-TuneupStateRoot -Path $Folder } | Should -Throw -ExpectedMessage "State folder $Folder is not trusted.*"
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'refuses a folder that someone else created first while it was being created' {
        Mock -ModuleName Tuneup New-TuneupSecureDirectory {
            New-Item -ItemType Directory -Path $Path | Out-Null
            throw 'Cannot create a file when that file already exists'
        }
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' } -ParameterFilter { $LiteralPath -eq $Folder }
        Mock -ModuleName Tuneup Set-Acl { }
        { Initialize-TuneupStateRoot -Path $Folder } | Should -Throw -ExpectedMessage "State folder $Folder is not trusted.*"
        Test-Path -LiteralPath $Folder | Should -BeTrue
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'refuses a machine folder that is a junction' {
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType Junction -Path $Folder -Value $target | Out-Null
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-32-544' }
        Mock -ModuleName Tuneup Set-Acl { }
        { Initialize-TuneupStateRoot -Path $Folder } | Should -Throw -ExpectedMessage '*is not trusted*'
        Should -Invoke Set-Acl -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Trust checks' {
    BeforeEach {
        $script:Item = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $Item | Out-Null
    }

    AfterEach {
        Reset-TestTrust
    }

    It 'trusts items owned by <Name>' -TestCases @(
        @{ Name = 'Administrators'; Sid = 'S-1-5-32-544' }
        @{ Name = 'SYSTEM'; Sid = 'S-1-5-18' }
    ) {
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity $Sid }
        Test-TuneupTrustedItem -Path $Item | Should -BeTrue
    }

    It 'does not trust items owned by a user' {
        Mock -ModuleName Tuneup Get-Acl { New-OwnedSecurity 'S-1-5-21-1000000000-2000000000-3000000000-1001' }
        Test-TuneupTrustedItem -Path $Item | Should -BeFalse
    }

    It 'does not trust items it cannot inspect' {
        Mock -ModuleName Tuneup Get-Acl { throw 'Access denied' }
        Test-TuneupTrustedItem -Path $Item | Should -BeFalse
        Test-TuneupTrustedItem -Path (Join-Path $Item 'missing') | Should -BeFalse
    }

    It 'does not trust a DACL that grants <Name> to another SID' -TestCases @(
        @{ Name = 'WriteData'; Mask = '0x2' }
        @{ Name = 'AppendData'; Mask = '0x4' }
        @{ Name = 'WriteExtendedAttributes'; Mask = '0x10' }
        @{ Name = 'DeleteSubdirectoriesAndFiles'; Mask = '0x40' }
        @{ Name = 'WriteAttributes'; Mask = '0x100' }
        @{ Name = 'Delete'; Mask = '0x10000' }
        @{ Name = 'ChangePermissions'; Mask = '0x40000' }
        @{ Name = 'TakeOwnership'; Mask = '0x80000' }
        @{ Name = 'GenericAll'; Mask = 'GA' }
        @{ Name = 'GenericWrite'; Mask = 'GW' }
    ) {
        $security = New-SddlSecurity "O:BAD:P(A;;FA;;;BA)(A;;0x1200a9;;;BU)(A;;$Mask;;;BU)"
        Test-TuneupTrustedSecurity -Security $security | Should -BeFalse
        Mock -ModuleName Tuneup Get-Acl { $security }
        Test-TuneupTrustedItem -Path $Item | Should -BeFalse
        $readOnly = New-SddlSecurity 'O:BAD:P(A;;FA;;;BA)(A;;0x1200a9;;;BU)(A;;GR;;;BU)'
        Test-TuneupTrustedSecurity -Security $readOnly | Should -BeTrue
    }

    It 'ignores deny entries and read-only grants' {
        Mock -ModuleName Tuneup Get-Acl {
            $security = New-OwnedSecurity 'S-1-5-32-544'
            Add-TestAccessRule -Security $security -Sid 'S-1-1-0' -Rights 'FullControl' -Type 'Deny' | Out-Null
            Add-TestAccessRule -Security $security -Sid 'S-1-5-32-545' -Rights 'ReadAndExecute' | Out-Null
            Add-TestAccessRule -Security $security -Sid 'S-1-5-32-544' -Rights 'FullControl'
        }
        Test-TuneupTrustedItem -Path $Item | Should -BeTrue
    }

    It 'does not trust a real folder once Everyone can write to it' {
        Set-TuneupStateSecurity -Path $Item -OwnerSid $MeSid -TrustedSids @($MeSid)
        Test-TuneupTrustedItem -Path $Item -TrustedSids @($MeSid) | Should -BeTrue
        Grant-EveryoneWrite $Item
        Test-TuneupTrustedItem -Path $Item -TrustedSids @($MeSid) | Should -BeFalse
    }

    It 'does not trust a real file with a second hard link' {
        Use-CurrentUserAsTrusted
        Set-TuneupStateSecurity -Path $Item
        $file = Join-Path $Item 'snapshot.jsonl'
        [System.IO.File]::WriteAllText($file, '')
        Test-TuneupTrustedItem -Path $file | Should -BeTrue
        New-Item -ItemType HardLink -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString())) -Value $file | Out-Null
        Test-TuneupTrustedItem -Path $file | Should -BeFalse
    }
}
