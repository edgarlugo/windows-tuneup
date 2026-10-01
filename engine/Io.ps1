# Where questions are written and answers are read. The console one writes to the host and reads a
# line with Read-Host, which also reads lines from a redirected standard input and gives $null at its
# end. Tests pass their own object with the same two script blocks and scripted answers.
function New-TuneupConsoleIo {
    [pscustomobject]@{
        PSTypeName = 'Tuneup.Io'
        Read       = { Read-Host }
        Write      = {
            param([AllowEmptyString()][string]$Text, [switch]$NoNewline)
            Write-Host $Text -NoNewline:$NoNewline
        }
    }
}

function Write-TuneupIoLine {
    param([Parameter(Mandatory)]$Io, [AllowEmptyString()][string]$Text = '', [switch]$NoNewline)
    & $Io.Write $Text -NoNewline:$NoNewline
}

# The answer, trimmed; $null when there is nothing more to read (the end of a redirected input).
function Read-TuneupIoAnswer {
    param([Parameter(Mandatory)]$Io, [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt)
    if ($Prompt) { Write-TuneupIoLine -Io $Io -Text "$Prompt " -NoNewline }
    $answer = & $Io.Read
    if ($null -eq $answer) { return $null }
    ([string]$answer).Trim()
}

# Yes only when the answer matches the yes pattern of the language; anything else, or no answer, is no.
function Read-TuneupConfirmation {
    param([Parameter(Mandatory)]$Io, [Parameter(Mandatory)][string]$Prompt)
    $answer = Read-TuneupIoAnswer -Io $Io -Prompt $Prompt
    ($null -ne $answer) -and ($answer -match (Get-TuneupText -Key 'confirm.pattern'))
}
