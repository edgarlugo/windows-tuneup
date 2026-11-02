BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en'
    $script:RealRules = Join-Path (Split-Path $PSScriptRoot -Parent) 'catalog\clean\rules.json'

    # A rule with every field it needs; the parameters change what a test is about.
    function New-TestCleanRule {
        param(
            [string]$Id = 'clean.test',
            [string]$Category = 'temp',
            [string]$Kind = 'files',
            [string]$Scope = 'user',
            [object[]]$Paths = @('%LOCALAPPDATA%\Cache'),
            [hashtable]$Extra = @{}
        )
        $rule = [ordered]@{
            id = $Id; category = $Category; kind = $Kind; scope = $Scope; paths = $Paths
            title = @{ es = 'Prueba'; en = 'Test' }; why = @{ es = 'Porque'; en = 'Because' }; sources = @('https://example.com/')
        }
        foreach ($key in $Extra.Keys) { $rule[$key] = $Extra[$key] }
        [pscustomobject]$rule | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }
    function New-TestCleanRuleSet([object[]]$Rules) {
        [pscustomobject]@{ schemaVersion = 1; about = 'x'; rules = @($Rules) }
    }
    # Writes a file with a size and an age in days.
    function New-TestFile([string]$Path, [int]$Bytes = 10, [int]$AgeDays = 30) {
        $folder = Split-Path $Path -Parent
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        [System.IO.File]::WriteAllBytes($Path, (New-Object byte[] $Bytes))
        $time = [datetime]::UtcNow.AddDays(-$AgeDays)
        [System.IO.File]::SetLastWriteTimeUtc($Path, $time)
        $Path
    }
    function Set-TestFolderAge([string]$Path, [int]$AgeDays) {
        [System.IO.Directory]::SetLastWriteTimeUtc($Path, [datetime]::UtcNow.AddDays(-$AgeDays))
    }
    # Points the variables of the rules at folders of the test, and the rules at a file of the test.
    function Use-TestCleanRoot([string]$Root, [object[]]$Rules) {
        $map = @{}
        foreach ($name in 'LOCALAPPDATA', 'APPDATA', 'USERPROFILE', 'PROGRAMDATA', 'SYSTEMROOT', 'SYSTEMDRIVE') {
            $map[$name] = Join-Path $Root $name.ToLowerInvariant()
            New-Item -ItemType Directory -Path $map[$name] -Force | Out-Null
        }
        $rulesFile = Join-Path $Root 'rules.json'
        if ($Rules) { [System.IO.File]::WriteAllText($rulesFile, ((New-TestCleanRuleSet $Rules) | ConvertTo-Json -Depth 8)) }
        InModuleScope Tuneup -Parameters @{ Map = $map; RulesFile = $rulesFile } {
            param($Map, $RulesFile)
            $script:CleanVariableOverride = $Map
            $script:CleanRulesPath = $RulesFile
        }
        $map
    }
    function Reset-TestCleanRoot {
        InModuleScope Tuneup -Parameters @{ Real = $RealRules } {
            param($Real)
            $script:CleanVariableOverride = @{}
            $script:CleanRulesPath = $Real
        }
    }
    function New-TestCleanContext([switch]$Json, $Environment = (New-TestEnvironment -IsAdmin $false), [object[]]$Answers = @()) {
        $context = New-TuneupContext -Json:$Json -Io (New-TestIo -Answers $Answers)
        $context.Environment = $Environment
        $context
    }
    function Invoke-TestClean($Context, [string[]]$Remove = @(), [switch]$PlanOnly, [switch]$Yes) {
        $output = @(Invoke-TuneupCleanCommand -Context $Context -Remove $Remove -PlanOnly:$PlanOnly -Yes:$Yes)
        ($output -join "`n") | ConvertFrom-Json
    }
}

