# -ResultId (design, section 13.2): with -Json, the document also goes to out\<id>.json under the state
# folder, for a caller that cannot read the standard output: the Claude skill starts the tool elevated
# with UAC (Start-Process -Verb RunAs) and reads that file afterwards. The caller gives an id, never a
# path. The file is created before the command runs, so an id in use stops everything, and it is filled
# with the text of the output when the command ends.

# \z and not $: $ also matches before a line break at the end. Not a hyphen first: PowerShell would
# take -abcd1234 as the name of a parameter.
$script:ResultIdPattern = '^[A-Za-z0-9][A-Za-z0-9-]{7,63}\z'
$script:ResultFileKeep = 50
# The fields of the documents that can carry a path (the run folder, a state file, a file that could not
# be written, the output of sfc or DISM): in the machine folder, which Users can read, the profile folder
# and the account name are hidden there, as in result.json. Ids, statuses, reasons and titles are written
# as they are, and so is manual: it is a command to run (hidden, it would restore a wrong value, or a
# wrong key for an account named like one of its folders), and the run folder already holds its values.
$script:ResultFreeTextFields = @('warnings', 'message', 'details', 'runDir', 'path', 'error', 'detail', 'output', 'repairedFiles', 'unrepairedFiles')

# The reason -ResultId cannot be used, or nothing. Without -Json there is no document to save.
function Get-TuneupResultIdProblem {
    param([AllowEmptyString()][AllowNull()][string]$Id, [switch]$Json)
    if (-not $Json) { return (Get-TuneupText -Key 'err.resultIdNeedsJson') }
    if ($Id -cnotmatch $script:ResultIdPattern) { return (Get-TuneupText -Key 'err.resultIdInvalid') }
}

# Creates out\<id>.json, empty and held open (nobody else can write it), in the same folder the runs of
# this process use: the hardened machine folder when elevated (only administrators write; users read),
# the user folder otherwise, or -StateRoot. The machine folder and out are checked like the rest of the
# machine state (owner, ACL, no junction), so only administrators can put anything there, links
# included. CreateNew never replaces an existing file or hard link. Then the oldest results are removed,
# so out keeps the newest ones, this one included.
function Open-TuneupResultFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [string]$StateRoot, [switch]$Machine, [string]$MachineRoot, [string]$UserRoot)
    if ($Id -cnotmatch $script:ResultIdPattern) { throw "Invalid result id '$Id'" }
    if ($StateRoot) {
        Write-TuneupStateRootWarning
        $kind = 'custom'
        $root = $StateRoot
    }
    elseif ($Machine) {
        if (-not (Test-TuneupAdmin)) { throw 'The machine state folder can only be written by an elevated process' }
        $kind = 'machine'
        $root = $(if ($MachineRoot) { $MachineRoot } else { Get-TuneupStateRoot -Machine })
        Initialize-TuneupStateRoot -Path $root -Children @('out')
    }
    else {
        $kind = 'user'
        $root = $(if ($UserRoot) { $UserRoot } else { Get-TuneupStateRoot })
    }
    $dir = Join-Path $root 'out'
    if ($kind -ne 'machine') { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
    $path = Join-Path $dir "$Id.json"
    try {
        if ($kind -eq 'machine') {
            $stream = New-TuneupSecureFile -Path $path -Security (New-TuneupStateSecurity -File)
        }
        else {
            $stream = [System.IO.FileStream]::new($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        }
    }
    catch {
        if ($_.Exception.GetBaseException() -is [System.IO.IOException] -and (Test-Path -LiteralPath $path)) {
            throw (Get-TuneupText -Key 'err.resultIdExists' -Format $Id)
        }
        throw
    }
    Remove-TuneupOldResultFile -Directory $dir -Keep ($script:ResultFileKeep - 1) -Current "$Id.json"
    [pscustomobject]@{ PSTypeName = 'Tuneup.ResultFile'; Id = $Id; Path = $path; Root = $kind; Stream = $stream }
}

# Removes all but the newest results, never Current (the file of this run, held open). Only files right
# inside out whose name is a result id count: a folder or a link (a reparse point) is left alone, and
# deleting a name removes that name only, never what a link points to. A result that cannot be removed
# is a warning: the document of this run is what matters.
function Remove-TuneupOldResultFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][int]$Keep, [string]$Current)
    try {
        # -Filter '*.json' also matches longer extensions through short names.
        $files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.json' -File -Force -ErrorAction Stop |
            Where-Object {
                $_.Extension -eq '.json' -and $_.BaseName -cmatch $script:ResultIdPattern -and $_.Name -ne $Current -and
                -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
            } |
            Sort-Object -Property @{ Expression = 'LastWriteTimeUtc'; Descending = $true }, @{ Expression = 'Name'; Descending = $true })
    }
    catch {
        Write-Warning "Could not list the old result files in ${Directory}: $($_.Exception.Message)"
        return
    }
    foreach ($file in @($files | Select-Object -Skip $Keep)) {
        try {
            [System.IO.File]::Delete((Join-Path $Directory $file.Name))
        }
        catch {
            Write-Warning "Could not remove the old result file $($file.FullName): $($_.Exception.Message)"
        }
    }
}

