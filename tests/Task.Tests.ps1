BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Tweak = New-TestTweak -Id 'tasks.sample' -Type 'task' -Scope 'machine' `
        -Set ([pscustomobject]@{ path = '\Microsoft\Windows\Test\'; name = 'Sample'; state = 'Disabled' })
}

Describe 'Task handler' {
    It 'reports an enabled task as not applied when the goal is Disabled' {
        Mock -ModuleName Tuneup Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
        (Get-TaskTweakState -Tweak $Tweak).enabled | Should -BeTrue
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'reports a disabled task as applied' {
        Mock -ModuleName Tuneup Get-ScheduledTask { [pscustomobject]@{ State = 'Disabled' } }
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'applied'
    }

    It 'reports a missing task as not-present' {
        Mock -ModuleName Tuneup Get-ScheduledTask { $null }
        Test-TaskTweakState -Tweak $Tweak | Should -Be 'not-present'
    }

    It 'disables the task' {
        Mock -ModuleName Tuneup Disable-ScheduledTask { }
        Set-TaskTweakDesired -Tweak $Tweak
        Should -Invoke Disable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'Sample' -and $TaskPath -eq '\Microsoft\Windows\Test\' }
    }

    It 'enables the task again when it was enabled before' {
        Mock -ModuleName Tuneup Enable-ScheduledTask { }
        Restore-TaskTweakState -Tweak $Tweak -State ([pscustomobject]@{ present = $true; enabled = $true })
        Should -Invoke Enable-ScheduledTask -ModuleName Tuneup -Times 1 -Exactly
    }
}