Describe 'catalog/clean/rules.json' {
    It 'is valid, and every rule says why in both languages and cites a source' {
        $rules = Import-TuneupCleanRuleSet -Path $RealRules
        @($rules.rules).Count | Should -BeGreaterThan 15
        foreach ($rule in $rules.rules) {
            $rule.id | Should -Match '^clean\.[a-z0-9-]+$'
            $rule.why.es | Should -Not -BeNullOrEmpty
            $rule.why.en | Should -Not -BeNullOrEmpty
        }
    }

    It 'never names cookies, passwords, history, sessions or the logs of CBS and DISM' {
        $text = [System.IO.File]::ReadAllText($RealRules)
        $paths = @((ConvertFrom-Json $text).rules | ForEach-Object { $_.paths }) -join "`n"
        foreach ($word in 'Cookies', 'Login Data', 'History', 'Sessions', 'places.sqlite', 'Logs\CBS', 'Logs\DISM') { $paths.Contains($word) | Should -BeFalse -Because $word }
    }

    It 'only measures what is in the report category, each with how to free it by hand' {
        foreach ($rule in (Import-TuneupCleanRuleSet -Path $RealRules).rules) {
            $measured = @('report', 'recycle-bin') -contains $rule.kind
            ($rule.category -eq 'report') | Should -Be $measured -Because $rule.id
            if ($measured) { $rule.hint.es | Should -Not -BeNullOrEmpty -Because $rule.id }
        }
    }
}

Describe 'Test-TuneupCleanRuleSet' {
    It 'accepts a valid rule' {
        @(Test-TuneupCleanRuleSet -Rules (New-TestCleanRuleSet @(New-TestCleanRule))) | Should -BeNullOrEmpty
    }

    It 'reports <Name>' -TestCases @(
        @{ Name = 'an unknown field'; Rule = { New-TestCleanRule -Extra @{ path = 'x' } }; Expected = "unknown field 'path'" }
        @{ Name = 'a variable of the other scope'; Rule = { New-TestCleanRule -Scope 'user' -Paths @('%SYSTEMROOT%\Temp') }; Expected = 'cannot use %SYSTEMROOT% with scope user' }
        @{ Name = 'a path that is only a variable'; Rule = { New-TestCleanRule -Paths @('%LOCALAPPDATA%') }; Expected = 'must start with a variable and name' }
        @{ Name = 'a relative segment'; Rule = { New-TestCleanRule -Paths @('%LOCALAPPDATA%\..\Documents') }; Expected = 'empty or relative segment' }
        @{ Name = 'a wildcard inside a segment'; Rule = { New-TestCleanRule -Paths @('%LOCALAPPDATA%\Cache*') }; Expected = 'wildcard' }
        @{ Name = 'a path that ends with *'; Rule = { New-TestCleanRule -Paths @('%LOCALAPPDATA%\Cache\*') }; Expected = 'cannot end with *' }
        @{ Name = 'the logs of CBS'; Rule = { New-TestCleanRule -Scope 'machine' -Paths @('%SYSTEMROOT%\Logs\CBS') }; Expected = 'never cleaned' }
        @{ Name = 'the documents of the user'; Rule = { New-TestCleanRule -Paths @('%USERPROFILE%\Documents\Cache') }; Expected = 'never cleaned' }
        @{ Name = 'a report without a hint'; Rule = { New-TestCleanRule -Category 'report' -Kind 'report' }; Expected = 'needs a hint' }
        @{ Name = 'a hint on a rule that deletes'; Rule = { New-TestCleanRule -Extra @{ hint = @{ es = 'a'; en = 'b' } } }; Expected = 'cannot have a hint' }
        @{ Name = 'a report outside the report category'; Rule = { New-TestCleanRule -Kind 'report' -Extra @{ hint = @{ es = 'a'; en = 'b' } } }; Expected = 'category report exactly' }
        @{ Name = 'a negative age'; Rule = { New-TestCleanRule -Extra @{ minAgeDays = -1 } }; Expected = 'minAgeDays' }
        @{ Name = 'a process name with a path'; Rule = { New-TestCleanRule -Extra @{ apps = @('C:\x.exe') } }; Expected = 'apps has a name' }
        @{ Name = 'a filter on another kind'; Rule = { New-TestCleanRule -Scope 'machine' -Kind 'lghub-depots' -Category 'installers' -Paths @('%PROGRAMDATA%\LGHUB\depots') -Extra @{ filter = '*.db' } }; Expected = 'cannot have filter' }
        @{ Name = 'a source that is not https'; Rule = { New-TestCleanRule -Extra @{ sources = @('http://example.com') } }; Expected = 'https' }
    ) {
        param($Rule, $Expected)
        $problems = @(Test-TuneupCleanRuleSet -Rules (New-TestCleanRuleSet @(& $Rule))) -join '; '
        $problems | Should -BeLike "*$Expected*"
    }

    It 'reports an id that is there twice' {
        (@(Test-TuneupCleanRuleSet -Rules (New-TestCleanRuleSet @((New-TestCleanRule), (New-TestCleanRule)))) -join '; ') | Should -BeLike '*twice*'
    }

    It 'stops the command when the rules are not valid' {
        $file = Join-Path $TestDrive 'bad.json'
        [System.IO.File]::WriteAllText($file, ((New-TestCleanRuleSet @(New-TestCleanRule -Paths @('C:\Windows'))) | ConvertTo-Json -Depth 8))
        { Import-TuneupCleanRuleSet -Path $file } | Should -Throw '*are not valid*'
    }
}

