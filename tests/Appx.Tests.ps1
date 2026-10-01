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
