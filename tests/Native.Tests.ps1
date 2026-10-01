BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
}

Describe 'Invoke-TuneupNative' {
    It 'returns the exit code and both output streams without throwing' {
        $result = Invoke-TuneupNative -FilePath $Cmd -Arguments @('/c', 'echo out & echo err 1>&2 & exit 3')
        $result.ExitCode | Should -Be 3
        $result.Output | Should -Match 'out'
        $result.Output | Should -Match 'err'
    }

    It 'returns exit code 0 for a tool that succeeds' {
        (Invoke-TuneupNative -FilePath $Cmd -Arguments @('/c', 'exit 0')).ExitCode | Should -Be 0
    }
}

Describe 'Invoke-TuneupSc' {
    It 'calls sc.exe config with start= and the value as separate arguments' {
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 0; Output = '[SC] ChangeServiceConfig SUCCESS' } }
        Invoke-TuneupSc -Name 'RetailDemo' -Start 'disabled'
        Should -Invoke Invoke-TuneupNative -ModuleName Tuneup -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\System32\sc.exe' -and ($Arguments -join '|') -eq 'config|RetailDemo|start=|disabled'
        }
    }

    It 'throws with the exit code and the output when sc.exe fails' {
        Mock -ModuleName Tuneup Invoke-TuneupNative { [pscustomobject]@{ ExitCode = 1060; Output = 'The specified service does not exist as an installed service.' } }
        { Invoke-TuneupSc -Name 'Nope' -Start 'disabled' } | Should -Throw '*exit code 1060*does not exist*'
    }
}
