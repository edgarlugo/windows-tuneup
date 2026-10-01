BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'apps.bing-news' -Type 'appx' -Scope 'machine' `
        -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' })
    function New-FakePackage([string]$InstallState = 'Installed') {
        [pscustomobject]@{
            Name                   = 'Microsoft.BingNews'
            PackageFullName        = 'Microsoft.BingNews_4.55.62231.0_x64__8wekyb3d8bbwe'
            Version                = '4.55.62231.0'
            PackageUserInformation = @([pscustomobject]@{ InstallState = $InstallState })
        }
    }
    $script:Provisioned = [pscustomobject]@{
        DisplayName = 'Microsoft.BingNews'
        PackageName = 'Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'
        Version     = '4.55.62231.0'
    }
}

Describe 'Appx handler' {
    It 'reads an app installed for a user and provisioned' {
        $installed = New-FakePackage
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        $state = Get-AppxTweakState -Tweak $Tweak
        $state.installedUsers | Should -BeTrue
        $state.provisioned | Should -BeTrue
        $state.version | Should -Be '4.55.62231.0'
        Test-AppxTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'treats a package only staged for a user as not installed' {
        $staged = New-FakePackage -InstallState 'Staged'
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $staged }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        (Get-AppxTweakState -Tweak $Tweak).installedUsers | Should -BeFalse
        Test-AppxTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'still needs the removal when the app is only provisioned' {
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        Test-AppxTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'counts an app that is neither installed nor provisioned as applied' {
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        $state = Get-AppxTweakState -Tweak $Tweak
        $state.installedUsers | Should -BeFalse
        $state.provisioned | Should -BeFalse
        $state.version | Should -BeNullOrEmpty
        Test-AppxTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'removes the app for all users and deprovisions it' {
        $installed = New-FakePackage
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxProvisionedPackage { }
        $outcome = Get-TuneupOutcome -Output @(Set-AppxTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeFalse
        Should -Invoke Remove-TuneupAppxPackage -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $Package.PackageFullName -eq 'Microsoft.BingNews_4.55.62231.0_x64__8wekyb3d8bbwe'
        }
        Should -Invoke Remove-TuneupAppxProvisionedPackage -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $Package.PackageName -eq 'Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'
        }
    }

    It 'reports a partial change when deprovisioning fails after the removal' {
        $installed = New-FakePackage
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxProvisionedPackage { throw 'Access denied' }
        $outcome = Get-TuneupOutcome -Output @(Set-AppxTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*provisioned package*Access denied*'
    }

    It 'throws when nothing could be removed' {
        $installed = New-FakePackage
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { throw 'in use' }
        { Set-AppxTweakDesired -Tweak $Tweak } | Should -Throw '*for all users failed: in use*'
    }
}

Describe 'Appx definition' {
    It 'accepts a valid appx tweak' {
        (Test-AppxTweakDefinition -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'a wildcard in the name'; Field = 'name'; Value = 'Microsoft.Bing*'; Message = 'invalid appx package name' }
        @{ Problem = 'a lowercase Store id'; Field = 'storeId'; Value = '9wzdncrfhvfw'; Message = 'Microsoft Store id' }
        @{ Problem = 'a short Store id'; Field = 'storeId'; Value = '9WZDNCRF'; Message = 'Microsoft Store id' }
        @{ Problem = 'another action'; Field = 'action'; Value = 'install'; Message = "invalid appx action 'install'" }
    ) {
        param($Field, $Value, $Message)
        $set = [pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' }
        $set.$Field = $Value
        $tweak = New-TestTweak -Type 'appx' -Scope 'machine' -Set $set
        (Test-AppxTweakDefinition -Tweak $tweak) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'requires scope machine' {
        $tweak = New-TestTweak -Type 'appx' -Scope 'user' -Set $Tweak.set
        (Test-AppxTweakDefinition -Tweak $tweak) -join '; ' | Should -Match 'must use scope machine'
    }
}

Describe 'Appx restore' {
    It 'reinstalls an app that was installed, from the Store, for the current user' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = 0; Output = 'Successfully installed' } }
        $state = [pscustomobject]@{ installedUsers = $true; provisioned = $true; version = '4.55.62231.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'reinstalled'
        $outcome.detail | Should -BeLike '*current user only*not provisioned again*'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join ' ') -eq 'install --id 9WZDNCRFHVFW --source msstore --exact --accept-package-agreements --accept-source-agreements --silent --disable-interactivity'
        }
    }

    It 'accepts the winget code for an app that is already installed' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = -1978335135; Output = 'Found an existing package already installed.' } }
        $state = [pscustomobject]@{ installedUsers = $true; provisioned = $false; version = '1.0' }
        (Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)).reason | Should -Be 'reinstalled'
    }

    It 'throws with the winget exit code when the install fails' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = -1978335212; Output = 'No package found matching input criteria.' } }
        $state = [pscustomobject]@{ installedUsers = $true; provisioned = $false; version = '1.0' }
        { Restore-AppxTweakState -Tweak $Tweak -State $state } | Should -Throw '*exit code -1978335212*No package found*'
    }

    It 'does not call winget when the current user still has the app' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $true }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { }
        $state = [pscustomobject]@{ installedUsers = $true; provisioned = $true; version = '1.0' }
        (Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)).reason | Should -BeNullOrEmpty
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'does nothing for an app that was not there' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { }
        $state = [pscustomobject]@{ installedUsers = $false; provisioned = $false; version = $null }
        @(Restore-AppxTweakState -Tweak $Tweak -State $state).Count | Should -Be 0
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'explains that an app that was only provisioned cannot be provisioned again' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { }
        $state = [pscustomobject]@{ installedUsers = $false; provisioned = $true; version = '1.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'not-reprovisioned'
        $outcome.detail | Should -BeLike '*winget install --id 9WZDNCRFHVFW --source msstore*'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'winget' {
    It 'throws a clear error when winget is missing' {
        Mock -ModuleName Tuneup Get-TuneupWingetPath { }
        { Invoke-TuneupWinget -Arguments @('--version') } | Should -Throw '*winget is not available*'
    }

    It 'runs winget through the native runner' {
        Mock -ModuleName Tuneup Get-TuneupWingetPath { 'C:\fake\winget.exe' }
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 0; Output = 'v1.9.25200' } }
        (Invoke-TuneupWinget -Arguments @('--version')).Output | Should -Be 'v1.9.25200'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'C:\fake\winget.exe' -and ($Arguments -join ' ') -eq '--version'
        }
    }

    It 'decodes the output as UTF-8 while it runs and puts the console encoding back' {
        $script:EncodingDuringCall = $null
        $before = [Console]::OutputEncoding.CodePage
        Mock -ModuleName Tuneup Get-TuneupWingetPath { 'C:\fake\winget.exe' }
        Mock -ModuleName Tuneup Invoke-TuneupNative {
            $script:EncodingDuringCall = [Console]::OutputEncoding.CodePage
            [pscustomobject]@{ ExitCode = 0; Output = 'ok' }
        }
        Invoke-TuneupWinget -Arguments @('--version') | Out-Null
        $script:EncodingDuringCall | Should -Be 65001
        [Console]::OutputEncoding.CodePage | Should -Be $before
    }

    It 'puts the console encoding back when the run throws' {
        $before = [Console]::OutputEncoding.CodePage
        Mock -ModuleName Tuneup Get-TuneupWingetPath { 'C:\fake\winget.exe' }
        Mock -ModuleName Tuneup Invoke-TuneupNative { throw 'boom' }
        { Invoke-TuneupWinget -Arguments @('--version') } | Should -Throw '*boom*'
        [Console]::OutputEncoding.CodePage | Should -Be $before
    }
}

Describe 'Appx registration' {
    It 'is a dispatched type that needs elevation to read' {
        Get-TuneupHandlerName -Tweak $Tweak | Should -Be 'Appx'
        (Get-TuneupHandler -Type 'appx').ReadNeedsAdmin | Should -BeTrue
    }

    It 'passes the catalog validation' {
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }
}