$script:ActionNamePattern = '^[a-z0-9]+(-[a-z0-9]+)*$'
# Loaded action scripts: name -> file.
$script:TuneupActionScripts = @{}
# Function names defined by action scripts: name -> script (hashtables ignore case).
$script:TuneupActionFunctions = @{}

function ConvertTo-TuneupPascalName {
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -cnotmatch $script:ActionNamePattern) { throw "Invalid action script name '$Name': use lowercase words separated by hyphens" }
    (($Name -split '-') | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''
}

function Get-TuneupActionFunctionName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Get', 'Test', 'Set', 'Restore')][string]$Verb
    )
    $suffix = $(if ($Verb -eq 'Set') { 'Desired' } else { 'State' })
    "$Verb-$(ConvertTo-TuneupPascalName -Name $Name)Action$suffix"
}

# Scripts that could not be loaded: name -> { name, file, path, message }. A broken script never
# stops the others, the engine or the commands that do not need it: its tweaks fail their catalog
# check with the reason and everything else keeps working.
$script:TuneupActionLoadErrors = @{}

function Set-TuneupActionLoadError {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Message)
    $script:TuneupActionLoadErrors[$Name] = [pscustomobject]@{ name = $Name; file = [System.IO.Path]::GetFileName($Path); path = $Path; message = $Message }
}

function Get-TuneupActionLoadError {
    @($script:TuneupActionLoadErrors.Keys | Sort-Object | ForEach-Object { $script:TuneupActionLoadErrors[$_] })
}

function Write-TuneupActionLoadWarning {
    [CmdletBinding()]
    param()
    foreach ($problem in @(Get-TuneupActionLoadError)) {
        Write-Warning "Action script $($problem.file) could not be loaded, so the tweaks that use it are not available: $($problem.message)"
    }
}

function Import-TuneupActionScript {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    $name = $File.BaseName
    $pascal = ConvertTo-TuneupPascalName -Name $name
    if ($pascal -like 'Tuneup*') { throw "Action script $($File.Name): names starting with tuneup are reserved for the engine" }
    $loadedFrom = $script:TuneupActionScripts[$name]
    if ($null -ne $loadedFrom -and $loadedFrom -ne $File.FullName) {
        throw "Action script '$name' is already loaded from $loadedFrom; $($File.FullName) cannot replace it"
    }
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "Action script $($File.Name) has a syntax error: $($parseErrors[0].Message)" }
    # The file is never run: only its function definitions are taken, so loading it cannot
    # execute code, and the name rules keep it from replacing functions of the engine or of
    # another action script.
    $onlyFunctions = ($null -eq $ast.ParamBlock -and $null -eq $ast.BeginBlock -and $null -eq $ast.ProcessBlock -and
        $null -eq $ast.DynamicParamBlock -and -not @($ast.UsingStatements).Count)
    $definitions = New-Object System.Collections.Generic.List[object]
    if ($null -ne $ast.EndBlock) {
        foreach ($statement in $ast.EndBlock.Statements) {
            if ($statement -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $onlyFunctions = $false; break }
            $definitions.Add($statement)
        }
    }
    if (-not $onlyFunctions) { throw "Action script $($File.Name) may only define functions" }
    $contract = @{}
    foreach ($verb in 'Get', 'Test', 'Set', 'Restore') { $contract[(Get-TuneupActionFunctionName -Name $name -Verb $verb)] = $true }
    $seen = @{}
    foreach ($definition in $definitions) {
        $function = $definition.Name
        # A function is one of the four contract names or a helper <Verb>-<Pascal>ActionHelper<Name>
        # whose name never contains Action again, so no name of one script can equal a contract
        # name of another (FooActionX has Set-FooActionXActionDesired; Foo cannot define it).
        $isHelper = $function -cmatch "^[A-Z][a-z]+-$($pascal)ActionHelper[A-Za-z0-9]*$" -and
            $function.Substring($function.IndexOf('ActionHelper') + 'ActionHelper'.Length) -notlike '*Action*'
        if ($function -like '*-Tuneup*' -or -not ($contract.ContainsKey($function) -or $isHelper)) {
            throw "Action script $($File.Name) defines $function; its functions must be the four contract names or helpers named <Verb>-$($pascal)ActionHelper<Name>"
        }
        if ($definition.IsFilter -or $definition.IsWorkflow) {
            throw "Action script $($File.Name) must define $function as a plain function"
        }
        if ($null -ne $definition.Parameters) {
            throw "Action script $($File.Name) must declare the parameters of $function in a param() block"
        }
        if ($null -ne $definition.Body.DynamicParamBlock) {
            throw "Action script $($File.Name) must not use a dynamicparam block in $function"
        }
        if ($seen.ContainsKey($function)) { throw "Action script $($File.Name) defines $function twice" }
        $seen[$function] = $true
        # Names compare without regard to case (a-b and ab both give AB/Ab). A name that is
        # already a command (the engine, a cmdlet, another module) is never replaced.
        $owner = $script:TuneupActionFunctions[$function]
        if ($null -ne $owner -and $owner -ne $name) {
            throw "Action script $($File.Name) defines $function, which action script '$owner' already defines"
        }
        if ($null -eq $owner -and $null -ne (Get-Command -Name $function -ErrorAction SilentlyContinue)) {
            throw "Action script $($File.Name) defines $function, which is already a command"
        }
    }
    foreach ($verb in 'Get', 'Test', 'Set', 'Restore') {
        $required = Get-TuneupActionFunctionName -Name $name -Verb $verb
        if (-not $seen.ContainsKey($required)) { throw "Action script $($File.Name) does not define $required" }
    }
    foreach ($definition in $definitions) {
        Set-Item -LiteralPath "Function:script:$($definition.Name)" -Value $definition.Body.GetScriptBlock()
        $script:TuneupActionFunctions[$definition.Name] = $name
    }
    $script:TuneupActionScripts[$name] = $File.FullName
}

