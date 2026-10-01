function Invoke-TuneupNative {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [AllowEmptyCollection()][string[]]$Arguments = @()
    )
    # Native tools report failure through their exit code. With Stop, Windows PowerShell 5.1 turns
    # any line they write to standard error into a terminating error before that code can be read.
    $ErrorActionPreference = 'Continue'
    $output = & $FilePath @Arguments 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = (@($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    }
}
