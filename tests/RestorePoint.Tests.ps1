BeforeAll {
    if (-not (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue)) {
        function global:Get-ComputerRestorePoint { param([Parameter(ValueFromRemainingArguments)]$Rest) }
    }
    if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
        function global:Checkpoint-Computer { param([Parameter(ValueFromRemainingArguments)]$Rest) }
    }
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
}

Describe 'New-TuneupRestorePoint' {
    BeforeEach {
        $script:Points = 1
        Mock -ModuleName Tuneup Get-ComputerRestorePoint {
            if ($script:Points -gt 0) { 1..$script:Points | ForEach-Object { [pscustomobject]@{ SequenceNumber = $_ } } }
        }
    }

    It 'reports created when a new point appears' {
        Mock -ModuleName Tuneup Checkpoint-Computer { $script:Points++ }
        New-TuneupRestorePoint -Description 'test' | Should -Be 'created'
    }

    It 'reports created when the newest point advances even if old ones were pruned' {
        Mock -ModuleName Tuneup Checkpoint-Computer { $script:Points = @(2) }
        Mock -ModuleName Tuneup Get-ComputerRestorePoint {
            [pscustomobject]@{ SequenceNumber = $script:Points[-1] }
        }
        $script:Points = @(1)
        New-TuneupRestorePoint -Description 'test' | Should -Be 'created'
    }

    It 'reports skipped-recent when Windows keeps the last one' {
        Mock -ModuleName Tuneup Checkpoint-Computer { }
        New-TuneupRestorePoint -Description 'test' | Should -Be 'skipped-recent'
    }

    It 'reports failed when the checkpoint throws' {
        Mock -ModuleName Tuneup Checkpoint-Computer { throw 'disabled' }
        New-TuneupRestorePoint -Description 'test' | Should -Be 'failed'
    }

    It 'reports unavailable when restore points cannot be listed' {
        Mock -ModuleName Tuneup Get-ComputerRestorePoint { throw 'not supported' }
        New-TuneupRestorePoint -Description 'test' | Should -Be 'unavailable'
    }
}
