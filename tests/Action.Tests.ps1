BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Key = 'HKCU:\Software\windows-tuneup-test'
    Import-TuneupActionLibrary -Path (Join-Path $PSScriptRoot 'fixtures\actions')
    $script:Tweak = New-TestTweak -Id 'test.action' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'fixture-toggle' })
    function New-ActionFolder([hashtable]$Files) {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        foreach ($name in $Files.Keys) { [System.IO.File]::WriteAllText((Join-Path $dir $name), $Files[$name]) }
        $dir
    }
    function New-ContractFor([string]$Pascal) {
        @(
            "function Get-${Pascal}ActionState { param(`$Tweak) `$null }"
            "function Test-${Pascal}ActionState { param(`$Tweak) 'applied' }"
            "function Set-${Pascal}ActionDesired { param(`$Tweak) }"
            "function Restore-${Pascal}ActionState { param(`$Tweak, `$State) }"
        ) -join "`r`n"
    }
    $script:Contract = @'
function Get-BadOneActionState { param($Tweak) $null }
function Test-BadOneActionState { param($Tweak) 'applied' }
function Set-BadOneActionDesired { param($Tweak) }
function Restore-BadOneActionState { param($Tweak, $State) }
'@
}

Describe 'Action library' {
    AfterEach {
        if (Test-Path -LiteralPath $Key) { Remove-Item -LiteralPath $Key -Recurse -Force }
    }

    It 'turns kebab-case names into Pascal names' {
        ConvertTo-TuneupPascalName -Name 'fixture-toggle' | Should -Be 'FixtureToggle'
        ConvertTo-TuneupPascalName -Name 'win11-start' | Should -Be 'Win11Start'
        Get-TuneupActionFunctionName -Name 'fixture-toggle' -Verb 'Set' | Should -Be 'Set-FixtureToggleActionDesired'
    }

    It 'rejects a name that is not lowercase kebab case' {
        { ConvertTo-TuneupPascalName -Name 'Bad_Name' } | Should -Throw "*Invalid action script name 'Bad_Name'*"
    }

    It 'runs the loaded action through the dispatcher and undoes it' {
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
        $state = Get-TuneupState -Tweak $Tweak
        (Get-TuneupOutcome -Output @(Set-TuneupDesired -Tweak $Tweak)).rebootRequired | Should -BeTrue
        Test-TuneupState -Tweak $Tweak | Should -Be 'applied'
        Restore-TuneupState -Tweak $Tweak -State $state
        Test-TuneupState -Tweak $Tweak | Should -Be 'not-applied'
    }

    It 'never runs code while loading a script' {
        $marker = Join-Path $TestDrive 'ran.txt'
        $dir = New-ActionFolder @{ 'bad-one.ps1' = ($Contract + "`r`n[System.IO.File]::WriteAllText('$marker', 'x')") }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*bad-one.ps1 may only define functions*'
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'refuses a function outside the name space of its script' {
        $dir = New-ActionFolder @{ 'bad-one.ps1' = ($Contract + "`r`nfunction Test-TuneupTrustedItem { param(`$Path) `$true }") }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*defines Test-TuneupTrustedItem*'
        (& (Get-Module Tuneup) { Test-TuneupTrustedItem -Path 'C:\no\such\path' }) | Should -BeFalse
    }

    It 'refuses names reserved for the engine' {
        $dir = New-ActionFolder @{ 'tuneup.ps1' = 'function Get-TuneupActionCommand { param($Tweak) }' }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*reserved for the engine*'
    }

    It 'refuses a script without the four contract functions' {
        $dir = New-ActionFolder @{ 'bad-one.ps1' = 'function Get-BadOneActionState { param($Tweak) $null }' }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*does not define Test-BadOneActionState*'
    }

    It 'refuses a file name that is not kebab case' {
        $dir = New-ActionFolder @{ 'Bad_One.ps1' = $Contract }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw "*Invalid action script name 'Bad_One'*"
    }

    It 'refuses parameters declared outside a param block' {
        $inline = @'
function Get-BadOneActionState($Tweak) { $null }
function Test-BadOneActionState { param($Tweak) 'applied' }
function Set-BadOneActionDesired { param($Tweak) }
function Restore-BadOneActionState { param($Tweak, $State) }
'@
        $dir = New-ActionFolder @{ 'bad-one.ps1' = $inline }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*param() block*'
    }

    It 'refuses reserved names whatever their case' {
        $dir = New-ActionFolder @{ 'tune-up.ps1' = (New-ContractFor 'TuneUp') + "`r`nfunction Get-TuneUpActionCommand { param(`$Tweak) 1 }" }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*reserved for the engine*'
        $dir = New-ActionFolder @{ 'tuneup-two.ps1' = (New-ContractFor 'TuneupTwo') }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*reserved for the engine*'
    }

    It 'refuses a function that another action script already defines' {
        Import-TuneupActionLibrary -Path (New-ActionFolder @{ 'a-b.ps1' = (New-ContractFor 'AB') })
        $dir = New-ActionFolder @{ 'ab.ps1' = (New-ContractFor 'Ab') }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw "*defines Get-AbActionState, which action script 'a-b' already defines*"
    }

    It 'refuses a function that is a contract name of another action script' {
        Import-TuneupActionLibrary -Path (New-ActionFolder @{ 'foo-action-x.ps1' = (New-ContractFor 'FooActionX') })
        $dir = New-ActionFolder @{ 'foo.ps1' = ((New-ContractFor 'Foo') + "`r`nfunction Set-FooActionXActionDesired { param(`$Tweak) }") }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*defines Set-FooActionXActionDesired*'
    }

    It 'refuses a function that would shadow an existing command' {
        function global:Get-ShadowOneActionHelperRead { 'global' }
        try {
            $dir = New-ActionFolder @{ 'shadow-one.ps1' = ((New-ContractFor 'ShadowOne') + "`r`nfunction Get-ShadowOneActionHelperRead { param() 1 }") }
            { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*Get-ShadowOneActionHelperRead, which is already a command*'
        } finally {
            Remove-Item -LiteralPath 'Function:\global:Get-ShadowOneActionHelperRead'
        }
    }

    It 'allows helper functions named <Verb>-<Pascal>ActionHelper<Name>' {
        $dir = New-ActionFolder @{ 'helper-ok.ps1' = ((New-ContractFor 'HelperOk') + "`r`nfunction Get-HelperOkActionHelperRead { param() 7 }") }
        Import-TuneupActionLibrary -Path $dir
        (& (Get-Module Tuneup) { Get-HelperOkActionHelperRead }) | Should -Be 7
    }

    It 'reloads the same script without calling it a duplicate' {
        $dir = New-ActionFolder @{ 'again-one.ps1' = (New-ContractFor 'AgainOne') }
        Import-TuneupActionLibrary -Path $dir
        { Import-TuneupActionLibrary -Path $dir } | Should -Not -Throw
    }

    It 'refuses function names that are neither a contract name nor a helper (<Name>)' -TestCases @(
        @{ Name = 'Get-BadOneActionFoo' }
        @{ Name = 'Get-BadOneActionHelperActionX' }
        @{ Name = 'Get-BadOneActionStates' }
        @{ Name = 'Get-BadOne' }
    ) {
        param($Name)
        $dir = New-ActionFolder @{ 'bad-one.ps1' = ($Contract + "`r`nfunction $Name { param() }") }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw "*defines $Name*"
    }

    It 'refuses a function with a dynamicparam block' {
        $dynamic = $Contract + "`r`nfunction Get-BadOneActionHelperDyn { dynamicparam { } }"
        $dir = New-ActionFolder @{ 'bad-one.ps1' = $dynamic }
        { Import-TuneupActionLibrary -Path $dir } | Should -Throw '*dynamicparam*'
    }

    It 'only takes files whose extension is exactly .ps1' {
        $dir = New-ActionFolder @{ 'long-file-name.ps1xml' = '<Types />'; 'other-file.ps1.txt' = 'x' }
        { Import-TuneupActionLibrary -Path $dir } | Should -Not -Throw
        $tweak = New-TestTweak -Id 'test.xml' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'long-file-name' })
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match 'not in the actions folder'
    }

    It 'does not export the functions of action scripts' {
        # The module loads <root>\actions while it is imported, so a copy of the engine with an
        # actions folder next to it is imported in a separate process to see what it exports.
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $copy | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\engine') -Destination (Join-Path $copy 'engine') -Recurse
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\actions') -Destination (Join-Path $copy 'actions') -Recurse
        $module = Join-Path $copy 'engine\Tuneup.psm1'
        $command = "Import-Module '$module'; (Get-Module Tuneup).ExportedFunctions.Keys; '--'; & (Get-Module Tuneup) { Get-FixtureToggleActionState -Tweak ([pscustomobject]@{}) | Out-Null; 'loaded' }"
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -Command $command)
        $output -contains 'Get-TuneupState' | Should -BeTrue
        $output -contains 'Import-TuneupActionLibrary' | Should -BeTrue
        $output -contains 'loaded' | Should -BeTrue
        ($output | Where-Object { $_ -like '*FixtureToggle*' }) | Should -BeNullOrEmpty
    }

    It 'ignores a folder that does not exist' {
        { Import-TuneupActionLibrary -Path (Join-Path $TestDrive 'none') } | Should -Not -Throw
    }

    It 'says when an action is not loaded' {
        $other = New-TestTweak -Id 'test.other' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'not-loaded' })
        { Get-TuneupState -Tweak $other } | Should -Throw "*Action script 'not-loaded' is not loaded*"
    }

    It 'rejects a test function that answers something else' {
        $odd = @'
function Get-OddTestActionState { param($Tweak) $null }
function Test-OddTestActionState { param($Tweak) 'yes' }
function Set-OddTestActionDesired { param($Tweak) }
function Restore-OddTestActionState { param($Tweak, $State) }
'@
        Import-TuneupActionLibrary -Path (New-ActionFolder @{ 'odd-test.ps1' = $odd })
        $tweak = New-TestTweak -Id 'test.odd' -Type 'action' -Scope 'machine' -Set ([pscustomobject]@{ script = 'odd-test' })
        { Test-TuneupState -Tweak $tweak } | Should -Throw "*returned 'yes'*"
    }
}

Describe 'Action definition and registration' {
    It 'accepts a loaded script' {
        (Test-TuneupTweak -Tweak $Tweak) -join '; ' | Should -BeNullOrEmpty
    }

    It 'rejects <Problem>' -TestCases @(
        @{ Problem = 'a script that is not loaded'; Script = 'missing-one'; Scope = 'machine'; Message = "action script 'missing-one', which is not in the actions folder" }
        @{ Problem = 'a path as script name'; Script = '..\evil'; Scope = 'machine'; Message = 'invalid action script name' }
        @{ Problem = 'scope user'; Script = 'fixture-toggle'; Scope = 'user'; Message = 'must use scope machine' }
    ) {
        param($Script, $Scope, $Message)
        $tweak = New-TestTweak -Type 'action' -Scope $Scope -Set ([pscustomobject]@{ script = $Script })
        (Test-TuneupTweak -Tweak $tweak) -join '; ' | Should -Match ([regex]::Escape($Message))
    }

    It 'is a dispatched type that reads without elevation' {
        Get-TuneupHandlerName -Tweak $Tweak | Should -Be 'Action'
        (Get-TuneupHandler -Type 'action').ReadNeedsAdmin | Should -BeFalse
    }
}
