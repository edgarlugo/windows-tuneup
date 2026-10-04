BeforeDiscovery {
    $script:Elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script:Version = Get-TuneupVersion
    $script:Top = "windows-tuneup-$Version"

    function Invoke-Package([string]$Output, [string]$From = $Repo, [switch]$Release) {
        # Its errors come on standard error; with Stop, Windows PowerShell 5.1 would throw on the first line.
        $ErrorActionPreference = 'Continue'
        $flag = $(if ($Release) { ' -Release' } else { '' })
        & $PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '$From\build\package.ps1' -OutputPath '$Output'$flag | ConvertTo-Json" 2>&1 | Out-String
    }
    # Runs an installer the way people do (powershell -File) and gives its exit code and output.
    function Invoke-Installer([string]$Installer, [string[]]$Arguments, [string]$WorkingFolder = $TestDrive) {
        # Its errors come on standard error; with Stop, Windows PowerShell 5.1 would throw on the first line.
        $ErrorActionPreference = 'Continue'
        Push-Location -LiteralPath $WorkingFolder
        try {
            $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File $Installer @Arguments 2>&1
        } finally {
            Pop-Location
        }
        $text = $output | Out-String
        # Flat: the output without any whitespace. An error that comes through a console is wrapped at
        # its width (even inside a word), so messages are matched against it (Get-Flat on both sides).
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $text; Flat = (Get-Flat $text) }
    }
    # Runs an installer inside a session, as a script (& or .) of a powershell -Command, from -Location
    # while the process folder is -ProcessFolder; after it, the session writes the errors it holds, whether
    # PSModulePath came back and how many variables of the installer were left in it.
    function Invoke-InstallerInSession([string]$Operator, [string]$Installer, [string]$Arguments, [string]$Location = $TestDrive, [string]$ProcessFolder = $TestDrive) {
        $ErrorActionPreference = 'Continue'
        $command = "`$before = `$env:PSModulePath; Set-Location -LiteralPath '$Location'; " +
            "`$process = [Environment]::CurrentDirectory; $Operator '$Installer' $Arguments; " +
            "'errors=' + `$Error.Count; `$Error | ForEach-Object { 'error: ' + `$_.ToString() }; " +
            "'modulepath=' + (`$before -eq `$env:PSModulePath); 'variables=' + @(Get-Variable -Name 'windowsTuneup*').Count; " +
            "'process=' + `$process"
        Push-Location -LiteralPath $ProcessFolder
        try {
            $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1
        } finally {
            Pop-Location
        }
        $text = $output | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $text; Flat = (Get-Flat $text) }
    }
    function Get-Flat([string]$Text) { $Text -replace '\s+', '' }
    function Get-ZipEntry([string]$Path) {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { @($archive.Entries | ForEach-Object { $_.FullName }) } finally { $archive.Dispose() }
    }
    # A folder with windows-tuneup-<version>.zip holding the given entries; gives the SHA256 of the zip.
    function New-TestZip([string]$Folder, [string]$ZipVersion, [string[]]$Names) {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        $zip = Join-Path $Folder "windows-tuneup-$ZipVersion.zip"
        $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Names) {
                $writer = New-Object System.IO.StreamWriter -ArgumentList $archive.CreateEntry($name).Open()
                try { $writer.Write('x') } finally { $writer.Dispose() }
            }
        } finally {
            $archive.Dispose()
        }
        (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    }
    # What the installer leaves next to a destination while it works (and must not leave after).
    function Get-Leftover([string]$Destination) {
        @(Get-ChildItem -LiteralPath (Split-Path $Destination -Parent) -Force | Where-Object { $_.Name -like "$(Split-Path $Destination -Leaf).new-*" -or $_.Name -like "$(Split-Path $Destination -Leaf).old-*" })
    }
    # Elevated, a destination must be under folders only administrators can change: TestDrive is not,
    # and neither is %SystemRoot%\Temp on a GitHub runner (Users can rename or delete it there). The
    # folder goes at the root of the system drive, or under Program Files when the root is not trusted,
    # with the access list the installer gives its own folders; AfterAll removes it.
    function New-TrustedParent {
        $name = 'windows-tuneup-test-' + [guid]::NewGuid().ToString('N')
        $candidates = @((Join-Path ($env:SystemDrive + '\') $name), (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) $name))
        # The folders above a candidate decide (the candidate itself is created with the installer's access list).
        $path = @($candidates | Where-Object { -not (Get-InstallParentProblem -Path $_) } | Select-Object -First 1)[0]
        if (-not $path) { throw "No folder that only administrators can change was found for the test: $(Get-InstallParentProblem -Path $candidates[0])" }
        New-InstallFolder -Path $path -Security (New-InstallFolderSecurity)
        $script:TrustedParents += $path
        $path
    }
    $script:TrustedParents = @()
    $script:IsElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    # Where a test installs: TestDrive, or elevated a trusted folder (the installer refuses TestDrive there).
    function Get-TestDestination([string]$Name) {
        if ($IsElevated) { Join-Path (New-TrustedParent) $Name } else { Join-Path $TestDrive $Name }
    }

    # The checks of the installer live inside it (it is one file); they are loaded from its syntax tree.
    $installerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'install.ps1'), [ref]$null, [ref]$null)
    foreach ($functionName in 'Get-InstallFolderProblem', 'Get-InstallFolderWriter', 'Get-InstallParentProblem', 'New-InstallFolderSecurity', 'New-InstallFolder', 'Get-InstallEntryProblem') {
        $definition = $installerAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $true)
        if ($definition) { . ([scriptblock]::Create($definition.Extent.Text)) }
    }

    $script:Dist = Join-Path $TestDrive 'dist'
    $script:Built = Invoke-Package $Dist | ConvertFrom-Json
}

