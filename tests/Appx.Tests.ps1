BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'apps.bing-news' -Type 'appx' -Scope 'machine' `
        -Set ([pscustomobject]@{ name = 'Microsoft.BingNews'; storeId = '9WZDNCRFHVFW'; action = 'remove' })
    $script:Me = 'S-1-5-21-1-1-1-1001'
    $script:Other = 'S-1-5-21-1-1-1-1002'
    $script:Third = 'S-1-5-21-1-1-1-1003'
    # Windows returns a struct with string Sid and Username fields whose text form is only its type name.
    function New-FakeUser([string]$Sid, [string]$InstallState = 'Installed') {
        $id = [pscustomobject]@{ Sid = $Sid; Username = "PC\$Sid" }
        $id | Add-Member -MemberType ScriptMethod -Name ToString -Force -Value { 'Microsoft.Windows.Appx.PackageManager.Commands.AppxUserSecurityId' }
        [pscustomobject]@{ UserSecurityId = $id; InstallState = $InstallState }
    }
    function New-FakePackage([string]$InstallState = 'Installed', [object[]]$Users = $null) {
        if ($null -eq $Users) { $Users = @(New-FakeUser -Sid $script:Me -InstallState $InstallState) }
        [pscustomobject]@{
            Name                   = 'Microsoft.BingNews'
            PackageFullName        = 'Microsoft.BingNews_4.55.62231.0_x64__8wekyb3d8bbwe'
            Version                = '4.55.62231.0'
            PackageUserInformation = $Users
        }
    }
    $script:Provisioned = [pscustomobject]@{
        DisplayName = 'Microsoft.BingNews'
        PackageName = 'Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'
        Version     = '4.55.62231.0'
    }
}

Describe 'Appx handler' {
    BeforeEach {
        Clear-TuneupAppxCache
        Mock -ModuleName Tuneup Get-TuneupCurrentUserSid { 'S-1-5-21-1-1-1-1001' }
    }

    It 'reads an app installed for a user and provisioned' {
        $installed = New-FakePackage
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        $state = Get-AppxTweakState -Tweak $Tweak
        $state.installedUsers | Should -BeTrue
        $state.provisioned | Should -BeTrue
        $state.version | Should -Be '4.55.62231.0'
        $state.currentUserHad | Should -BeTrue
        $state.currentUserSid | Should -Be $Me
        $state.otherUsers | Should -Be 0
        Test-AppxTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'tells the current user from the other users that have the app' {
        $installed = New-FakePackage -Users @(
            (New-FakeUser -Sid $Me), (New-FakeUser -Sid $Other), (New-FakeUser -Sid $Other), (New-FakeUser -Sid $Third -InstallState 'Staged'))
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        $state = Get-AppxTweakState -Tweak $Tweak
        $state.currentUserHad | Should -BeTrue
        $state.otherUsers | Should -Be 1
    }

    It 'records an app that only other users have' {
        $installed = New-FakePackage -Users @((New-FakeUser -Sid $Me -InstallState 'Staged'), (New-FakeUser -Sid $Other), (New-FakeUser -Sid $Third))
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        $state = Get-AppxTweakState -Tweak $Tweak
        $state.installedUsers | Should -BeTrue
        $state.currentUserHad | Should -BeFalse
        $state.currentUserSid | Should -BeNullOrEmpty
        $state.otherUsers | Should -Be 2
    }

    It 'reads the user id from an entry that only has its text form' {
        $user = [pscustomobject]@{ UserSecurityId = 'S-1-5-21-1-1-1-1001[PC\me]'; InstallState = 'Installed' }
        $installed = New-FakePackage -Users @($user)
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        (Get-AppxTweakState -Tweak $Tweak).currentUserHad | Should -BeTrue
    }

    It 'treats a package only staged for a user as not installed' {
        $staged = New-FakePackage -InstallState 'Staged'
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $staged }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        $state = Get-AppxTweakState -Tweak $Tweak
        $state.installedUsers | Should -BeFalse
        $state.currentUserHad | Should -BeFalse
        $state.otherUsers | Should -Be 0
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

    It 'removes the app for all users and deprovisions it, after reading both lists' {
        $log = New-Object System.Collections.Generic.List[string]
        $installed = New-FakePackage
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $log.Add('read-users'); $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $log.Add('read-provisioned'); $provisioned }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { $log.Add('remove-user') }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-TuneupAppxProvisionedPackage { $log.Add('remove-provisioned') }.GetNewClosure()
        $outcome = Get-TuneupOutcome -Output @(Set-AppxTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeFalse
        $log -join ',' | Should -Be 'read-users,read-provisioned,remove-user,remove-provisioned'
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

    It 'reports a partial change when the removal for users fails but deprovisioning works' {
        $installed = New-FakePackage
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { throw 'in use' }
        Mock -ModuleName Tuneup Remove-TuneupAppxProvisionedPackage { }
        $outcome = Get-TuneupOutcome -Output @(Set-AppxTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*for all users failed: in use*'
    }

    It 'reports a partial change when the provisioned list cannot be read after the users lost the app' {
        $installed = New-FakePackage
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { throw 'list failed' }
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { }
        $outcome = Get-TuneupOutcome -Output @(Set-AppxTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeTrue
        $outcome.detail | Should -BeLike '*provisioned packages*list failed*'
        Should -Invoke Remove-TuneupAppxPackage -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'throws when nothing could be removed' {
        $installed = New-FakePackage
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $installed }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { throw 'in use' }
        { Set-AppxTweakDesired -Tweak $Tweak } | Should -Throw '*for all users failed: in use*'
    }

    It 'throws when the provisioned list cannot be read and there is nothing else to remove' {
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { throw 'list failed' }
        { Set-AppxTweakDesired -Tweak $Tweak } | Should -Throw '*list failed*'
    }

    It 'only deprovisions an app that is staged but not installed for any user' {
        $staged = New-FakePackage -InstallState 'Staged'
        $provisioned = $Provisioned
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { $staged }.GetNewClosure()
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { $provisioned }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxProvisionedPackage { }
        $outcome = Get-TuneupOutcome -Output @(Set-AppxTweakDesired -Tweak $Tweak)
        $outcome.partial | Should -BeFalse
        Should -Invoke Remove-TuneupAppxPackage -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Remove-TuneupAppxProvisionedPackage -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'does nothing when there is nothing to remove' {
        Mock -ModuleName Tuneup Get-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Get-TuneupAppxProvisionedPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxPackage { }
        Mock -ModuleName Tuneup Remove-TuneupAppxProvisionedPackage { }
        @(Set-AppxTweakDesired -Tweak $Tweak).Count | Should -Be 0
        Should -Invoke Remove-TuneupAppxPackage -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Remove-TuneupAppxProvisionedPackage -ModuleName Tuneup -Times 0 -Exactly
    }
}

Describe 'Appx system wrappers' {
    BeforeEach { Clear-TuneupAppxCache }

    It 'lists the packages of all users and keeps only the exact name' {
        $listed = @((New-FakePackage), [pscustomobject]@{ Name = 'Microsoft.BingNewsExtra'; PackageFullName = 'x'; PackageUserInformation = @() })
        Mock -ModuleName Tuneup Get-AppxPackage { $listed }.GetNewClosure()
        $found = @(Get-TuneupAppxPackage -Name 'Microsoft.BingNews')
        $found.Count | Should -Be 1
        $found[0].Name | Should -Be 'Microsoft.BingNews'
        Should -Invoke Get-AppxPackage -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $AllUsers -and $Name -eq 'Microsoft.BingNews' }
    }

    It 'lists the provisioned packages online and keeps only the exact display name' {
        $listed = @($Provisioned, [pscustomobject]@{ DisplayName = 'Microsoft.BingNewsExtra'; PackageName = 'x' })
        Mock -ModuleName Tuneup Get-AppxProvisionedPackage { $listed }.GetNewClosure()
        $found = @(Get-TuneupAppxProvisionedPackage -Name 'Microsoft.BingNews')
        $found.Count | Should -Be 1
        $found[0].DisplayName | Should -Be 'Microsoft.BingNews'
        Should -Invoke Get-AppxProvisionedPackage -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $Online }
    }

    It 'reads the provisioned list once until something is removed' {
        $listed = @($Provisioned)
        Mock -ModuleName Tuneup Get-AppxProvisionedPackage { $listed }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-AppxProvisionedPackage { }
        Get-TuneupAppxProvisionedPackage -Name 'Microsoft.BingNews' | Out-Null
        Get-TuneupAppxProvisionedPackage -Name 'Microsoft.BingNews' | Out-Null
        Should -Invoke Get-AppxProvisionedPackage -ModuleName Tuneup -Times 1 -Exactly
        Remove-TuneupAppxProvisionedPackage -Package $Provisioned
        Get-TuneupAppxProvisionedPackage -Name 'Microsoft.BingNews' | Out-Null
        Should -Invoke Get-AppxProvisionedPackage -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'reads the packages of a name once until something is removed' {
        $listed = @((New-FakePackage))
        Mock -ModuleName Tuneup Get-AppxPackage { $listed }.GetNewClosure()
        Mock -ModuleName Tuneup Remove-AppxPackage { }
        Get-TuneupAppxPackage -Name 'Microsoft.BingNews' | Out-Null
        Get-TuneupAppxPackage -Name 'Microsoft.BingNews' | Out-Null
        Should -Invoke Get-AppxPackage -ModuleName Tuneup -Times 1 -Exactly
        Remove-TuneupAppxPackage -Package (New-FakePackage)
        Get-TuneupAppxPackage -Name 'Microsoft.BingNews' | Out-Null
        Should -Invoke Get-AppxPackage -ModuleName Tuneup -Times 2 -Exactly
    }

    It 'does not keep a failed read in the cache' {
        Mock -ModuleName Tuneup Get-AppxProvisionedPackage { throw 'denied' }
        { Get-TuneupAppxProvisionedPackage -Name 'Microsoft.BingNews' } | Should -Throw '*denied*'
        $listed = @($Provisioned)
        Mock -ModuleName Tuneup Get-AppxProvisionedPackage { $listed }.GetNewClosure()
        @(Get-TuneupAppxProvisionedPackage -Name 'Microsoft.BingNews').Count | Should -Be 1
    }

    It 'removes a package for all users by its full name' {
        Mock -ModuleName Tuneup Remove-AppxPackage { }
        Remove-TuneupAppxPackage -Package (New-FakePackage)
        Should -Invoke Remove-AppxPackage -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $AllUsers -and $Package -eq 'Microsoft.BingNews_4.55.62231.0_x64__8wekyb3d8bbwe'
        }
    }

    It 'deprovisions a package online by its package name' {
        Mock -ModuleName Tuneup Remove-AppxProvisionedPackage { }
        Remove-TuneupAppxProvisionedPackage -Package $Provisioned
        Should -Invoke Remove-AppxProvisionedPackage -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $Online -and $AllUsers -and $PackageName -eq 'Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'
        }
    }

    It 'looks for the current user package without -AllUsers and by exact name' {
        $listed = @((New-FakePackage), [pscustomobject]@{ Name = 'Microsoft.BingNewsExtra' })
        Mock -ModuleName Tuneup Get-AppxPackage { $listed }.GetNewClosure()
        Test-TuneupAppxInstalledForCurrentUser -Name 'Microsoft.BingNews' | Should -BeTrue
        Should -Invoke Get-AppxPackage -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { -not $AllUsers -and $Name -eq 'Microsoft.BingNews' }
        $none = @([pscustomobject]@{ Name = 'Microsoft.BingNewsExtra' })
        Mock -ModuleName Tuneup Get-AppxPackage { $none }.GetNewClosure()
        Test-TuneupAppxInstalledForCurrentUser -Name 'Microsoft.BingNews' | Should -BeFalse
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
        @{ Problem = 'a name with a trailing newline'; Field = 'name'; Value = "Microsoft.BingNews`n"; Message = 'invalid appx package name' }
        @{ Problem = 'a Store id with a trailing newline'; Field = 'storeId'; Value = "9WZDNCRFHVFW`n"; Message = 'Microsoft Store id' }
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
    BeforeEach {
        Clear-TuneupAppxCache
        Mock -ModuleName Tuneup Get-TuneupCurrentUserSid { 'S-1-5-21-1-1-1-1001' }
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $false }
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = 0; Output = 'Successfully installed' } }
    }

    It 'reinstalls an app the current user had, from the Store, without upgrading' {
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; otherUsers = 0; provisioned = $false; version = '4.55.62231.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'reinstalled'
        $outcome.detail | Should -BeNullOrEmpty
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join ' ') -eq 'install --id 9WZDNCRFHVFW --source msstore --exact --no-upgrade --accept-package-agreements --accept-source-agreements --silent --disable-interactivity'
        }
    }

    It 'lists only what was not restored after a reinstall' {
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; otherUsers = 2; provisioned = $true; version = '1.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'reinstalled'
        $outcome.detail | Should -BeLike '*not provisioned again*'
        $outcome.detail | Should -BeLike '*2 other users not restored*'
        $outcome.detail | Should -Not -BeLike '*reinstalled*'
    }

    It 'treats a state saved before the user fields existed as an app the current user had' {
        $state = [pscustomobject]@{ installedUsers = $true; provisioned = $false; version = '1.0' }
        (Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)).reason | Should -Be 'reinstalled'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'accepts winget code <Code> as success' -TestCases @(
        @{ Code = -1978335135 }
        @{ Code = -1978335189 }
    ) {
        param($Code)
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = $Code; Output = 'Already there.' } }.GetNewClosure()
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; otherUsers = 0; provisioned = $false; version = '1.0' }
        (Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)).reason | Should -Be 'reinstalled'
    }

    It 'throws with the winget exit code when the install fails' {
        Mock -ModuleName Tuneup Invoke-TuneupWinget { [pscustomobject]@{ ExitCode = -1978335212; Output = 'No package found matching input criteria.' } }
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; otherUsers = 0; provisioned = $false; version = '1.0' }
        { Restore-AppxTweakState -Tweak $Tweak -State $state } | Should -Throw '*exit code -1978335212*No package found*'
    }

    It 'does not call winget when the current user still has the app and nothing else was lost' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $true }
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; otherUsers = 0; provisioned = $false; version = '1.0' }
        @(Restore-AppxTweakState -Tweak $Tweak -State $state).Count | Should -Be 0
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'still reports the provisioned copy and the other users when the current user kept the app' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $true }
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; otherUsers = 1; provisioned = $true; version = '1.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'installed-for-other-users'
        $outcome.detail | Should -BeLike '*1 other user not restored*'
        $outcome.detail | Should -BeLike '*not provisioned again*'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'only notes the lost provisioning, without a reason, when the current user kept the app' {
        Mock -ModuleName Tuneup Test-TuneupAppxInstalledForCurrentUser { $true }
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; otherUsers = 0; provisioned = $true; version = '1.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -BeNullOrEmpty
        $outcome.detail | Should -Be 'not provisioned again for new users'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'reinstalls when the user who applied the tweak is the current user' {
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; currentUserSid = $Me; otherUsers = 0; provisioned = $false; version = '1.0' }
        (Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)).reason | Should -Be 'reinstalled'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 1 -Exactly
    }

    It 'does not install for another account than the one that applied the tweak' {
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; currentUserSid = $Other; otherUsers = 1; provisioned = $false; version = '1.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'installed-for-other-users'
        $outcome.detail | Should -BeLike '*2 other users not restored*winget install --id 9WZDNCRFHVFW --source msstore*'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'does nothing for an app that was not there' {
        $state = [pscustomobject]@{ installedUsers = $false; currentUserHad = $false; otherUsers = 0; provisioned = $false; version = $null }
        @(Restore-AppxTweakState -Tweak $Tweak -State $state).Count | Should -Be 0
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'explains that an app that was only provisioned cannot be provisioned again' {
        $state = [pscustomobject]@{ installedUsers = $false; currentUserHad = $false; otherUsers = 0; provisioned = $true; version = '1.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'not-reprovisioned'
        $outcome.detail | Should -BeLike '*winget install --id 9WZDNCRFHVFW --source msstore*'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'does not install an app that only other users had' {
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $false; otherUsers = 2; provisioned = $true; version = '1.0' }
        $outcome = Get-TuneupOutcome -Output @(Restore-AppxTweakState -Tweak $Tweak -State $state)
        $outcome.reason | Should -Be 'installed-for-other-users'
        $outcome.detail | Should -BeLike '*2 other users*winget install --id 9WZDNCRFHVFW --source msstore*'
        $outcome.detail | Should -BeLike '*not provisioned again*'
        Should -Invoke Invoke-TuneupWinget -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'reads the app packages again after a reinstall' {
        Mock -ModuleName Tuneup Get-AppxPackage { }
        Get-TuneupAppxPackage -Name 'Microsoft.BingNews' | Out-Null
        $state = [pscustomobject]@{ installedUsers = $true; currentUserHad = $true; otherUsers = 0; provisioned = $false; version = '1.0' }
        Restore-AppxTweakState -Tweak $Tweak -State $state | Out-Null
        Get-TuneupAppxPackage -Name 'Microsoft.BingNews' | Out-Null
        Should -Invoke Get-AppxPackage -ModuleName Tuneup -Times 2 -Exactly
    }
}

Describe 'winget' {
    BeforeAll {
        $script:OriginalEncoding = [Console]::OutputEncoding
    }
    AfterAll {
        [Console]::OutputEncoding = $script:OriginalEncoding
    }
    BeforeEach {
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(850)
    }

    It 'throws a clear error when winget is missing' {
        Mock -ModuleName Tuneup Get-TuneupWingetPath { }
        { Invoke-TuneupWinget -Arguments @('--version') } | Should -Throw "*winget is not available for this user (run the undo from the signed-in user's elevated prompt)*"
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
        Mock -ModuleName Tuneup Get-TuneupWingetPath { 'C:\fake\winget.exe' }
        Mock -ModuleName Tuneup Invoke-TuneupNative {
            $script:EncodingDuringCall = [Console]::OutputEncoding.CodePage
            [pscustomobject]@{ ExitCode = 0; Output = 'ok' }
        }
        Invoke-TuneupWinget -Arguments @('--version') | Out-Null
        $script:EncodingDuringCall | Should -Be 65001
        [Console]::OutputEncoding.CodePage | Should -Be 850
    }

    It 'puts the console encoding back when the run throws' {
        Mock -ModuleName Tuneup Get-TuneupWingetPath { 'C:\fake\winget.exe' }
        Mock -ModuleName Tuneup Invoke-TuneupNative { throw 'boom' }
        { Invoke-TuneupWinget -Arguments @('--version') } | Should -Throw '*boom*'
        [Console]::OutputEncoding.CodePage | Should -Be 850
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