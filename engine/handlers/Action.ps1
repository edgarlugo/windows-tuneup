$script:ActionNamePattern = '^[a-z0-9]+(-[a-z0-9]+)*$'
# Loaded action scripts: name -> file.
$script:TuneupActionScripts = @{}

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

function Import-TuneupActionLibrary {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $Path -Filter '*.ps1' -File | Sort-Object Name) {
        $name = $file.BaseName
        $pascal = ConvertTo-TuneupPascalName -Name $name
        if ($pascal -clike 'Tuneup*') { throw "Action script $($file.Name): names starting with tuneup are reserved for the engine" }
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "Action script $($file.Name) has a syntax error: $($parseErrors[0].Message)" }
        # The file is never run: only its function definitions are taken, so loading it cannot
        # execute code, and the name check keeps it from replacing functions of the engine.
        $onlyFunctions = ($null -eq $ast.ParamBlock -and $null -eq $ast.BeginBlock -and $null -eq $ast.ProcessBlock -and
            $null -eq $ast.DynamicParamBlock -and -not @($ast.UsingStatements).Count)
        $definitions = New-Object System.Collections.Generic.List[object]
        if ($null -ne $ast.EndBlock) {
            foreach ($statement in $ast.EndBlock.Statements) {
                if ($statement -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $onlyFunctions = $false; break }
                $definitions.Add($statement)
            }
        }
        if (-not $onlyFunctions) { throw "Action script $($file.Name) may only define functions" }
        foreach ($definition in $definitions) {
            if ($definition.Name -cnotmatch "^[A-Z][a-z]+-$($pascal)Action[A-Za-z0-9]*$") {
                throw "Action script $($file.Name) defines $($definition.Name); its functions must be named <Verb>-$($pascal)Action..."
            }
            if ($definition.IsFilter -or $definition.IsWorkflow) {
                throw "Action script $($file.Name) must define $($definition.Name) as a plain function"
            }
            if ($null -ne $definition.Parameters) {
                throw "Action script $($file.Name) must declare the parameters of $($definition.Name) in a param() block"
            }
        }
        $defined = @($definitions | ForEach-Object { $_.Name })
        foreach ($verb in 'Get', 'Test', 'Set', 'Restore') {
            $required = Get-TuneupActionFunctionName -Name $name -Verb $verb
            if ($defined -cnotcontains $required) { throw "Action script $($file.Name) does not define $required" }
        }
        foreach ($definition in $definitions) {
            Set-Item -LiteralPath "Function:script:$($definition.Name)" -Value $definition.Body.GetScriptBlock()
        }
        $script:TuneupActionScripts[$name] = $file.FullName
    }
}

function Get-TuneupActionCommand {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)][string]$Verb)
    $name = [string]$Tweak.set.script
    if ($name -cnotmatch $script:ActionNamePattern -or -not $script:TuneupActionScripts.ContainsKey($name)) {
        throw "Action script '$name' is not loaded"
    }
    Get-TuneupActionFunctionName -Name $name -Verb $Verb
}

function Test-ActionTweakDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $name = [string]$Tweak.set.script
    if ($Tweak.scope -ne 'machine') { 'must use scope machine' }
    if ($name -cnotmatch $script:ActionNamePattern) { "has an invalid action script name '$name'" }
    elseif (-not $script:TuneupActionScripts.ContainsKey($name)) { "uses action script '$name', which is not in the actions folder" }
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
