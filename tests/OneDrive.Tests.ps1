BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Tweak = New-TestTweak -Id 'apps.onedrive' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'onedrive' })
    $script:MeSid = Get-TestCurrentSid
    $script:OtherSid = 'S-1-5-21-1000000000-2000000000-3000000000-1001'
    function New-TestInstall([bool]$PerUser, [bool]$PerMachine, [string]$MachineSetup) {
        [pscustomobject]@{ perUser = $PerUser; perMachine = $PerMachine; machineSetup = $MachineSetup; version = '26.150.0804.0011' }
    }
    function New-TestScan([int]$Count = 0, [string]$First = $null, [int]$Errors = 0) {
        [pscustomobject]@{ count = $Count; firstFolder = $First; errors = $Errors }
    }
}

Describe 'onedrive action' {
    BeforeEach {
        # Nothing real is read, run or installed: every look at the system goes through a helper.
        $script:Setup = Join-Path $TestDrive 'OneDriveSetup.exe'
        $script:SystemSetup = Join-Path $TestDrive 'System32\OneDriveSetup.exe'
        New-Item -ItemType Directory -Path (Split-Path $SystemSetup) -Force | Out-Null
        Set-Content -LiteralPath $Setup -Value 'fake' -Encoding ASCII
        Set-Content -LiteralPath $SystemSetup -Value 'fake' -Encoding ASCII
        $script:Installs = @((New-TestInstall $false $true $Setup))
        $script:InstallCalls = 0
        Mock -ModuleName Tuneup Get-OnedriveActionHelperInstall {
            $index = [Math]::Min($script:InstallCalls, $script:Installs.Count - 1)
            $script:InstallCalls++
            $script:Installs[$index]
        }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperSystemSetup { $script:SystemSetup }
        Mock -ModuleName Tuneup Test-TuneupTrustedExecutable { $true }
        Mock -ModuleName Tuneup Get-TuneupSessionUserSid { $script:MeSid }
        Mock -ModuleName Tuneup Test-OnedriveActionHelperRedirected { $false }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperRoot { }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperProfileFolder { }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOnlineOnly { New-TestScan }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperProfileAtRisk { }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOtherProfile { 0 }
        Mock -ModuleName Tuneup Test-OnedriveActionHelperRunning { $false }
        Mock -ModuleName Tuneup Wait-OnedriveActionHelperRemoval { $true }
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = 0; Output = 'Successfully installed' } }
    }

    It 'is loaded from actions/ and passes the catalog check' {
        @(Get-TuneupActionLoadError | Where-Object { $_.name -eq 'onedrive' }).Count | Should -Be 0
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'is applied when no OneDrive.exe is installed, so leftovers do not count' {
        $script:Installs = @((New-TestInstall $false $false $null))
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        (Get-TuneupState -Tweak $Tweak).installed | Should -BeFalse
        (Get-TuneupState -Tweak $Tweak).currentUserSid | Should -BeNullOrEmpty
    }

    It 'saves whose OneDrive it is, so the undo of another account leaves it for its owner' {
        (Get-TuneupState -Tweak $Tweak).currentUserSid | Should -Be $MeSid
    }

    It 'uninstalls a per-machine OneDrive for all users with the setup next to it, once it is trusted' {
        $script:Installs = @((New-TestInstall $false $true $Setup), (New-TestInstall $false $false $null))
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $script:InstallCalls = 0
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.partial | Should -BeFalse
        $outcome.refused | Should -BeFalse
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $FilePath -eq $Setup -and ($Arguments -join ' ') -eq '/uninstall /allusers' }
        Should -Invoke Test-TuneupTrustedExecutable -ModuleName Tuneup -ParameterFilter { $Path -eq $Setup -and $StopAt -eq [Environment]::GetFolderPath('ProgramFiles') }
        Should -Invoke Wait-OnedriveActionHelperRemoval -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Flavour -eq 'perMachine' }
    }

    It 'uninstalls a per-user OneDrive with the setup of Windows, never one from the user''s folders' {
        $script:Installs = @((New-TestInstall $true $false $null), (New-TestInstall $false $false $null))
        Set-TuneupDesired -Tweak $Tweak | Out-Null
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $FilePath -eq $SystemSetup -and ($Arguments -join ' ') -eq '/uninstall' }
        Should -Invoke Test-TuneupTrustedExecutable -ModuleName Tuneup -ParameterFilter { $Path -eq $SystemSetup -and $StopAt -eq [Environment]::GetFolderPath('Windows') }
        Should -Invoke Wait-OnedriveActionHelperRemoval -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Flavour -eq 'perUser' }
        # Only the current account loses it: the other profiles are not checked.
        Should -Invoke Get-OnedriveActionHelperProfileAtRisk -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'removes both kinds of install, waiting for each one on its own' {
        $script:Installs = @((New-TestInstall $true $true $Setup), (New-TestInstall $false $false $null))
        Set-TuneupDesired -Tweak $Tweak | Out-Null
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 2 -Exactly
        Should -Invoke Wait-OnedriveActionHelperRemoval -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Flavour -eq 'perMachine' }
        Should -Invoke Wait-OnedriveActionHelperRemoval -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Flavour -eq 'perUser' }
    }

    It 'fails, without running anything, when the <Name> setup is not trusted' -TestCases @(
        @{ Name = 'per-machine'; PerUser = $false; PerMachine = $true }
        @{ Name = 'Windows'; PerUser = $true; PerMachine = $false }
        @{ Name = 'per-machine or the Windows'; PerUser = $true; PerMachine = $true }
    ) {
        param($PerUser, $PerMachine)
        $script:Installs = @((New-TestInstall $PerUser $PerMachine $Setup))
        Mock -ModuleName Tuneup Test-TuneupTrustedExecutable { $false }
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*not trusted*nothing was changed*'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'fails, without running anything, when the per-user setup of Windows is missing' {
        $script:Installs = @((New-TestInstall $true $true $Setup))
        Mock -ModuleName Tuneup Get-OnedriveActionHelperSystemSetup { }
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*OneDriveSetup.exe of Windows was not found*'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'fails, without running anything, when the per-machine setup is missing' {
        $script:Installs = @((New-TestInstall $false $true (Join-Path $TestDrive 'missing.exe')))
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*OneDriveSetup.exe was not found*'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'refuses, without running anything, when <Name>' -TestCases @(
        @{ Name = 'it runs as another account than the one at the desktop'; Reason = 'onedrive-session-user'; Session = @('S-1-5-21-1000000000-2000000000-3000000000-1001') }
        @{ Name = 'there is no desktop to compare with'; Reason = 'onedrive-session-user'; Session = @() }
        @{ Name = 'two accounts own the desktop'; Reason = 'onedrive-session-user'; Session = @('ME', 'S-1-5-21-1000000000-2000000000-3000000000-1001') }
        @{ Name = 'the desktop cannot be read'; Reason = 'onedrive-session-user'; Session = 'throw' }
        @{ Name = 'Known Folder Move is on'; Reason = 'onedrive-known-folders'; Redirected = $true }
        @{ Name = 'some file could not be listed'; Reason = 'onedrive-scan-incomplete'; Errors = 2 }
        @{ Name = 'the profile folder could not be listed'; Reason = 'onedrive-scan-incomplete'; FolderThrows = $true }
        @{ Name = 'there are online-only files'; Reason = 'onedrive-online-only-files'; Count = 3 }
        @{ Name = 'another account is at risk'; Reason = 'onedrive-other-accounts'; AtRisk = $true }
    ) {
        param($Reason, $Session, [bool]$Redirected, [int]$Errors, [int]$Count, [bool]$AtRisk, [bool]$FolderThrows)
        $script:Session = $(if ($null -eq $Session) { @($MeSid) } else { @($Session | ForEach-Object { $_ -replace '^ME$', $MeSid }) })
        $script:Redirected = $Redirected
        $script:Scan = New-TestScan -Count $Count -First 'Projects' -Errors $Errors
        $script:AtRisk = $AtRisk
        $script:FolderThrows = $FolderThrows
        Mock -ModuleName Tuneup Get-TuneupSessionUserSid { if ($script:Session -contains 'throw') { throw 'no access' }; $script:Session }
        Mock -ModuleName Tuneup Test-OnedriveActionHelperRedirected { $script:Redirected }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperProfileFolder { if ($script:FolderThrows) { throw 'Access denied' } }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOnlineOnly { $script:Scan }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperProfileAtRisk { if ($script:AtRisk) { [pscustomobject]@{ name = 'Ana'; why = 'signed-out' } } }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.refused | Should -BeTrue
        $outcome.reason | Should -Be $Reason
        $outcome.detail | Should -BeLike '*nothing was changed*'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'checks Known Folder Move and online-only files of the current account with its own roots' {
        Set-TuneupDesired -Tweak $Tweak | Out-Null
        Should -Invoke Test-OnedriveActionHelperRedirected -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $SoftwareKey -eq 'HKCU:\Software' -and $Environment -and $ProfilePath -eq [Environment]::GetFolderPath('UserProfile')
        }
        Should -Invoke Get-OnedriveActionHelperRoot -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $SoftwareKey -eq 'HKCU:\Software' -and $Environment }
    }

    It 'names only how many online-only items there are and the folder of the first one, never a path' {
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOnlineOnly { New-TestScan -Count 3 -First 'Projects' }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.detail | Should -BeLike "*holds 3 file(s) or folder(s)*'Projects'*"
        $outcome.detail | Should -Not -BeLike '*:\*'
    }

    It 'has a text for each refusal and for the reinstall in both languages' {
        foreach ($lang in 'es', 'en') {
            Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang $lang
            foreach ($reason in 'onedrive-known-folders', 'onedrive-online-only-files', 'onedrive-scan-incomplete', 'onedrive-other-accounts',
                'onedrive-session-user', 'reinstalled-onedrive') {
                Get-TuneupText -Key "reason.$reason" | Should -Not -Be "reason.$reason"
            }
        }
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
        Get-TuneupText -Key 'reason.reinstalled-onedrive' | Should -Not -BeLike '*Store*'
    }

    It 'is partial when OneDrive is gone here but other accounts keep their own' {
        $script:Installs = @((New-TestInstall $false $true $Setup), (New-TestInstall $false $false $null))
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOtherProfile { 2 }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*2 other account(s)*'
    }

    It 'fails when the setup could not remove it' {
        $script:Installs = @((New-TestInstall $false $true $Setup))
        Mock -ModuleName Tuneup Wait-OnedriveActionHelperRemoval { $false }
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 5; Output = 'Access is denied' } }
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*ended with code 5*'
    }

    It 'fails when the setup ends well but OneDrive is still there after waiting' {
        $script:Installs = @((New-TestInstall $false $true $Setup))
        Mock -ModuleName Tuneup Wait-OnedriveActionHelperRemoval { $false }
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*ended with code 0 and the OneDrive for all users was still installed after waiting*'
    }

    It 'is partial when one kind of install is gone and the other is still there after waiting' {
        $script:Installs = @((New-TestInstall $true $true $Setup), (New-TestInstall $true $false $null))
        Mock -ModuleName Tuneup Wait-OnedriveActionHelperRemoval { $Flavour -eq 'perMachine' }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*the OneDrive of this account was still installed after waiting*'
    }

    It 'says that OneDrive was running and its setup closed it' {
        $script:Installs = @((New-TestInstall $false $true $Setup), (New-TestInstall $false $false $null))
        Mock -ModuleName Tuneup Test-OnedriveActionHelperRunning { $true }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.partial | Should -BeFalse
        $outcome.detail | Should -BeLike '*was running*'
    }

    It 'reinstalls it for all users on undo when it was per-machine' {
        $script:Installs = @((New-TestInstall $false $false $null), (New-TestInstall $false $true $Setup))
        $state = [pscustomobject]@{ installed = $true; perUser = $false; perMachine = $true; version = '26.1' }
        $outcome = Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'reinstalled-onedrive'
        $outcome.detail | Should -Not -BeLike '*could not be confirmed*'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join ' ') -eq 'install --id Microsoft.OneDrive --source winget --exact --no-upgrade --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --override /silent /allusers'
        }
    }

    It 'reinstalls it for the current user on undo when it was per-user' {
        $script:Installs = @((New-TestInstall $false $false $null))
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) | Out-Null
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -notlike '*--override*' }
    }

    It 'gives back both kinds of install on undo, and says which one it could not confirm' {
        $script:Installs = @((New-TestInstall $false $false $null), (New-TestInstall $false $true $Setup))
        $script:WingetCalls = New-Object System.Collections.Generic.List[string]
        Mock -ModuleName Tuneup Invoke-TuneupWinget { $script:WingetCalls.Add(($Arguments -join ' ')); [pscustomobject]@{ ExitCode = 0; Output = '' } }
        $outcome = Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $true; version = '26.1' }))
        $WingetCalls.Count | Should -Be 2
        $WingetCalls[0] | Should -BeLike '*--override /silent /allusers'
        $WingetCalls[1] | Should -Not -BeLike '*--override*'
        $outcome.detail | Should -BeLike '*OneDrive for this account could not be confirmed*'
    }

    It 'gives back on undo only the kind of install that is missing' {
        $script:Installs = @((New-TestInstall $false $true $Setup))
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $true; version = '26.1' }) | Out-Null
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -notlike '*--override*' }
    }

    It 'does nothing on undo if it was not installed or is installed again' {
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $false; perUser = $false; perMachine = $false; version = $null }) | Out-Null
        $script:Installs = @((New-TestInstall $true $false $null))
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) | Out-Null
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'fails the undo with the way to install it by hand when winget fails' {
        $script:Installs = @((New-TestInstall $false $false $null))
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = -1978335212; Output = 'No package found' } }
        { Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) } |
            Should -Throw '*winget install --id Microsoft.OneDrive*'
    }
}