AfterAll {
    foreach ($path in $TrustedParents) {
        if ([System.IO.Directory]::Exists($path)) { [System.IO.Directory]::Delete($path, $true) }
    }
}

Describe 'build/package.ps1' {
    It 'packs only what runs and what people read, under one folder' {
        $entries = @(Get-ZipEntry $Built.Zip)
        @($entries | Where-Object { -not $_.StartsWith("$Top/") }).Count | Should -Be 0
        $names = @($entries | ForEach-Object { $_.Substring($Top.Length + 1) })
        foreach ($expected in 'tuneup.ps1', 'README.md', 'LICENSE', 'engine/Tuneup.psm1', 'engine/Commands.ps1', 'engine/Menu.ps1',
            'engine/handlers/Registry.ps1', 'i18n/es.json', 'i18n/en.json', 'catalog/apps.json', 'profiles/lite.json',
            'actions/onedrive.ps1', 'docs/es/profiles.md', 'docs/en/catalog.md', 'docs/json-contract.md') {
            $names | Should -Contain $expected
        }
        foreach ($folder in 'tests/', 'build/', '.github/', 'docs/superpowers/', 'catalog/notes/', 'plugins/', '.claude-plugin/') {
            @($names | Where-Object { $_.StartsWith($folder) }).Count | Should -Be 0 -Because $folder
        }
        @($names | Where-Object { $_ -match '^docs/[^/]+$' }) -join ',' | Should -Be 'docs/json-contract.md'
        # Every page that the README links to is in the installed copy too.
        $links = @([regex]::Matches([System.IO.File]::ReadAllText((Join-Path $Repo 'README.md')), '\]\(([^)#:]+)(#[^)]*)?\)') | ForEach-Object { $_.Groups[1].Value })
        $links.Count | Should -BeGreaterThan 0
        foreach ($link in $links) { $names | Should -Contain $link -Because "README.md links to $link" }
        $names | Should -Not -Contain 'install.ps1'
        $names | Should -Not -Contain '.gitignore'
        $engine = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'engine') -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }).Count
        @($names | Where-Object { $_ -match '^engine/[^/]+$' }).Count | Should -Be $engine
    }

    BeforeAll {
        $script:NotGit = Join-Path $TestDrive 'not-git'
        New-Item -ItemType Directory -Path $NotGit | Out-Null
        foreach ($item in 'tuneup.ps1', 'install.ps1', 'README.md', 'LICENSE', 'engine', 'i18n', 'catalog', 'profiles', 'actions', 'docs', 'build') {
            Copy-Item -LiteralPath (Join-Path $Repo $item) -Destination (Join-Path $NotGit $item) -Recurse
        }
    }

    It 'builds the same files from a copy that is not a git checkout' {
        $built = Invoke-Package (Join-Path $TestDrive 'dist-not-git') -From $NotGit | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        @(Get-ZipEntry $built.Zip) -join ',' | Should -Be (@(Get-ZipEntry $Built.Zip) -join ',')
    }

    It 'gives the same zip for the same files' {
        $again = Invoke-Package (Join-Path $TestDrive 'dist-again') | ConvertFrom-Json
        $again.ZipSha256 | Should -Be $Built.ZipSha256
    }

    It 'writes the version and the SHA256 of the zip into install.ps1, and both hashes into SHA256SUMS' {
        $installer = [System.IO.File]::ReadAllText($Built.Installer)
        $installer | Should -Match ([regex]::Escape("[string]`$Version = '$Version'"))
        $installer | Should -Match ([regex]::Escape("[string]`$Sha256 = '$($Built.ZipSha256)'"))
        $installer | Should -Not -Match '__TUNEUP_'
        $lines = @([System.IO.File]::ReadAllText($Built.Sums).TrimEnd("`n").Split("`n"))
        $lines | Should -Be @("$($Built.ZipSha256)  $Top.zip", "$($Built.InstallerSha256)  install.ps1")
        (Get-FileHash -LiteralPath $Built.Zip -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $Built.ZipSha256
        $notes = [System.IO.File]::ReadAllText($Built.Notes)
        $notes | Should -Not -Match '\{\{'
        $notes | Should -Match ([regex]::Escape("releases/download/v$Version/install.ps1 | iex"))
    }

    Context 'in a git checkout of its own' {
        BeforeAll {
            $script:Checkout = Join-Path $TestDrive 'checkout'
            Copy-Item -LiteralPath $NotGit -Destination $Checkout -Recurse
            # A name with a space and a letter outside ASCII: git quotes it unless it is listed with -z.
            [System.IO.File]::WriteAllText((Join-Path $Checkout ('docs\es\nota ' + [char]0x00E1 + '.md')), 'x')
            $ErrorActionPreference = 'Continue'
            $script:Git = @('-C', $Checkout, '-c', 'user.name=test', '-c', 'user.email=test@example.invalid', '-c', 'commit.gpgsign=false', '-c', 'core.autocrlf=false')
            & git @Git init -q 2>&1 | Out-Null
            & git @Git add . 2>&1 | Out-Null
            & git @Git commit -q -m test 2>&1 | Out-Null
            $ErrorActionPreference = 'Stop'
        }

        It 'takes the names git lists, also those with spaces or letters outside ASCII' {
            $built = Invoke-Package (Join-Path $TestDrive 'dist-checkout') -From $Checkout -Release | ConvertFrom-Json
            $LASTEXITCODE | Should -Be 0
            Get-ZipEntry $built.Zip | Should -Contain ("$Top/docs/es/nota " + [char]0x00E1 + '.md')
        }

        It 'refuses -Release when the checkout has changes that are not committed' {
            [System.IO.File]::AppendAllText((Join-Path $Checkout 'engine\Tuneup.psm1'), "`r`n# changed`r`n")
            $output = Invoke-Package (Join-Path $TestDrive 'dist-dirty') -From $Checkout -Release
            $LASTEXITCODE | Should -Not -Be 0
            Get-Flat $output | Should -Match 'notcommitted'
            Test-Path -LiteralPath (Join-Path $TestDrive "dist-dirty\$Top.zip") | Should -BeFalse
            $output = Invoke-Package (Join-Path $TestDrive 'dist-dirty-not-release') -From $Checkout
            $LASTEXITCODE | Should -Be 0 -Because $output
        }

        It 'refuses -Release outside a git checkout' {
            $output = Invoke-Package (Join-Path $TestDrive 'dist-not-git-release') -From $NotGit -Release
            $LASTEXITCODE | Should -Not -Be 0
            Get-Flat $output | Should -Match 'gitcheckout'
        }
    }
}