Describe 'Resolve-TuneupCleanPath' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:Map = Use-TestCleanRoot -Root $Root
    }
    AfterEach { Reset-TestCleanRoot }

    It 'gives every folder a * names, and nothing that is missing' {
        New-Item -ItemType Directory -Path (Join-Path $Map.LOCALAPPDATA 'App\User Data\Default\Cache'), (Join-Path $Map.LOCALAPPDATA 'App\User Data\Profile 1\Cache') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Map.LOCALAPPDATA 'App\User Data\Empty') -Force | Out-Null
        $found = @(Resolve-TuneupCleanPath -Path '%LOCALAPPDATA%\App\User Data\*\Cache')
        $found.Count | Should -Be 2
        @(Resolve-TuneupCleanPath -Path '%LOCALAPPDATA%\Missing\Cache').Count | Should -Be 0
    }

    It 'never follows a junction, at any level' {
        $target = Join-Path $Root 'elsewhere'
        New-Item -ItemType Directory -Path (Join-Path $target 'Cache') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Map.LOCALAPPDATA 'App\User Data') -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $Map.LOCALAPPDATA 'App\User Data\Linked') -Target $target | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $Map.LOCALAPPDATA 'Direct') -Target $target | Out-Null
        @(Resolve-TuneupCleanPath -Path '%LOCALAPPDATA%\App\User Data\*\Cache').Count | Should -Be 0
        @(Resolve-TuneupCleanPath -Path '%LOCALAPPDATA%\Direct\Cache').Count | Should -Be 0
    }
}