Describe 'onedrive install detection' {
    It 'reads the folders from Windows, not from environment variables that a user can set' {
        $expected = & (Get-Module Tuneup) { Get-OnedriveActionHelperInstall } | ConvertTo-Json -Compress
        $fake = Join-Path $TestDrive 'fake'
        New-Item -ItemType Directory -Path (Join-Path $fake 'Microsoft\OneDrive'), (Join-Path $fake 'Microsoft OneDrive') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fake 'Microsoft\OneDrive\OneDrive.exe') -Value 'fake'
        Set-Content -LiteralPath (Join-Path $fake 'Microsoft OneDrive\OneDrive.exe') -Value 'fake'
        $saved = @{ LOCALAPPDATA = $env:LOCALAPPDATA; ProgramFiles = $env:ProgramFiles }
        try {
            $env:LOCALAPPDATA = $fake
            $env:ProgramFiles = $fake
            & (Get-Module Tuneup) { Get-OnedriveActionHelperInstall } | ConvertTo-Json -Compress | Should -Be $expected
        } finally {
            $env:LOCALAPPDATA = $saved.LOCALAPPDATA
            $env:ProgramFiles = $saved.ProgramFiles
        }
    }

    It 'takes the setup with the highest version, compared as versions and not as text' {
        $files = @(
            [pscustomobject]@{ FullName = 'C:\a\9.0.0.0\OneDriveSetup.exe'; VersionInfo = [pscustomobject]@{ FileVersion = '9.0.0.0' } }
            [pscustomobject]@{ FullName = 'C:\a\10.0.0.0\OneDriveSetup.exe'; VersionInfo = [pscustomobject]@{ FileVersion = '10.0.0.0' } }
            [pscustomobject]@{ FullName = 'C:\a\bad\OneDriveSetup.exe'; VersionInfo = [pscustomobject]@{ FileVersion = 'n/a' } }
        )
        (& (Get-Module Tuneup) { param($f) Get-OnedriveActionHelperNewest -File $f } $files).FullName | Should -Be 'C:\a\10.0.0.0\OneDriveSetup.exe'
    }

    It 'points at the OneDriveSetup.exe of Windows' {
        $setup = & (Get-Module Tuneup) { Get-OnedriveActionHelperSystemSetup }
        if ($setup) {
            @((Join-Path ([Environment]::GetFolderPath('System')) 'OneDriveSetup.exe'), (Join-Path ([Environment]::GetFolderPath('SystemX86')) 'OneDriveSetup.exe')) | Should -Contain $setup
        }
    }

    It 'reads the accounts of this PC without changing anything' {
        foreach ($account in @(& (Get-Module Tuneup) { Get-OnedriveActionHelperProfile })) {
            $account.sid | Should -Not -Be $MeSid
            $account.sid | Should -Match '^S-1-(5-21|12-1)-'
            $account.path | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'onedrive detection helpers' {
    BeforeAll {
        # Not $Root: a test that names a folder $root would replace it in AfterEach, which shares its scope.
        $script:RegistryRoot = 'HKCU:\Software\windows-tuneup-test'
        $script:Software = "$RegistryRoot\od"
        $script:ShellFolders = "$Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
        $script:Account = "$Software\Microsoft\OneDrive\Accounts\Business1"
        function Set-TestShellFolder([string]$Name, [string]$Value) {
            if (-not (Test-Path -LiteralPath $ShellFolders)) { New-Item -Path $ShellFolders -Force | Out-Null }
            New-ItemProperty -LiteralPath $ShellFolders -Name $Name -PropertyType ExpandString -Value $Value -Force | Out-Null
        }
    }

    BeforeEach {
        Mock -ModuleName Tuneup Get-OnedriveActionHelperEnvironmentRoot { }
    }

    AfterEach {
        if (Test-Path -LiteralPath $RegistryRoot) { Remove-Item -LiteralPath $RegistryRoot -Recurse -Force }
    }

    It 'sees Known Folder Move under a OneDrive folder and not under the local profile' {
        Mock -ModuleName Tuneup Get-OnedriveActionHelperRoot { 'C:\Users\me\OneDrive - Contoso' }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperKnownFolder { 'C:\Users\me\Desktop', 'C:\Users\me\OneDrive - Contoso\Documents' }
        & (Get-Module Tuneup) { Test-OnedriveActionHelperRedirected } | Should -BeTrue
        Mock -ModuleName Tuneup Get-OnedriveActionHelperKnownFolder { 'C:\Users\me\Desktop', 'C:\Users\me\Documents' }
        & (Get-Module Tuneup) { Test-OnedriveActionHelperRedirected } | Should -BeFalse
    }

    It 'sees Known Folder Move by <Name> alone' -TestCases @(
        @{ Name = 'a folder named OneDrive'; Folder = 'D:\Data\OneDrive\Music'; Kind = 'none' }
        @{ Name = 'a OneDrive root announced to the account'; Folder = 'D:\Sync\Docs'; Kind = 'environment' }
        @{ Name = 'the UserFolder of an account'; Folder = 'E:\Corp\Desk'; Kind = 'userfolder' }
        @{ Name = 'a SharePoint library synced outside the root'; Folder = 'F:\Contoso\Site - Docs\Fav'; Kind = 'tenant' }
    ) {
        param($Folder, $Kind)
        Set-TestShellFolder -Name 'My Music' -Value $Folder
        if ($Kind -eq 'environment') { Mock -ModuleName Tuneup Get-OnedriveActionHelperEnvironmentRoot { 'D:\Sync' } }
        if ($Kind -eq 'userfolder') {
            New-Item -Path $Account -Force | Out-Null
            New-ItemProperty -LiteralPath $Account -Name 'UserFolder' -Value 'E:\Corp' | Out-Null
        }
        if ($Kind -eq 'tenant') {
            New-Item -Path "$Account\Tenants\Contoso" -Force | Out-Null
            New-ItemProperty -LiteralPath "$Account\Tenants\Contoso" -Name 'F:\Contoso\Site - Docs' -Value '' | Out-Null
        }
        $test = { param($s, $e) Test-OnedriveActionHelperRedirected -SoftwareKey $s -ProfilePath 'C:\Users\me' -Environment:$e }
        & (Get-Module Tuneup) $test $Software $true | Should -BeTrue
        # Without the source that names the root, the same folder is a normal one.
        if ($Kind -eq 'environment') { & (Get-Module Tuneup) $test $Software $false | Should -BeFalse }
        if ($Kind -in 'userfolder', 'tenant') {
            Remove-Item -LiteralPath "$Software\Microsoft\OneDrive" -Recurse -Force
            & (Get-Module Tuneup) $test $Software $true | Should -BeFalse
        }
    }

    It 'reads every shell folder, with %USERPROFILE% as the profile of that account' {
        Set-TestShellFolder -Name 'Favorites' -Value '%USERPROFILE%\Favorites'
        Set-TestShellFolder -Name '{374DE290-123F-4565-9164-39C4925E467B}' -Value '%USERPROFILE%\Downloads'
        $folders = @(& (Get-Module Tuneup) { param($s) Get-OnedriveActionHelperKnownFolder -SoftwareKey $s -ProfilePath 'C:\Users\other' } $Software)
        $folders | Should -Contain 'C:\Users\other\Favorites'
        $folders | Should -Contain 'C:\Users\other\Downloads'
    }

    It 'treats <Name> as only in the cloud' -TestCases @(
        @{ Name = 'RECALL_ON_DATA_ACCESS'; Attributes = 0x400000; Expected = $true }
        @{ Name = 'RECALL_ON_OPEN'; Attributes = 0x40000; Expected = $true }
        @{ Name = 'OFFLINE'; Attributes = 0x1000; Expected = $true }
        @{ Name = 'a pinned file'; Attributes = 0x80020; Expected = $false }
        @{ Name = 'a reparse point'; Attributes = 0x420; Expected = $false }
    ) {
        param($Attributes, $Expected)
        & (Get-Module Tuneup) { param($a) Test-OnedriveActionHelperCloudAttribute -Attributes $a } $Attributes | Should -Be $Expected
    }

    It 'finds an online-only file and a folder placeholder, and names only the folder that holds it' {
        $root = Join-Path $TestDrive 'OneDrive'
        New-Item -ItemType Directory -Path (Join-Path $root 'sub') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'local.txt') -Value 'x'
        $scan = & (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } $root
        "$($scan.count)/$($scan.errors)" | Should -Be '0/0'
        $cloud = Join-Path $root 'sub\cloud.txt'
        Set-Content -LiteralPath $cloud -Value 'x'
        # OFFLINE (0x1000) is one of the attributes of an online-only placeholder.
        (Get-Item -LiteralPath $cloud).Attributes = [System.IO.FileAttributes]::Offline
        $scan = & (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } $root
        "$($scan.count)/$($scan.firstFolder)/$($scan.errors)" | Should -Be '1/sub/0'
        $folder = Join-Path $root 'Shared'
        New-Item -ItemType Directory -Path $folder | Out-Null
        (Get-Item -LiteralPath $folder).Attributes = 'Directory, Offline'
        (& (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } $root).count | Should -Be 2
    }

    It 'reaches paths longer than 260 characters' {
        $root = Join-Path $TestDrive 'Deep'
        $deep = "\\?\$root\" + ('a' * 120) + '\' + ('b' * 120)
        [System.IO.Directory]::CreateDirectory($deep) | Out-Null
        try {
            [System.IO.File]::WriteAllText("$deep\cloud.txt", 'x')
            (Get-Item -LiteralPath "$deep\cloud.txt").Attributes = [System.IO.FileAttributes]::Offline
            $scan = & (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } $root
            "$($scan.count)/$($scan.firstFolder)/$($scan.errors)" | Should -Be "1/$('a' * 120)/0"
        } finally {
            # The test drive is removed without \\?\, which cannot reach this folder.
            [System.IO.Directory]::Delete("\\?\$root", $true)
        }
    }

    It 'counts what it could not list, so the check fails closed' {
        $root = Join-Path $TestDrive 'Locked'
        $locked = Join-Path $root 'Private'
        New-Item -ItemType Directory -Path $locked -Force | Out-Null
        # A folder that the account cannot list: what is inside is never seen, so it cannot be cleared.
        $acl = Get-Acl -LiteralPath $locked
        $deny = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $MeSid), 'ListDirectory', 'None', 'None', 'Deny')
        $acl.AddAccessRule($deny)
        $acl.SetAuditRuleProtection($acl.AreAccessRulesProtected, $true)
        Set-Acl -LiteralPath $locked -AclObject $acl
        try {
            (& (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } $root).errors | Should -Be 1
        } finally {
            $acl = Get-Acl -LiteralPath $locked
            [void]$acl.RemoveAccessRule($deny)
            $acl.SetAuditRuleProtection($acl.AreAccessRulesProtected, $true)
            Set-Acl -LiteralPath $locked -AclObject $acl
        }
        Mock -ModuleName Tuneup Get-Item { throw 'Access to the path is denied.' }
        (& (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } $root).errors | Should -Be 1
    }

    It 'does not skip an online-only file behind a junction: it counts it as not checked' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $root, $target | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'cloud.txt') -Value 'x'
        (Get-Item -LiteralPath (Join-Path $target 'cloud.txt')).Attributes = [System.IO.FileAttributes]::Offline
        New-Item -ItemType Junction -Path (Join-Path $root 'Linked') -Value $target | Out-Null
        $scan = & (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } $root
        $scan.errors | Should -BeGreaterThan 0
    }

    It 'walks into a reparse folder that is not a link, as OneDrive keeps its folders' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $root, $target | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'cloud.txt') -Value 'x'
        (Get-Item -LiteralPath (Join-Path $target 'cloud.txt')).Attributes = [System.IO.FileAttributes]::Offline
        New-Item -ItemType Junction -Path (Join-Path $root 'Synced') -Value $target | Out-Null
        # A cloud files reparse point is neither a junction nor a symbolic link.
        Mock -ModuleName Tuneup Get-OnedriveActionHelperLinkType { $null }
        $scan = & (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } $root
        "$($scan.count)/$($scan.firstFolder)/$($scan.errors)" | Should -Be '1/Synced/0'
    }

    It 'finds an online-only file deep in nested folders' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $deep = Join-Path $root 'Top\a\b\c\d\e\f\g\h'
        New-Item -ItemType Directory -Path $deep -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $deep 'cloud.txt') -Value 'x'
        (Get-Item -LiteralPath (Join-Path $deep 'cloud.txt')).Attributes = [System.IO.FileAttributes]::Offline
        $scan = & (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } $root
        "$($scan.count)/$($scan.firstFolder)/$($scan.errors)" | Should -Be '1/Top/0'
    }

    It 'reads the OneDrive sync roots of every account from the machine registry' {
        $key = "$RegistryRoot\SyncRootManager"
        New-Item -Path "$key\OneDrive!S-1-5-21-1-1-1-1001!Personal|1\UserSyncRoots" -Force | Out-Null
        New-ItemProperty -LiteralPath "$key\OneDrive!S-1-5-21-1-1-1-1001!Personal|1\UserSyncRoots" -Name 'S-1-5-21-1-1-1-1001' -Value 'D:\Ana\OneDrive' | Out-Null
        New-Item -Path "$key\OneDrive!S-1-5-21-1-1-1-1002!Business1|Contoso\UserSyncRoots" -Force | Out-Null
        New-ItemProperty -LiteralPath "$key\OneDrive!S-1-5-21-1-1-1-1002!Business1|Contoso\UserSyncRoots" -Name 'S-1-5-21-1-1-1-1002' -Value 'D:\Beto\Contoso' | Out-Null
        # Other sync providers are not removed with OneDrive.
        New-Item -Path "$key\Dropbox!S-1-5-21-1-1-1-1001!Personal\UserSyncRoots" -Force | Out-Null
        New-ItemProperty -LiteralPath "$key\Dropbox!S-1-5-21-1-1-1-1001!Personal\UserSyncRoots" -Name 'S-1-5-21-1-1-1-1001' -Value 'D:\Ana\Dropbox' | Out-Null
        $roots = @(& (Get-Module Tuneup) { param($k) Get-OnedriveActionHelperSyncRoot -Key $k } $key)
        ($roots | Sort-Object sid | ForEach-Object { "$($_.sid)=$($_.path)" }) -join ',' | Should -Be 'S-1-5-21-1-1-1-1001=D:\Ana\OneDrive,S-1-5-21-1-1-1-1002=D:\Beto\Contoso'
        @(& (Get-Module Tuneup) { param($k) Get-OnedriveActionHelperSyncRoot -Key $k } "$RegistryRoot\missing").Count | Should -Be 0
    }

    It 'sees the risk of a signed-out account in its sync roots: <Name>' -TestCases @(
        @{ Name = 'a root with files'; Content = $true; Expected = 'signed-out' }
        @{ Name = 'an empty root'; Content = $false; Expected = $null }
        @{ Name = 'a root it cannot read'; Throws = $true; Expected = 'unreadable' }
    ) {
        param([bool]$Content, [bool]$Throws, $Expected)
        $profilePath = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $syncRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $profilePath, $syncRoot | Out-Null
        if ($Content) { Set-Content -LiteralPath (Join-Path $syncRoot 'a.txt') -Value 'x' }
        $script:SyncRoot = $syncRoot
        Mock -ModuleName Tuneup Get-OnedriveActionHelperSyncRoot {
            [pscustomobject]@{ sid = $OtherSid; path = $script:SyncRoot }
            [pscustomobject]@{ sid = 'S-1-5-21-9-9-9-9'; path = 'C:\Windows' }
        }
        if ($Throws) { Mock -ModuleName Tuneup Test-OnedriveActionHelperNonEmpty { throw 'Access denied' } }
        $account = [pscustomobject]@{ sid = $OtherSid; name = 'Ana'; path = $profilePath; software = $null }
        & (Get-Module Tuneup) { param($a) Get-OnedriveActionHelperProfileRisk -Account $a } $account | Should -Be $Expected
    }

    It 'expands a profile path with the folders of Windows, not the variables of the process' {
        $windows = [Environment]::GetFolderPath('Windows')
        $drive = [System.IO.Path]::GetPathRoot($windows).TrimEnd('\')
        $saved = $env:SystemDrive
        try {
            $env:SystemDrive = 'Z:'
            & (Get-Module Tuneup) { Get-OnedriveActionHelperProfilePath -Raw '%SystemDrive%\Perfiles\Ana' } | Should -Be "$drive\Perfiles\Ana"
            & (Get-Module Tuneup) { Get-OnedriveActionHelperProfilePath -Raw '%systemroot%\ServiceProfiles\x' } | Should -Be "$windows\ServiceProfiles\x"
        } finally {
            $env:SystemDrive = $saved
        }
        # A variable it does not know is left as it is, and that profile cannot be checked.
        $account = [pscustomobject]@{ sid = $OtherSid; name = 'Ana'; path = '%OTHER%\Ana'; software = $null }
        & (Get-Module Tuneup) { param($a) Get-OnedriveActionHelperProfileRisk -Account $a } $account | Should -Be 'unreadable'
    }

    It 'counts other accounts with their own OneDrive wherever their profile is' {
        $profilePath = Join-Path $TestDrive 'Perfiles\Ana'
        New-Item -ItemType Directory -Path (Join-Path $profilePath 'AppData\Local\Microsoft\OneDrive') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profilePath 'AppData\Local\Microsoft\OneDrive\OneDrive.exe') -Value 'fake'
        $script:ProfilePath = $profilePath
        Mock -ModuleName Tuneup Get-OnedriveActionHelperProfile { [pscustomobject]@{ sid = $OtherSid; name = 'Ana'; path = $script:ProfilePath; software = $null } }
        & (Get-Module Tuneup) { Get-OnedriveActionHelperOtherProfile } | Should -Be 1
    }

    It 'skips a root that does not exist' {
        $scan = & (Get-Module Tuneup) { param($r) Get-OnedriveActionHelperOnlineOnly -Root $r } (Join-Path $TestDrive 'missing')
        "$($scan.count)/$($scan.errors)" | Should -Be '0/0'
    }

    It 'names the root for an item right at the root' {
        & (Get-Module Tuneup) { Get-OnedriveActionHelperTopFolder -Root 'C:\Users\me\OneDrive' -Path 'C:\Users\me\OneDrive\a.txt' } | Should -Be 'OneDrive'
        & (Get-Module Tuneup) { Get-OnedriveActionHelperTopFolder -Root 'C:\Users\me\OneDrive' -Path 'C:\Users\me\OneDrive\Fotos' -Folder } | Should -Be 'Fotos'
    }

    It 'stops waiting as soon as the kind of install it waits for is gone' {
        Mock -ModuleName Tuneup Get-OnedriveActionHelperInstall { New-TestInstall $true $false $null }
        Mock -ModuleName Tuneup Start-Sleep { }
        & (Get-Module Tuneup) { Wait-OnedriveActionHelperRemoval -Flavour 'perMachine' -Seconds 5 } | Should -BeTrue
        Should -Invoke Start-Sleep -ModuleName Tuneup -Times 0 -Exactly
        & (Get-Module Tuneup) { Wait-OnedriveActionHelperRemoval -Flavour 'perUser' -Seconds 0 } | Should -BeFalse
    }

    It 'sees the risk of another account: <Name>' -TestCases @(
        @{ Name = 'signed out with files in OneDrive'; Loaded = $false; File = $true; Expected = 'signed-out' }
        @{ Name = 'signed out with an empty OneDrive folder'; Loaded = $false; File = $false; Expected = $null }
        @{ Name = 'signed in with Known Folder Move'; Loaded = $true; Kfm = $true; Expected = 'known-folders' }
        @{ Name = 'signed in with an online-only file'; Loaded = $true; Offline = $true; File = $true; Expected = 'online-only' }
        @{ Name = 'signed in with local files only'; Loaded = $true; File = $true; Expected = $null }
    ) {
        param([bool]$Loaded, [bool]$File, [bool]$Kfm, [bool]$Offline, $Expected)
        $profilePath = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $oneDrive = Join-Path $profilePath 'OneDrive - Contoso'
        New-Item -ItemType Directory -Path $oneDrive -Force | Out-Null
        if ($File) {
            Set-Content -LiteralPath (Join-Path $oneDrive 'a.txt') -Value 'x'
            if ($Offline) { (Get-Item -LiteralPath (Join-Path $oneDrive 'a.txt')).Attributes = [System.IO.FileAttributes]::Offline }
        }
        if ($Kfm) { Set-TestShellFolder -Name 'Personal' -Value '%USERPROFILE%\OneDrive - Contoso\Documents' }
        if (-not (Test-Path -LiteralPath $Software)) { New-Item -Path $Software -Force | Out-Null }
        $account = [pscustomobject]@{ sid = $OtherSid; name = 'Ana'; path = $profilePath; software = $(if ($Loaded) { $Software } else { $null }) }
        & (Get-Module Tuneup) { param($a) Get-OnedriveActionHelperProfileRisk -Account $a } $account | Should -Be $Expected
    }

    It 'treats a profile it cannot read as a risk' {
        $profilePath = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $profilePath | Out-Null
        Mock -ModuleName Tuneup Get-OnedriveActionHelperProfileFolder { throw 'Access denied' }
        & (Get-Module Tuneup) { param($p) Get-OnedriveActionHelperProfileRisk -Account ([pscustomobject]@{ sid = 'x'; name = 'Ana'; path = $p; software = $null }) } $profilePath |
            Should -Be 'unreadable'
    }

    It 'lists every other account at risk' {
        Mock -ModuleName Tuneup Get-OnedriveActionHelperProfile {
            [pscustomobject]@{ sid = 'a'; name = 'Ana'; path = 'C:\Users\Ana'; software = $null }
            [pscustomobject]@{ sid = 'b'; name = 'Beto'; path = 'C:\Users\Beto'; software = $null }
        }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperProfileRisk { if ($Account.name -eq 'Beto') { 'signed-out' } }
        $risk = @(& (Get-Module Tuneup) { Get-OnedriveActionHelperProfileAtRisk })
        ($risk | ForEach-Object { "$($_.name):$($_.why)" }) -join ',' | Should -Be 'Beto:signed-out'
    }
}