Describe 'install.ps1' {
    It 'checks the SHA256 and installs the release in -Destination, with its marker' {
        $destination = Get-TestDestination 'installed'
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Flat | Should -Match (Get-Flat "SHA256 checked: $($Built.ZipSha256.ToUpperInvariant())")
        Test-Path -LiteralPath (Join-Path $destination 'engine\Tuneup.psm1') | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $destination '.windows-tuneup')).Trim() | Should -Be $Version
        Get-Leftover $destination | Should -BeNullOrEmpty
        # -Force: on Windows Server (a GitHub runner) the tool refuses to plan without it.
        $plan = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $destination 'tuneup.ps1') -StateRoot (Join-Path $TestDrive 'state') -Force -WhatIf -Json
        $LASTEXITCODE | Should -Be 0 -Because ($plan | Out-String)
        ($plan | Out-String | ConvertFrom-Json).toolVersion | Should -Be $Version
    }

    It 'never writes to the temporary folder' {
        # A file where the temporary folder should be: anything staged there would fail.
        $destination = Get-TestDestination 'no-temp'
        $blocked = Join-Path $TestDrive 'temp-is-a-file'
        [System.IO.File]::WriteAllText($blocked, 'not a folder')
        $temp, $tmp = $env:TEMP, $env:TMP
        $env:TEMP = $blocked
        $env:TMP = $blocked
        try {
            $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        } finally {
            $env:TEMP, $env:TMP = $temp, $tmp
        }
        $run.ExitCode | Should -Be 0 -Because $run.Output
        Test-Path -LiteralPath (Join-Path $destination 'tuneup.ps1') | Should -BeTrue
    }

    It 'loads modules only from the folder of PowerShell, not from a folder put first in PSModulePath' {
        $destination = Get-TestDestination 'planted'
        $planted = Join-Path $TestDrive 'planted-modules'
        $marker = Join-Path $TestDrive 'planted-install.txt'
        New-PlantedModuleFolder -Folder $planted -Marker $marker
        $modulePath = $env:PSModulePath
        $env:PSModulePath = "$planted;$modulePath"
        try {
            $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        } finally {
            $env:PSModulePath = $modulePath
        }
        $loaded = $(if (Test-Path -LiteralPath $marker) { [System.IO.File]::ReadAllText($marker) } else { '' })
        $loaded | Should -BeNullOrEmpty
        $run.ExitCode | Should -Be 0 -Because $run.Output
        Test-Path -LiteralPath (Join-Path $destination 'tuneup.ps1') | Should -BeTrue
    }

    It 'replaces an earlier copy and leaves any other folder alone, touching nothing' {
        $destination = Get-TestDestination 'twice'
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        [System.IO.File]::WriteAllText((Join-Path $destination 'stale.txt'), 'old')
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $destination 'stale.txt') | Should -BeFalse
        Get-Leftover $destination | Should -BeNullOrEmpty
        $other = Get-TestDestination 'other'
        New-Item -ItemType Directory -Path $other | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $other 'keep.txt'), 'mine')
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $other)
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'is not a copy of windows-tuneup')
        Test-Path -LiteralPath (Join-Path $other 'keep.txt') | Should -BeTrue
        Get-Leftover $other | Should -BeNullOrEmpty
    }

    It 'repairs a copy that lost its files but kept its marker' {
        $destination = Get-TestDestination 'half'
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        Remove-Item -LiteralPath (Join-Path $destination 'tuneup.ps1'), (Join-Path $destination 'engine') -Recurse -Force
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        Test-Path -LiteralPath (Join-Path $destination 'engine\Tuneup.psm1') | Should -BeTrue
    }

    It 'keeps the earlier copy whole when it cannot be moved aside' {
        $destination = Get-TestDestination 'in-use'
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        $before = @(Get-ChildItem -LiteralPath $destination -Recurse -Force).Count
        # A console whose current folder is inside the copy: Windows does not let the folder be renamed.
        $holder = Start-Process $PowerShell -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 60' -WorkingDirectory (Join-Path $destination 'i18n') -PassThru -WindowStyle Hidden
        try {
            Start-Sleep -Seconds 2
            $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        } finally {
            $holder | Stop-Process -Force
            $holder.WaitForExit()
        }
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'could not be moved aside .* Nothing was installed\. The earlier copy in .* is as it was')
        @(Get-ChildItem -LiteralPath $destination -Recurse -Force).Count | Should -Be $before
        Get-Leftover $destination | Should -BeNullOrEmpty
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
    }

    It 'leaves the variables of the session alone when run through iex' {
        $destination = Get-TestDestination 'iex'
        $script = Join-Path $TestDrive 'iex.ps1'
        # Through iex there are no arguments: the text gets the source and the destination of the test instead.
        $text = [System.IO.File]::ReadAllText($Built.Installer).Replace("'https://github.com/edgarlugo/windows-tuneup/releases/download'", "'$Dist'").Replace('[string]$Destination,', "[string]`$Destination = '$destination',")
        $text | Should -Match ([regex]::Escape("[string]`$Destination = '$destination',"))
        $installer = Join-Path $TestDrive 'iex-install.ps1'
        [System.IO.File]::WriteAllText($installer, $text)
        [System.IO.File]::WriteAllText($script, @"
`$Version = 'callers-version'; `$Destination = 'callers-destination'; `$Sha256 = 'callers-sha'; `$Source = 'callers-source'
`$protocol = [Net.ServicePointManager]::SecurityProtocol
`$modulePath = `$env:PSModulePath
Invoke-Expression ([IO.File]::ReadAllText('$installer')) *> `$null
"`$Version|`$Destination|`$Sha256|`$Source|`$ErrorActionPreference|`$ProgressPreference|" + @(Get-ChildItem function:\ | Where-Object Name -like '*-Install*').Count + '|' + (`$protocol -eq [Net.ServicePointManager]::SecurityProtocol) + '|' + (`$modulePath -eq `$env:PSModulePath) + '|' + @(Get-Variable -Name '*ModulePath*' -Scope Global | Where-Object Name -ne 'modulePath').Count
"@)
        $output = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File $script
        $output | Should -Be 'callers-version|callers-destination|callers-sha|callers-source|Continue|Continue|0|True|True|0'
        Test-Path -LiteralPath (Join-Path $destination 'tuneup.ps1') | Should -BeTrue
    }

    # powershell -File and iex run the installer in a scope whose variables can be removed; a script run
    # with & or . inside a session (.\install.ps1 in a console) does not, and nothing must fail there.
    It 'runs as a script inside a session with <Operator>, without errors and leaving nothing behind' -ForEach @(
        @{ Operator = '&' }
        @{ Operator = '.' }
    ) {
        $destination = Get-TestDestination ('in-session-' + [guid]::NewGuid().ToString('N'))
        $run = Invoke-InstallerInSession $Operator $Built.Installer "-Source '$Dist' -Destination '$destination'"
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match 'errors=0' -Because $run.Output
        $run.Output | Should -Match 'modulepath=True'
        $run.Output | Should -Match 'variables=0'
        Test-Path -LiteralPath (Join-Path $destination 'tuneup.ps1') | Should -BeTrue
    }

    It 'fails with its own error when run as a script inside a session' {
        $destination = Get-TestDestination 'in-session-mismatch'
        $run = Invoke-InstallerInSession '&' (Join-Path $Repo 'install.ps1') "-Version '$Version' -Sha256 '$('0' * 64)' -Source '$Dist' -Destination '$destination'"
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'it is not that release. Nothing was installed.')
        $run.Output | Should -Not -Match 'windowsTuneupCallerModulePath'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    # A console keeps the folder it started in as the folder of its process: Set-Location does not change
    # it, and .NET resolves relative paths against it. The installer resolves them against the location.
    It 'takes a relative -Source and -Destination from the location of PowerShell, not from the process folder' -Skip:$Elevated {
        $elsewhere = Join-Path $TestDrive 'process-folder'
        New-Item -ItemType Directory -Path $elsewhere | Out-Null
        $run = Invoke-InstallerInSession '&' $Built.Installer '-Source .\dist -Destination .\relative-out' -ProcessFolder $elsewhere
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match 'errors=0' -Because $run.Output
        $run.Output | Should -Match ([regex]::Escape("process=$elsewhere")) -Because 'the process folder must differ from the location'
        Test-Path -LiteralPath (Join-Path $TestDrive 'relative-out\tuneup.ps1') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $elsewhere -Force).Count | Should -Be 0
    }

    It 'fails on a parameter it does not have' {
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destinaton', (Join-Path $TestDrive 'typo'))
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'Destinaton')
    }

    It 'installs nothing when the SHA256 does not match' {
        $destination = Get-TestDestination 'mismatch'
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Version', $Version, '-Sha256', ('0' * 64), '-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'it is not that release. Nothing was installed.')
        Test-Path -LiteralPath $destination | Should -BeFalse
        Get-Leftover $destination | Should -BeNullOrEmpty
    }

    It 'asks for a version and a SHA256 when it is the copy of the repository' {
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Source', $Dist, '-Destination', (Join-Path $TestDrive 'none'))
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'has no release in it')
    }

    It 'only downloads over HTTPS' {
        $destination = Join-Path $TestDrive 'plain-http'
        $run = Invoke-Installer $Built.Installer @('-Source', 'http://example.invalid/releases', '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'only downloads over HTTPS')
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'refuses a zip with <Case>' -ForEach @(
        @{ Case = 'an entry outside its folder'; Entry = '../escaped.txt'; Message = 'entry outside its folder: \.\./escaped\.txt' }
        @{ Case = 'an entry that is not under the folder of its version'; Entry = 'other-folder/payload.ps1'; Message = 'entry outside its folder: other-folder/payload\.ps1' }
        @{ Case = 'an entry that climbs out from inside'; Entry = 'windows-tuneup-9.9.9/engine/../../x.ps1'; Message = 'entry outside its folder' }
        @{ Case = 'an entry with a stream'; Entry = 'windows-tuneup-9.9.9/engine/handlers/Registry.ps1:payload'; Message = 'whose name is not allowed' }
        @{ Case = 'an entry named like a device'; Entry = 'windows-tuneup-9.9.9/engine/NUL.ps1'; Message = 'whose name is not allowed' }
        @{ Case = 'the marker of the installer'; Entry = 'windows-tuneup-9.9.9/.windows-tuneup'; Message = 'whose name is not allowed' }
    ) {
        $source = Join-Path $TestDrive ('zip-' + [guid]::NewGuid().ToString('N'))
        $hash = New-TestZip $source '9.9.9' @('windows-tuneup-9.9.9/tuneup.ps1', 'windows-tuneup-9.9.9/engine/Tuneup.psm1', $Entry)
        $destination = Get-TestDestination ('out-' + [guid]::NewGuid().ToString('N'))
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Version', '9.9.9', '-Sha256', $hash, '-Source', $source, '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat $Message)
        Test-Path -LiteralPath $destination | Should -BeFalse
        Get-Leftover $destination | Should -BeNullOrEmpty
    }

    It 'refuses a zip that is not a release of windows-tuneup' {
        $source = Join-Path $TestDrive 'not-a-release'
        $hash = New-TestZip $source '9.9.9' @('windows-tuneup-9.9.9/tuneup.ps1', 'windows-tuneup-9.9.9/readme.txt')
        $destination = Get-TestDestination 'not-a-release-out'
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Version', '9.9.9', '-Sha256', $hash, '-Source', $source, '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'is not a release of windows-tuneup')
        Test-Path -LiteralPath $destination | Should -BeFalse
        Get-Leftover $destination | Should -BeNullOrEmpty
    }

    It 'extracts to the current folder when not elevated' -Skip:$Elevated {
        $folder = Join-Path $TestDrive 'here'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist) -WorkingFolder $folder
        $run.ExitCode | Should -Be 0
        $run.Flat | Should -Match (Get-Flat 'never as administrator')
        Test-Path -LiteralPath (Join-Path $folder "$Top\tuneup.ps1") | Should -BeTrue
    }

    It 'installs with a folder that only administrators can change when elevated' -Skip:(-not $Elevated) {
        $destination = Join-Path (New-TrustedParent) 'windows-tuneup'
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        Get-InstallFolderProblem $destination -Recurse | Should -BeNullOrEmpty
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        Get-InstallFolderProblem $destination -Recurse | Should -BeNullOrEmpty
        Get-Leftover $destination | Should -BeNullOrEmpty
    }

    It 'creates the new folder with its access list already set when elevated' -Skip:(-not $Elevated) {
        $folder = Join-Path (New-TrustedParent) 'fresh'
        New-InstallFolder -Path $folder -Security (New-InstallFolderSecurity)
        Get-InstallFolderProblem $folder | Should -BeNullOrEmpty
        { New-InstallFolder -Path $folder -Security (New-InstallFolderSecurity) } | Should -Throw '*already exists*'
    }

    It 'refuses to replace an elevated copy that users can change, <Case>' -Skip:(-not $Elevated) -ForEach @(
        @{ Case = 'the folder'; Item = '' }
        @{ Case = 'one file in it'; Item = 'engine\Tuneup.psm1' }
    ) {
        $destination = Join-Path (New-TrustedParent) 'weakened'
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        $target = $(if ($Item) { Join-Path $destination $Item } else { $destination })
        $users = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        if ($Item) {
            $acl = [System.IO.File]::GetAccessControl($target)
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $users, 'Modify', 'Allow'))
            [System.IO.File]::SetAccessControl($target, $acl)
        } else {
            $acl = [System.IO.Directory]::GetAccessControl($target)
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $users, 'Modify', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
            [System.IO.Directory]::SetAccessControl($target, $acl)
        }
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'cannot be trusted')
        Get-Leftover $destination | Should -BeNullOrEmpty
    }

    It 'refuses a destination under folders that users can change when elevated' -Skip:(-not $Elevated) {
        $destination = Join-Path $TestDrive 'elevated-in-user-folder'
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Flat | Should -Match (Get-Flat 'The folders above .* cannot be trusted')
        Test-Path -LiteralPath $destination | Should -BeFalse
        Get-Leftover $destination | Should -BeNullOrEmpty
    }
}

Describe 'the checks of install.ps1' {
    It 'trusts a folder that belongs to the system and that users cannot change' {
        $system32 = Join-Path $env:SystemRoot 'System32'
        Get-InstallFolderProblem $system32 | Should -BeNullOrEmpty
    }

    It 'finds who besides the administrators and the system can change a folder' {
        $folder = Join-Path $TestDrive 'users-write'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $acl = [System.IO.Directory]::GetAccessControl($folder)
        $users = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $users, 'Modify', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
        [System.IO.Directory]::SetAccessControl($folder, $acl)
        Get-InstallFolderWriter $folder | Should -Not -BeNullOrEmpty
        Get-InstallFolderProblem $folder | Should -Not -BeNullOrEmpty
        Get-InstallFolderWriter (Join-Path $env:SystemRoot 'System32') | Should -BeNullOrEmpty
    }

    It 'finds a writer whose rule only says GENERIC_ALL or GENERIC_WRITE' -ForEach @(
        @{ Rights = 'GA' }
        @{ Rights = 'GW' }
    ) {
        # FileSystemAccessRule does not take generic rights; Windows keeps them as such in inherit-only rules.
        $folder = Join-Path $TestDrive ('generic-' + $Rights)
        New-Item -ItemType Directory -Path $folder | Out-Null
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetSecurityDescriptorSddlForm("D:P(A;OICI;FA;;;$me)(A;OICIIO;$Rights;;;BU)", 'Access')
        [System.IO.Directory]::SetAccessControl($folder, $acl)
        $users = (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-545').Translate([System.Security.Principal.NTAccount]).Value
        Get-InstallFolderWriter $folder | Should -Be $users
    }

    It 'does not trust a folder owned by a user' -Skip:$Elevated {
        $folder = Join-Path $TestDrive 'owned-by-user'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Get-InstallFolderProblem $folder | Should -Match 'not by Administrators'
    }

    It 'does not trust a link, whatever it points to, also deep inside a folder' {
        $target = Join-Path $TestDrive 'link-target'
        $outer = Join-Path $TestDrive 'link-outer'
        $link = Join-Path $outer 'engine\link'
        New-Item -ItemType Directory -Path $target, (Join-Path $outer 'engine') | Out-Null
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        try {
            Get-InstallFolderProblem $link | Should -Match 'is a link'
            Get-InstallFolderProblem $outer -LinkOnly | Should -BeNullOrEmpty
            Get-InstallFolderProblem $outer -LinkOnly -Recurse | Should -Match 'engine\\link is a link'
        } finally {
            [System.IO.Directory]::Delete($link)
        }
    }

    It 'trusts the folders above Program Files' {
        Get-InstallParentProblem (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'windows-tuneup') | Should -BeNullOrEmpty
    }

    It 'does not trust the folders above a folder of the user' {
        Get-InstallParentProblem (Join-Path $TestDrive 'somewhere\windows-tuneup') | Should -Not -BeNullOrEmpty
        Get-InstallParentProblem 'C:\' | Should -Match 'not a folder inside another'
    }

    It 'builds a folder security that is owned by Administrators and gives users only read and run' {
        $security = New-InstallFolderSecurity
        $sddl = $security.GetSecurityDescriptorSddlForm('All')
        $sddl | Should -Match '^O:BA'
        $sddl | Should -Match 'D:P'
        $rules = @($security.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]))
        $rules.Count | Should -Be 3
        $write = [int][System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
        $users = @($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-32-545' })
        $users.Count | Should -Be 1
        ([int]$users[0].FileSystemRights -band $write) | Should -Be 0
        @($rules | Where-Object { $_.IdentityReference.Value -in 'S-1-5-32-544', 'S-1-5-18' }).Count | Should -Be 2
    }

    It 'accepts the entry <Name>' -ForEach @(
        @{ Name = 'windows-tuneup-1.2.3/' }
        @{ Name = 'windows-tuneup-1.2.3/tuneup.ps1' }
        @{ Name = 'windows-tuneup-1.2.3/engine/handlers/' }
        @{ Name = 'windows-tuneup-1.2.3/docs/es/nota con espacio.md' }
    ) {
        Get-InstallEntryProblem -Name $Name -Version '1.2.3' | Should -BeNullOrEmpty
    }

    It 'refuses the entry <Name>' -ForEach @(
        @{ Name = 'windows-tuneup-1.2.4/tuneup.ps1' }
        @{ Name = '/windows-tuneup-1.2.3/tuneup.ps1' }
        @{ Name = 'windows-tuneup-1.2.3//tuneup.ps1' }
        @{ Name = 'windows-tuneup-1.2.3/./tuneup.ps1' }
        @{ Name = 'windows-tuneup-1.2.3/engine/../../x' }
        @{ Name = 'windows-tuneup-1.2.3/engine\..\..\x' }
        @{ Name = 'windows-tuneup-1.2.3/C:/x' }
        @{ Name = 'windows-tuneup-1.2.3/tuneup.ps1:stream' }
        @{ Name = 'windows-tuneup-1.2.3/engine/CON' }
        @{ Name = 'windows-tuneup-1.2.3/engine/com1.txt' }
        @{ Name = 'windows-tuneup-1.2.3/engine/name.' }
        @{ Name = 'windows-tuneup-1.2.3/engine/name ' }
        @{ Name = 'windows-tuneup-1.2.3/engine/a*b' }
        @{ Name = 'windows-tuneup-1.2.3/.windows-tuneup' }
    ) {
        Get-InstallEntryProblem -Name $Name -Version '1.2.3' | Should -Not -BeNullOrEmpty
    }
}
