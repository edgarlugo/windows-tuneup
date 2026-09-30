BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'tasks.sample' -Type 'task' -Scope 'machine' `
        -Set ([pscustomobject]@{ path = '\Microsoft\Windows\Test\'; name = 'Sample'; state = 'Disabled' })
    $script:EnabledTweak = New-TestTweak -Id 'tasks.sample2' -Type 'task' -Scope 'machine' `
        -Set ([pscustomobject]@{ path = '\Microsoft\Windows\Test\'; name = 'Sample'; state = 'Enabled' })
    # Client-only CIM instance: the real cmdlets type -InputObject as CimInstance, and this never touches a real task.
    $script:NewFakeTask = {
        param([string]$Name, [string]$State)
        New-CimInstance -ClientOnly -ClassName MSFT_ScheduledTask -Namespace 'Root/Microsoft/Windows/TaskScheduler' `
            -Property @{ TaskName = $Name; TaskPath = '\Microsoft\Windows\Test\'; State = $State }
    }
}

Describe 'Task handler' {
    It 'reports an enabled task as not applied when the goal is Disabled' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        (Get-TaskTweakState -Tweak $Tweak).enabled | Should -BeTrue
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'counts a running task as enabled' {
        $fake = & $NewFakeTask 'Sample' 'Running'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        (Get-TaskTweakState -Tweak $Tweak).enabled | Should -BeTrue
    }

    It 'reports a disabled task as applied' {
        $fake = & $NewFakeTask 'Sample' 'Disabled'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'reports a missing task as not-present' {
        Mock -ModuleName Tuneup Get-ScheduledTask { $null }
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'resolves only the exact match when the wildcard lookup returns several tasks' {
        $near = & $NewFakeTask 'SampleOther' 'Ready'
        $exact = & $NewFakeTask 'Sample' 'Disabled'
        Mock -ModuleName Tuneup Get-ScheduledTask { $near; $exact }.GetNewClosure()
        (Get-TaskTweakState -Tweak $Tweak).enabled | Should -BeFalse
    }

    It 'reports not-present when the lookup only returns near matches' {
        $near = & $NewFakeTask 'SampleOther' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $near }.GetNewClosure()
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'disables the exact task object with errors made terminating' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Disable-ScheduledTask { }
        Set-TaskTweakDesired -Tweak $Tweak
        Should -Invoke Disable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $InputObject.TaskName -eq 'Sample' -and $InputObject.TaskPath -eq '\Microsoft\Windows\Test\' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'enables the task when the goal state is Enabled' {
        $fake = & $NewFakeTask 'Sample' 'Disabled'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Enable-ScheduledTask { }
        Set-TaskTweakDesired -Tweak $EnabledTweak
        Should -Invoke Enable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $InputObject.TaskName -eq 'Sample' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'enables the task again when it was enabled before' {
        $fake = & $NewFakeTask 'Sample' 'Disabled'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Enable-ScheduledTask { }
        Restore-TaskTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; enabled = $true })
        Should -Invoke Enable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
    }

    It 'disables the task again when it was disabled before' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Disable-ScheduledTask { }
        Restore-TaskTweakState -Tweak $EnabledTweak -State ([pscustomobject]@{ present = $true; enabled = $false })
        Should -Invoke Disable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
    }

    It 'does nothing on restore when the task was not present' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Enable-ScheduledTask { }
        Mock -ModuleName Tuneup Disable-ScheduledTask { }
        Restore-TaskTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $false; enabled = $null })
        Should -Invoke Enable-ScheduledTask -ModuleName Tuneup -Times 0 -Exactly
        Should -Invoke Disable-ScheduledTask -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'throws when the task is missing at write time' {
        Mock -ModuleName Tuneup Get-ScheduledTask { $null }
        Mock -ModuleName Tuneup Disable-ScheduledTask { }
        { Set-TaskTweakDesired -Tweak $Tweak } | Should -Throw '*Scheduled task \Microsoft\Windows\Test\Sample not found*'
        Should -Invoke Disable-ScheduledTask -ModuleName Tuneup -Times 0 -Exactly
    }

    It 'propagates a failure from Disable-ScheduledTask' {
        $fake = & $NewFakeTask 'Sample' 'Ready'
        Mock -ModuleName Tuneup Get-ScheduledTask { $fake }.GetNewClosure()
        Mock -ModuleName Tuneup Disable-ScheduledTask { throw 'access denied' }
        { Set-TaskTweakDesired -Tweak $Tweak } | Should -Throw '*access denied*'
    }
}