Describe 'Invoke-TuneupCleanRule' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:Map = Use-TestCleanRoot -Root $Root
        $script:Cache = Join-Path $Map.LOCALAPPDATA 'Cache'
    }
    AfterEach { Reset-TestCleanRoot }

    It 'measures without deleting anything' {
        New-TestFile (Join-Path $Cache 'a.bin') -Bytes 100 | Out-Null
        New-TestFile (Join-Path $Cache 'sub\b.bin') -Bytes 50 | Out-Null
        $measured = Invoke-TuneupCleanRule -Rule (New-TestCleanRule)
        $measured.Tally.Files | Should -Be 2
        $measured.Tally.Bytes | Should -Be 150
        Test-Path -LiteralPath (Join-Path $Cache 'a.bin') | Should -BeTrue
    }

    It 'deletes old files and the folders it emptied, and keeps the folder of the rule' {
        New-TestFile (Join-Path $Cache 'a.bin') | Out-Null
        New-TestFile (Join-Path $Cache 'sub\deep\b.bin') | Out-Null
        Set-TestFolderAge (Join-Path $Cache 'sub\deep') 30
        Set-TestFolderAge (Join-Path $Cache 'sub') 30
        $done = (Invoke-TuneupCleanRule -Rule (New-TestCleanRule) -Delete).Tally
        $done.Deleted | Should -Be 2
        $done.FreedBytes | Should -Be 20
        Test-Path -LiteralPath (Join-Path $Cache 'sub') | Should -BeFalse
        Test-Path -LiteralPath $Cache | Should -BeTrue
    }

    It 'keeps what changed within minAgeDays' {
        New-TestFile (Join-Path $Cache 'old.bin') -AgeDays 10 | Out-Null
        New-TestFile (Join-Path $Cache 'new.bin') -AgeDays 1 | Out-Null
        $done = (Invoke-TuneupCleanRule -Rule (New-TestCleanRule -Extra @{ minAgeDays = 7 }) -Delete).Tally
        $done.Deleted | Should -Be 1
        Test-Path -LiteralPath (Join-Path $Cache 'new.bin') | Should -BeTrue
    }

    It 'follows filter and recurse' {
        New-TestFile (Join-Path $Cache 'thumbcache_1.db') | Out-Null
        New-TestFile (Join-Path $Cache 'iconcache_1.db') | Out-Null
        New-TestFile (Join-Path $Cache 'sub\thumbcache_2.db') | Out-Null
        $done = (Invoke-TuneupCleanRule -Rule (New-TestCleanRule -Extra @{ filter = 'thumbcache_*.db'; recurse = $false }) -Delete).Tally
        $done.Deleted | Should -Be 1
        Test-Path -LiteralPath (Join-Path $Cache 'iconcache_1.db') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $Cache 'sub\thumbcache_2.db') | Should -BeTrue
    }

    It 'keeps the files of the folder itself with topFolders, and what exclude names' {
        New-TestFile (Join-Path $Cache 'status.json') | Out-Null
        New-TestFile (Join-Path $Cache 'config\settings.json') | Out-Null
        New-TestFile (Join-Path $Cache 'f00d\driver.exe') -Bytes 1000 | Out-Null
        $done = (Invoke-TuneupCleanRule -Rule (New-TestCleanRule -Extra @{ topFolders = $true; exclude = @('config') }) -Delete).Tally
        $done.Deleted | Should -Be 1
        $done.FreedBytes | Should -Be 1000
        Test-Path -LiteralPath (Join-Path $Cache 'status.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $Cache 'config\settings.json') | Should -BeTrue
    }

    It 'never deletes through a junction inside the folder' {
        $outside = New-TestFile (Join-Path $Root 'precious\keep.txt')
        New-Item -ItemType Directory -Path $Cache -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $Cache 'link') -Target (Split-Path $outside -Parent) | Out-Null
        $done = (Invoke-TuneupCleanRule -Rule (New-TestCleanRule) -Delete).Tally
        $done.Files | Should -Be 0
        Test-Path -LiteralPath $outside | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $Cache 'link') | Should -BeTrue
    }

    It 'keeps and counts a file that is open, and a read-only one' {
        $open = New-TestFile (Join-Path $Cache 'open.bin')
        $readOnly = New-TestFile (Join-Path $Cache 'ro.bin')
        Set-ItemProperty -LiteralPath $readOnly -Name IsReadOnly -Value $true
        $stream = [System.IO.File]::Open($open, 'Open', 'Read', 'None')
        try {
            $done = (Invoke-TuneupCleanRule -Rule (New-TestCleanRule) -Delete).Tally
        } finally {
            $stream.Dispose()
            Set-ItemProperty -LiteralPath $readOnly -Name IsReadOnly -Value $false
        }
        $done.Kept | Should -Be 2
        $done.Deleted | Should -Be 0
        Test-Path -LiteralPath $open | Should -BeTrue
    }

    It 'only measures a report, even with -Delete' {
        $file = New-TestFile (Join-Path $Map.SYSTEMDRIVE 'hiberfil.sys') -Bytes 4096
        $rule = New-TestCleanRule -Category 'report' -Kind 'report' -Scope 'machine' -Paths @('%SYSTEMDRIVE%\hiberfil.sys') -Extra @{ hint = @{ es = 'a'; en = 'b' } }
        $done = (Invoke-TuneupCleanRule -Rule $rule -Delete).Tally
        $done.Bytes | Should -Be 4096
        $done.Deleted | Should -Be 0
        Test-Path -LiteralPath $file | Should -BeTrue
    }

    Context 'G HUB' {
        BeforeEach {
            $script:Depots = Join-Path $Map.PROGRAMDATA 'LGHUB\depots'
            foreach ($build in '100', '200', '300', '400') {
                New-TestFile (Join-Path $Depots "$build\lghub.exe") -Bytes 100 | Out-Null
                Set-TestFolderAge (Join-Path $Depots $build) 30
            }
            $script:LghubRule = New-TestCleanRule -Category 'installers' -Kind 'lghub-depots' -Scope 'machine' -Paths @('%PROGRAMDATA%\LGHUB\depots') -Extra @{ minAgeDays = 1 }
        }

        It 'keeps the versions current.json and next.json name, and what is recent' {
            Set-Content -LiteralPath (Join-Path $Map.PROGRAMDATA 'LGHUB\current.json') -Value '{ "buildId": "100" }'
            Set-Content -LiteralPath (Join-Path $Map.PROGRAMDATA 'LGHUB\next.json') -Value '{ "buildId": "400" }'
            Set-TestFolderAge (Join-Path $Depots '300') 0
            $done = (Invoke-TuneupCleanRule -Rule $LghubRule -Delete).Tally
            $done.Deleted | Should -Be 1
            @(Get-ChildItem -LiteralPath $Depots -Name | Sort-Object) | Should -Be @('100', '300', '400')
        }

        It 'deletes nothing when it cannot tell which version is installed' {
            Set-Content -LiteralPath (Join-Path $Map.PROGRAMDATA 'LGHUB\current.json') -Value 'not json'
            $measured = Invoke-TuneupCleanRule -Rule $LghubRule -Delete
            $measured.Reason | Should -Be 'unreadable'
            @(Get-ChildItem -LiteralPath $Depots).Count | Should -Be 4
        }
    }
}

