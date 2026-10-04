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
# be written, the output of sfc or DISM): in the machine folder, which Users can read, the profile folder,
# the account name and the SID of an account are hidden there, as in result.json (which keeps the SID).
# Ids, statuses, reasons and titles are written
# as they are, and so is manual: it is a command to run (hidden, it would restore a wrong value, or a
# wrong key for an account named like one of its folders), and the run folder already holds its values.
$script:ResultFreeTextFields = @('warnings', 'message', 'details', 'runDir', 'path', 'error', 'detail', 'output', 'repairedFiles', 'unrepairedFiles')
# What only the documents of -Startup add to those fields: an entry is named by the value, file, task or
# service it is (a task of OneDrive carries the SID of the account in its name, a file the profile folder),
# and its command line can hold the profile folder; what -Startup -Disable plans and applies is titled
# with the name of the entry. Name, key, command and title of other documents are written as they are.
$script:StartupResultFreeTextFields = @('name', 'key', 'command')
$script:StartupApplyFreeTextFields = @('title')
# The SID of an account of a person: local or of a domain (S-1-5-21-...), or of Entra ID (S-1-12-1-...).
# The SIDs of Windows accounts (S-1-5-18, S-1-5-32-545...) name nobody and are written as they are.
$script:AccountSidPattern = '\bS-1-(?:5-21|12-1)(?:-\d+)+'

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