# Opens the result file of tuneup.ps1 for this context: the machine folder when elevated, the user
# folder otherwise, -StateRoot (resolved like Invoke-TuneupCli does) in tests. Gives { File, Message }:
# Message is set when it cannot be used, and the caller writes the error.
function Open-TuneupContextResultFile {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][string]$Id, [string]$StateRoot)
    $openArguments = @{ Id = $Id; Machine = [bool](Test-TuneupAdmin) }
    if ($StateRoot) { $openArguments.StateRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StateRoot) }
    try {
        $file = Invoke-TuneupContextStep -Context $Context -Step { Open-TuneupResultFile @openArguments }
        [pscustomobject]@{ File = $file; Message = $null }
    }
    catch {
        [pscustomobject]@{ File = $null; Message = $_.Exception.Message }
    }
}

# The free texts of a document (see ResultFreeTextFields) with the profile folder and the account name
# hidden, everything else as it was. A document with nothing to hide is kept as it came, the same text
# as the standard output. Text that is not one JSON document is hidden as a whole.
function Hide-TuneupResultPersonalData {
    param([Parameter(Mandatory)][string]$Text)
    try {
        $document = $Text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return (Hide-TuneupPersonalData -Text $Text -JsonEscaped)
    }
    $changes = @{ Hidden = 0 }
    Hide-TuneupValuePersonalData -Value $document -Changes $changes
    $(if ($changes.Hidden) { Write-TuneupJson -Object $document } else { $Text })
}

# Hides in place, counting in Changes the texts that changed.
function Hide-TuneupValuePersonalData {
    param([AllowNull()]$Value, [Parameter(Mandatory)][hashtable]$Changes)
    $hide = {
        param($Item)
        if ($Item -isnot [string]) { return $Item }
        $hidden = Hide-TuneupPersonalData -Text $Item
        if ($hidden -cne $Item) { $Changes.Hidden++ }
        $hidden
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            if ($script:ResultFreeTextFields -cnotcontains $property.Name) {
                Hide-TuneupValuePersonalData -Value $property.Value -Changes $Changes
            }
            elseif ($property.Value -is [array]) {
                $property.Value = [object[]]@(foreach ($item in $property.Value) { & $hide $item })
            }
            else {
                $property.Value = & $hide $property.Value
            }
        }
    }
    elseif ($Value -is [array]) {
        foreach ($item in $Value) { Hide-TuneupValuePersonalData -Value $item -Changes $Changes }
    }
}

# Writes the document and closes the file; true when it was saved. In the machine folder, which Users
# can read, the personal paths are hidden (the standard output keeps them). With no document (Ctrl+C
# stopped PowerShell itself) or when it cannot be written, the file is removed: a caller then finds no
# file instead of a partial one.
function Close-TuneupResultFile {
    param([Parameter(Mandatory)]$File, [AllowEmptyString()][string]$Text = '')
    $saved = $false
    try {
        if ($Text) {
            if ($File.Root -eq 'machine') { $Text = Hide-TuneupResultPersonalData -Text $Text }
            $bytes = $script:Utf8NoBom.GetBytes($Text)
            $File.Stream.Write($bytes, 0, $bytes.Length)
            $File.Stream.Flush()
            $saved = $true
        }
    }
    catch {
        $saved = $false
    }
    finally {
        # Disposing writes what is still buffered: a failure there is a document not saved either.
        try { $File.Stream.Dispose() } catch { $saved = $false }
    }
    if (-not $saved) {
        try { [System.IO.File]::Delete($File.Path) } catch { $null = $_ }
    }
    $saved
}
