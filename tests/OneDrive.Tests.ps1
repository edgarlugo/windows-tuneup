BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Tweak = New-TestTweak -Id 'apps.onedrive' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'onedrive' })
    function New-TestInstall([bool]$PerUser, [bool]$PerMachine, [string]$MachineSetup) {
        [pscustomobject]@{ perUser = $PerUser; perMachine = $PerMachine; machineSetup = $MachineSetup; version = '26.150.0804.0011' }
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
        Mock -ModuleName Tuneup Test-OnedriveActionHelperRedirected { $false }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOnlineOnly { }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOtherProfile { 0 }
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
    }

    It 'uninstalls a per-user OneDrive with the setup of Windows, never one from the user''s folders' {
        $script:Installs = @((New-TestInstall $true $false $null), (New-TestInstall $false $false $null))
        Set-TuneupDesired -Tweak $Tweak | Out-Null
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $FilePath -eq $SystemSetup -and ($Arguments -join ' ') -eq '/uninstall' }
        Should -Invoke Test-TuneupTrustedExecutable -ModuleName Tuneup -ParameterFilter { $Path -eq $SystemSetup -and $StopAt -eq [Environment]::GetFolderPath('Windows') }
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

    It 'refuses, without running anything, when <Name>' -TestCases @(
        @{ Name = 'Known Folder Move is on'; Reason = 'onedrive-known-folders'; Redirected = $true; OnlineOnly = $null }
        @{ Name = 'there are online-only files'; Reason = 'onedrive-online-only-files'; Redirected = $false; OnlineOnly = 'C:\Users\me\OneDrive\notes.docx' }
    ) {
        param($Reason, $Redirected, $OnlineOnly)
        $script:Redirected = $Redirected
        $script:OnlineOnly = $OnlineOnly
        Mock -ModuleName Tuneup Test-OnedriveActionHelperRedirected { $script:Redirected }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOnlineOnly { $script:OnlineOnly }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.refused | Should -BeTrue
        $outcome.reason | Should -Be $Reason
        $outcome.detail | Should -BeLike '*nothing was changed*'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'has a text for each refusal in both languages' {
        foreach ($lang in 'es', 'en') {
            Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang $lang
            foreach ($reason in 'onedrive-known-folders', 'onedrive-online-only-files') {
                Get-TuneupText -Key "reason.$reason" | Should -Not -Be "reason.$reason"
            }
        }
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
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

    It 'fails, without running anything, when the per-machine setup is missing' {
        $script:Installs = @((New-TestInstall $false $true (Join-Path $TestDrive 'missing.exe')))
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*OneDriveSetup.exe was not found*'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'reinstalls it for all users on undo when it was per-machine' {
        $script:Installs = @((New-TestInstall $false $false $null))
        $state = [pscustomobject]@{ installed = $true; perUser = $false; perMachine = $true; version = '26.1' }
        $outcome = Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'reinstalled'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join ' ') -eq 'install --id Microsoft.OneDrive --source winget --exact --no-upgrade --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --override /silent /allusers'
        }
    }

    It 'reinstalls it for the current user on undo when it was per-user' {
        $script:Installs = @((New-TestInstall $false $false $null))
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) | Out-Null
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
}

Describe 'onedrive detection helpers' {
    It 'sees Known Folder Move under a OneDrive folder and not under the local profile' {
        Mock -ModuleName Tuneup Get-OnedriveActionHelperRoot { 'C:\Users\me\OneDrive - Contoso' }
        Mock -ModuleName Tuneup Get-OnedriveActionHelperKnownFolder { 'C:\Users\me\Desktop', 'C:\Users\me\OneDrive - Contoso\Documents' }
        & (Get-Module Tuneup) { Test-OnedriveActionHelperRedirected } | Should -BeTrue
        Mock -ModuleName Tuneup Get-OnedriveActionHelperKnownFolder { 'C:\Users\me\Desktop', 'C:\Users\me\Documents' }
        & (Get-Module Tuneup) { Test-OnedriveActionHelperRedirected } | Should -BeFalse
    }

    It 'finds an online-only file by its attributes and ignores a normal one' {
        $root = Join-Path $TestDrive 'OneDrive'
        New-Item -ItemType Directory -Path (Join-Path $root 'sub') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'local.txt') -Value 'x'
        Mock -ModuleName Tuneup Get-OnedriveActionHelperRoot { $root }
        & (Get-Module Tuneup) { Get-OnedriveActionHelperOnlineOnly } | Should -BeNullOrEmpty
        $cloud = Join-Path $root 'sub\cloud.txt'
        Set-Content -LiteralPath $cloud -Value 'x'
        # OFFLINE (0x1000) is one of the attributes of an online-only placeholder.
        (Get-Item -LiteralPath $cloud).Attributes = [System.IO.FileAttributes]::Offline
        & (Get-Module Tuneup) { Get-OnedriveActionHelperOnlineOnly } | Should -Be $cloud
    }

    It 'stops waiting as soon as OneDrive.exe is gone' {
        Mock -ModuleName Tuneup Get-OnedriveActionHelperInstall { New-TestInstall $false $false $null }
        Mock -ModuleName Tuneup Start-Sleep { }
        & (Get-Module Tuneup) { Wait-OnedriveActionHelperRemoval -Seconds 5 } | Should -BeTrue
        Should -Invoke Start-Sleep -ModuleName Tuneup -Times 0 -Exactly
    }
}