# A text with the profile folder, the account name and the SID of an account hidden.
function Hide-TuneupResultText {
    param([AllowNull()][AllowEmptyString()][string]$Text, [switch]$JsonEscaped)
    $hidden = Hide-TuneupPersonalData -Text $Text -JsonEscaped:$JsonEscaped
    if ([string]::IsNullOrEmpty($hidden)) { return $hidden }
    [regex]::Replace($hidden, $script:AccountSidPattern, '%SID%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

# The fields of a document whose texts are hidden: the free texts of every document, and what the
# documents of -Startup add (the startup list; the plan and the run of -Startup -Disable).
function Get-TuneupResultFreeTextField {
    param([Parameter(Mandatory)]$Document)
    $fields = $script:ResultFreeTextFields
    if ($Document -isnot [System.Management.Automation.PSCustomObject]) { return $fields }
    $command = $Document.PSObject.Properties['command']
    $source = $Document.PSObject.Properties['source']
    if ($null -ne $command -and [string]$command.Value -ceq 'startup') { return ($fields + $script:StartupResultFreeTextFields) }
    if ($null -ne $source -and [string]$source.Value -ceq 'startup') { return ($fields + $script:StartupApplyFreeTextFields) }
    $fields
}

# The free texts of a document (see ResultFreeTextFields) with the profile folder, the account name and
# the SID of an account hidden, everything else as it was. A document with nothing to hide is kept as it
# came, the same text as the standard output. Text that is not one JSON document is hidden as a whole.
function Hide-TuneupResultPersonalData {
    param([Parameter(Mandatory)][string]$Text)
    try {
        $document = $Text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return (Hide-TuneupResultText -Text $Text -JsonEscaped)
    }
    $changes = @{ Hidden = 0 }
    Hide-TuneupValuePersonalData -Value $document -Changes $changes -Fields (Get-TuneupResultFreeTextField -Document $document)
    $(if ($changes.Hidden) { Write-TuneupJson -Object $document } else { $Text })
}

# Hides in place, counting in Changes the texts that changed.
function Hide-TuneupValuePersonalData {
    param([AllowNull()]$Value, [Parameter(Mandatory)][hashtable]$Changes, [string[]]$Fields = $script:ResultFreeTextFields)
    $hide = {
        param($Item)
        if ($Item -isnot [string]) { return $Item }
        $hidden = Hide-TuneupResultText -Text $Item
        if ($hidden -cne $Item) { $Changes.Hidden++ }
        $hidden
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            if ($Fields -cnotcontains $property.Name) {
                Hide-TuneupValuePersonalData -Value $property.Value -Changes $Changes -Fields $Fields
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
        foreach ($item in $Value) { Hide-TuneupValuePersonalData -Value $item -Changes $Changes -Fields $Fields }
    }
}

# -ReadResult: the text of out\<id>.json, for a caller that started the tool elevated and must not trust
# the file by its path alone (a standard user can make %ProgramData%\windows-tuneup before the first
# elevated run, which then refuses to write, and leave a result of their own there). The machine folder
# first, checked like the machine state on every level (the folder that holds it, the state folder, out
# and the file itself: owner, who can write, no junction, one link); then, for an unelevated caller,
# the user folder, where its unelevated runs write, but never past a machine folder that exists and
# fails those checks; -StateRoot alone in tests. Gives { Code, Key, Text,
# Path, Folder }: Code is null and Text the document as it was written, or Code says why there is none
# (result-missing, result-incomplete, result-untrusted) and Key is its message.
function Read-TuneupResultFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [string]$StateRoot, [string]$MachineRoot, [string]$UserRoot, [switch]$IncludeUser)
    if ($Id -cnotmatch $script:ResultIdPattern) { throw "Invalid result id '$Id'" }
    $machine = $(if ($MachineRoot) { $MachineRoot } else { Get-TuneupStateRoot -Machine })
    $answer = {
        param([string]$Code, [string]$Key, [string]$Text, [string]$Path)
        [pscustomobject]@{ PSTypeName = 'Tuneup.ResultRead'; Code = $Code; Key = $Key; Text = $Text; Path = $Path; Folder = $machine }
    }
    $fileName = "$Id.json"
    if ($StateRoot) {
        Write-TuneupStateRootWarning
        $places = @([pscustomobject]@{ Kind = 'custom'; Path = Join-Path $StateRoot "out\$fileName" })
    }
    else {
        # A machine folder that is not trusted stops everything, before the user folder: the elevated run
        # refused to write there, and a result of the same id elsewhere is not its result.
        if ((Test-Path -LiteralPath $machine) -and -not (Test-TuneupResultFolderTrusted -Root $machine)) {
            return (& $answer 'result-untrusted' 'err.readResultUntrusted' $null $null)
        }
        $places = @([pscustomobject]@{ Kind = 'machine'; Path = Join-Path $machine "out\$fileName" })
        if ($IncludeUser) {
            $user = $(if ($UserRoot) { $UserRoot } else { Get-TuneupStateRoot })
            $places += [pscustomobject]@{ Kind = 'user'; Path = Join-Path $user "out\$fileName" }
        }
    }
    foreach ($place in $places) {
        if (-not (Test-Path -LiteralPath $place.Path)) { continue }
        try {
            if ($place.Kind -eq 'machine') {
                # Again: the folder may have been made after the check above.
                if (-not (Test-TuneupResultFolderTrusted -Root $machine)) { return (& $answer 'result-untrusted' 'err.readResultUntrusted' $null $place.Path) }
                try {
                    $stream = Open-TuneupTrustedStream -Path $place.Path
                }
                catch {
                    # In use: the run is still writing it. Anything else: not a file of an administrator.
                    if ($_.Exception.GetBaseException() -is [System.IO.IOException]) { throw }
                    return (& $answer 'result-untrusted' 'err.readResultUntrusted' $null $place.Path)
                }
                $reader = New-Object System.IO.StreamReader -ArgumentList $stream, $script:Utf8NoBom, $true
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
            else {
                $text = [System.IO.File]::ReadAllText($place.Path, $script:Utf8NoBom)
            }
        }
        catch {
            if ($_.Exception.GetBaseException() -is [System.IO.IOException]) { return (& $answer 'result-incomplete' 'err.readResultIncomplete' $null $place.Path) }
            throw
        }
        if (-not (Test-TuneupResultDocument -Text $text)) { return (& $answer 'result-incomplete' 'err.readResultIncomplete' $null $place.Path) }
        return (& $answer $null $null $text $place.Path)
    }
    & $answer 'result-missing' 'err.readResultMissing' $null $null
}

# The machine state folder and its out folder (when there is one), with the folder that holds them,
# pass the checks of the machine state: only administrators could have put a result there.
function Test-TuneupResultFolderTrusted {
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Test-TuneupBaseFolder -Path (Split-Path -Parent $Root))) { return $false }
    if (-not (Test-TuneupTrustedItem -Path $Root)) { return $false }
    $out = Join-Path $Root 'out'
    (-not (Test-Path -LiteralPath $out)) -or (Test-TuneupTrustedItem -Path $out)
}

# One JSON object, the whole text: an empty file or a cut one is a run still going or stopped.
function Test-TuneupResultDocument {
    param([AllowEmptyString()][string]$Text)
    if (-not $Text -or -not $Text.Trim()) { return $false }
    try {
        $document = $Text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $false
    }
    $document -is [System.Management.Automation.PSCustomObject]
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