function Import-TuneupActionLibrary {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    # Nothing is thrown for a script that cannot be loaded: the problem is kept (Get-TuneupActionLoadError)
    # and the next script is read. The same rule applies to the repository folder and to -ActionsPath.
    try {
        # -Filter '*.ps1' also matches names such as x.ps1xml (through their short names).
        $files = @(Get-ChildItem -LiteralPath $Path -Filter '*.ps1' -File | Where-Object { $_.Extension -eq '.ps1' } | Sort-Object Name)
    } catch {
        Set-TuneupActionLoadError -Name '*' -Path $Path -Message "the actions folder could not be read: $($_.Exception.Message)"
        return
    }
    foreach ($file in $files) {
        try {
            Import-TuneupActionScript -File $file
            # Loaded now: an error left by an earlier try of the same script no longer applies.
            $script:TuneupActionLoadErrors.Remove($file.BaseName)
        } catch {
            Set-TuneupActionLoadError -Name $file.BaseName -Path $file.FullName -Message $_.Exception.Message
        }
    }
}

function Get-TuneupActionCommand {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)][string]$Verb)
    $name = [string]$Tweak.set.script
    if ($name -cnotmatch $script:ActionNamePattern -or -not $script:TuneupActionScripts.ContainsKey($name)) {
        $problem = $(if ($name -cmatch $script:ActionNamePattern) { $script:TuneupActionLoadErrors[$name] })
        if ($null -ne $problem) { throw "Action script '$name' could not be loaded: $($problem.message)" }
        throw "Action script '$name' is not loaded"
    }
    Get-TuneupActionFunctionName -Name $name -Verb $Verb
}

function Test-ActionTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.script
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
    if ($name -cnotmatch $script:ActionNamePattern) { "has an invalid action script name '$name'" }
    elseif (-not $script:TuneupActionScripts.ContainsKey($name)) {
        $problem = $script:TuneupActionLoadErrors[$name]
        if ($null -ne $problem) { "action script '$name' could not be loaded: $($problem.message)" }
        else { "uses action script '$name', which is not in the actions folder" }
    }
}

function Get-ActionTweakState {
    param([Parameter(Mandatory)]$Tweak)
    & (Get-TuneupActionCommand -Tweak $Tweak -Verb 'Get') -Tweak $Tweak
}

function Test-ActionTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $result = @(& (Get-TuneupActionCommand -Tweak $Tweak -Verb 'Test') -Tweak $Tweak)
    if ($result.Count -ne 1 -or @('applied', 'not-applied', 'not-present') -cnotcontains [string]$result[0]) {
        throw "Action script '$($Tweak.set.script)' returned '$($result -join ', ')' from its test; expected applied, not-applied or not-present"
    }
    [string]$result[0]
}

function Set-ActionTweakDesired {
    param([Parameter(Mandatory)]$Tweak)
    & (Get-TuneupActionCommand -Tweak $Tweak -Verb 'Set') -Tweak $Tweak
}

function Restore-ActionTweakState {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$State)
    & (Get-TuneupActionCommand -Tweak $Tweak -Verb 'Restore') -Tweak $Tweak -State $State
}
