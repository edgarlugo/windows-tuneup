BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:Tweak = New-TestTweak -Id 'apps.onedrive' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'onedrive' })
    function New-TestInstall([bool]$PerUser, [bool]$PerMachine, [string]$UserSetup, [string]$MachineSetup) {
        [pscustomobject]@{ perUser = $PerUser; perMachine = $PerMachine; userSetup = $UserSetup; machineSetup = $MachineSetup; version = '26.150.0804.0011' }
    }
}

Describe 'onedrive action' {
    BeforeEach {
        # Nothing real is read, run or installed: every look at the system goes through a helper.
        $script:Setup = Join-Path $TestDrive 'OneDriveSetup.exe'
        Set-Content -LiteralPath $Setup -Value 'fake' -Encoding ASCII
        $script:Installs = @((New-TestInstall $false $true $null $Setup))
        $script:InstallCalls = 0
        Mock -ModuleName Tuneup Get-OnedriveActionHelperInstall {
            $index = [Math]::Min($script:InstallCalls, $script:Installs.Count - 1)
            $script:InstallCalls++
            $script:Installs[$index]
        }
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
        $script:Installs = @((New-TestInstall $false $false $null $null))
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        (Get-TuneupState -Tweak $Tweak).installed | Should -BeFalse
    }

    It 'uninstalls a per-machine OneDrive for all users with the setup next to it' {
        $script:Installs = @((New-TestInstall $false $true $null $Setup), (New-TestInstall $false $false $null $null))
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $script:InstallCalls = 0
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.partial | Should -BeFalse
        $outcome.refused | Should -BeFalse
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $FilePath -eq $Setup -and ($Arguments -join ' ') -eq '/uninstall /allusers' }
    }

    It 'uninstalls a per-user OneDrive without /allusers' {
        $script:Installs = @((New-TestInstall $true $false $Setup $null), (New-TestInstall $false $false $null $null))
        Set-TuneupDesired -Tweak $Tweak | Out-Null
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq '/uninstall' }
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
        $script:Installs = @((New-TestInstall $false $true $null $Setup), (New-TestInstall $false $false $null $null))
        Mock -ModuleName Tuneup Get-OnedriveActionHelperOtherProfile { 2 }
        $outcome = Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*2 other account(s)*'
    }

    It 'fails when the setup could not remove it' {
        $script:Installs = @((New-TestInstall $false $true $null $Setup))
        Mock -ModuleName Tuneup Wait-OnedriveActionHelperRemoval { $false }
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 5; Output = 'Access is denied' } }
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*ended with code 5*'
    }

    It 'fails, without running anything, when the setup is missing' {
        $script:Installs = @((New-TestInstall $false $true $null (Join-Path $TestDrive 'missing.exe')))
        { Set-TuneupDesired -Tweak $Tweak } | Should -Throw '*OneDriveSetup.exe was not found*'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'reinstalls it for all users on undo when it was per-machine' {
        $script:Installs = @((New-TestInstall $false $false $null $null))
        $state = [pscustomobject]@{ installed = $true; perUser = $false; perMachine = $true; version = '26.1' }
        $outcome = Get-TuneupOutcome -Output @(Restore-TuneupState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'reinstalled'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join ' ') -eq 'install --id Microsoft.OneDrive --source winget --exact --no-upgrade --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --override /silent /allusers'
        }
    }

    It 'reinstalls it for the current user on undo when it was per-user' {
        $script:Installs = @((New-TestInstall $false $false $null $null))
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) | Out-Null
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -notlike '*--override*' }
    }

    It 'does nothing on undo if it was not installed or is installed again' {
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $false; perUser = $false; perMachine = $false; version = $null }) | Out-Null
        $script:Installs = @((New-TestInstall $true $false $Setup $null))
        Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) | Out-Null
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'fails the undo with the way to install it by hand when winget fails' {
        $script:Installs = @((New-TestInstall $false $false $null $null))
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = -1978335212; Output = 'No package found' } }
        { Restore-TuneupState -Tweak $Tweak -State ([pscustomobject]@{ installed = $true; perUser = $true; perMachine = $false; version = '26.1' }) } |
            Should -Throw '*winget install --id Microsoft.OneDrive*'
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
        Mock -ModuleName Tuneup Get-OnedriveActionHelperInstall { New-TestInstall $false $false $null $null }
        Mock -ModuleName Tuneup Start-Sleep { }
        & (Get-Module Tuneup) { Wait-OnedriveActionHelperRemoval -Seconds 5 } | Should -BeTrue
        Should -Invoke Start-Sleep -ModuleName Tuneup -Times 0 -Exactly
    }
}