Describe 'Invoke-TuneupCleanCommand' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $userRule = New-TestCleanRule -Id 'clean.user-cache' -Paths @('%LOCALAPPDATA%\Cache') -Extra @{ apps = @('tuneup-test-app') }
        $machineRule = New-TestCleanRule -Id 'clean.machine-cache' -Scope 'machine' -Paths @('%PROGRAMDATA%\Cache')
        $reportRule = New-TestCleanRule -Id 'clean.report-big' -Category 'report' -Kind 'report' -Paths @('%USERPROFILE%\Downloads') -Extra @{ hint = @{ es = 'a mano'; en = 'by hand' } }
        $script:Map = Use-TestCleanRoot -Root $Root -Rules @($userRule, $machineRule, $reportRule)
        $script:UserFile = New-TestFile (Join-Path $Map.LOCALAPPDATA 'Cache\a.bin') -Bytes 300
        $script:MachineFile = New-TestFile (Join-Path $Map.PROGRAMDATA 'Cache\b.bin') -Bytes 200
        New-TestFile (Join-Path $Map.USERPROFILE 'Downloads\setup.exe') -Bytes 5000 | Out-Null
        Mock -ModuleName Tuneup Get-TuneupCleanBusy { [pscustomobject]@{ Apps = [string[]]@(); Services = [string[]]@() } }
    }
    AfterEach { Reset-TestCleanRoot }

    It 'lists every rule with its size, and changes nothing' {
        $document = Invoke-TestClean (New-TestCleanContext -Json)
        $document.command | Should -Be 'clean'
        $document.summary.total | Should -Be 3
        $user = $document.rules | Where-Object { $_.id -eq 'clean.user-cache' }
        $user.bytes | Should -Be 300
        $user.canRemove | Should -BeTrue
        $user.reason | Should -BeNullOrEmpty
        ($document.rules | Where-Object { $_.id -eq 'clean.machine-cache' }).reason | Should -Be 'needs-admin'
        ($document.rules | Where-Object { $_.id -eq 'clean.report-big' }).reason | Should -Be 'report-only'
        $document.summary.reportBytes | Should -Be 5000
        $document.removal | Should -BeNullOrEmpty
        Test-Path -LiteralPath $UserFile | Should -BeTrue
    }

    It 'refuses <Name> before deleting anything' -TestCases @(
        @{ Name = 'an id that is not a rule'; Ids = @('clean.user-cache', 'clean.nope'); Admin = $true; Session = $true; Reason = $null; Message = '*clean.nope*' }
        @{ Name = 'a rule that is only measured'; Ids = @('clean.report-big'); Admin = $true; Session = $true; Reason = $null; Message = '*only measured*' }
        @{ Name = 'a rule of the machine without administrator'; Ids = @('clean.user-cache', 'clean.machine-cache'); Admin = $false; Session = $true; Reason = 'needs-admin'; Message = '*clean.machine-cache*' }
        @{ Name = 'a rule of the user elevated as another account'; Ids = @('clean.user-cache'); Admin = $true; Session = $false; Reason = 'session-user'; Message = '*clean.user-cache*' }
    ) {
        param($Ids, $Admin, $Session, $Reason, $Message)
        $context = New-TestCleanContext -Json -Environment (New-TestEnvironment -IsAdmin $Admin -IsSessionUser $Session)
        $result = Invoke-TestClean $context -Remove $Ids -Yes
        $context.ExitCode | Should -Be 1
        $result.command | Should -Be 'error'
        $result.message | Should -BeLike $Message
        if ($Reason) { $result.reason | Should -Be $Reason }
        Test-Path -LiteralPath $UserFile | Should -BeTrue
        Test-Path -LiteralPath $MachineFile | Should -BeTrue
    }

    It 'asks for -Yes with -Json' {
        $context = New-TestCleanContext -Json
        (Invoke-TestClean $context -Remove @('clean.user-cache')).message | Should -BeLike '*-Yes*'
        Test-Path -LiteralPath $UserFile | Should -BeTrue
    }

    It 'gives what -WhatIf would delete, deleting nothing, also for a rule of the machine without administrator' {
        $context = New-TestCleanContext -Json
        $document = Invoke-TestClean $context -Remove @('clean.user-cache', 'CLEAN.MACHINE-CACHE') -PlanOnly
        $context.ExitCode | Should -Be 0
        $document.removal.planOnly | Should -BeTrue
        ($document.removal.results | Where-Object { $_.id -eq 'clean.user-cache' }).status | Should -Be 'planned'
        ($document.removal.results | Where-Object { $_.id -eq 'clean.machine-cache' }).reason | Should -Be 'needs-admin'
        $document.removal.freedBytes | Should -Be 300
        Test-Path -LiteralPath $UserFile | Should -BeTrue
    }

    It 'deletes what -Remove names with -Yes, and only that' {
        $context = New-TestCleanContext -Json -Environment (New-TestEnvironment -IsAdmin $true)
        $document = Invoke-TestClean $context -Remove @('clean.user-cache') -Yes
        $context.ExitCode | Should -Be 0
        $result = @($document.removal.results)[0]
        $result.status | Should -Be 'removed'
        $result.freedBytes | Should -Be 300
        $result.deletedFiles | Should -Be 1
        $document.removal.freedBytes | Should -Be 300
        Test-Path -LiteralPath $UserFile | Should -BeFalse
        Test-Path -LiteralPath $MachineFile | Should -BeTrue
    }

    It 'leaves a rule whose program is open, and ends with code 2' {
        Mock -ModuleName Tuneup Get-TuneupCleanBusy { [pscustomobject]@{ Apps = [string[]]@('tuneup-test-app'); Services = [string[]]@() } }
        $context = New-TestCleanContext -Json
        $document = Invoke-TestClean $context -Remove @('clean.user-cache') -Yes
        $context.ExitCode | Should -Be 2
        $result = @($document.removal.results)[0]
        $result.status | Should -Be 'skipped'
        $result.reason | Should -Be 'app-running'
        $result.runningApps | Should -Be @('tuneup-test-app')
        Test-Path -LiteralPath $UserFile | Should -BeTrue
    }

    It 'asks before deleting, and deletes nothing when the answer is no' {
        $context = New-TestCleanContext -Answers @('n')
        Invoke-TuneupCleanCommand -Context $context -Remove @('clean.user-cache') | Out-Null
        $context.ExitCode | Should -Be 1
        ($context.Io.Output -join "`n") | Should -BeLike '*cannot be undone*'
        Test-Path -LiteralPath $UserFile | Should -BeTrue
    }

    It 'deletes after a yes, and says what it freed' {
        $context = New-TestCleanContext -Answers @('y')
        Invoke-TuneupCleanCommand -Context $context -Remove @('clean.user-cache') 6>&1 | Out-Null
        $context.ExitCode | Should -Be 0
        Test-Path -LiteralPath $UserFile | Should -BeFalse
    }

    It 'warns without administrator that what belongs to the machine is not deleted' {
        $document = Invoke-TestClean (New-TestCleanContext -Json)
        @($document.warnings) -join ' ' | Should -BeLike '*Without administrator*'
    }

    It 'is offered by option 7 of the menu, which deletes only what is picked' {
        $context = New-TestCleanContext -Environment (New-TestEnvironment -IsAdmin $true) -Answers @('7', 'n', '1', '', 'y', '', '0')
        $context.Menu = $true
        Invoke-TuneupMenu -Context $context 6>&1 | Out-Null
        Test-Path -LiteralPath $UserFile | Should -BeFalse
        Test-Path -LiteralPath $MachineFile | Should -BeTrue
    }
}

Describe 'Format-TuneupCleanSize' {
    It 'gives <Expected> for <Bytes> bytes in <Lang>' -TestCases @(
        @{ Bytes = 1536; Lang = 'en'; Expected = '2 KB' }
        @{ Bytes = 350MB; Lang = 'en'; Expected = '350 MB' }
        @{ Bytes = 1.44GB; Lang = 'en'; Expected = '1.4 GB' }
        @{ Bytes = 1.44GB; Lang = 'es'; Expected = '1,4 GB' }
    ) {
        param($Bytes, $Lang, $Expected)
        Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang $Lang
        try { Format-TuneupCleanSize -Bytes ([long]$Bytes) | Should -Be $Expected }
        finally { Initialize-TuneupI18n -Root (Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n') -Lang 'en' }
    }
}
