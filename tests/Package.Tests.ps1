BeforeDiscovery {
    $script:Elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script:Version = Get-TuneupVersion
    $script:Top = "windows-tuneup-$Version"

    function Invoke-Package([string]$Output) {
        & $PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '$Repo\build\package.ps1' -OutputPath '$Output' | ConvertTo-Json" | Out-String | ConvertFrom-Json
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
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
    }
    function Get-ZipEntry([string]$Path) {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { @($archive.Entries | ForEach-Object { $_.FullName }) } finally { $archive.Dispose() }
    }

    # The folder checks of the installer live inside it (it is one file); they are loaded from its syntax tree.
    $installerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo 'install.ps1'), [ref]$null, [ref]$null)
    foreach ($functionName in 'Get-InstallFolderProblem', 'Get-InstallFolderWriter', 'New-InstallFolderSecurity') {
        $definition = $installerAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    $script:Dist = Join-Path $TestDrive 'dist'
    $script:Built = Invoke-Package $Dist
}

Describe 'build/package.ps1' {
    It 'packs only what runs and what people read, under one folder' {
        $entries = @(Get-ZipEntry $Built.Zip)
        @($entries | Where-Object { -not $_.StartsWith("$Top/") }).Count | Should -Be 0
        $names = @($entries | ForEach-Object { $_.Substring($Top.Length + 1) })
        foreach ($expected in 'tuneup.ps1', 'README.md', 'LICENSE', 'engine/Tuneup.psm1', 'engine/Commands.ps1', 'engine/Menu.ps1',
            'engine/handlers/Registry.ps1', 'i18n/es.json', 'i18n/en.json', 'catalog/apps.json', 'profiles/lite.json',
            'actions/onedrive.ps1', 'docs/es/profiles.md', 'docs/en/catalog.md') {
            $names | Should -Contain $expected
        }
        foreach ($folder in 'tests/', 'build/', '.github/', 'docs/superpowers/', 'catalog/notes/') {
            @($names | Where-Object { $_.StartsWith($folder) }).Count | Should -Be 0 -Because $folder
        }
        $names | Should -Not -Contain 'install.ps1'
        $names | Should -Not -Contain '.gitignore'
        $engine = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'engine') -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }).Count
        @($names | Where-Object { $_ -match '^engine/[^/]+$' }).Count | Should -Be $engine
    }

    It 'builds the same files from a copy that is not a git checkout' {
        $copy = Join-Path $TestDrive 'not-git'
        New-Item -ItemType Directory -Path $copy | Out-Null
        foreach ($item in 'tuneup.ps1', 'install.ps1', 'README.md', 'LICENSE', 'engine', 'i18n', 'catalog', 'profiles', 'actions', 'docs', 'build') {
            Copy-Item -LiteralPath (Join-Path $Repo $item) -Destination (Join-Path $copy $item) -Recurse
        }
        $output = Join-Path $TestDrive 'dist-not-git'
        $built = & $PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '$copy\build\package.ps1' -OutputPath '$output' | ConvertTo-Json" | Out-String | ConvertFrom-Json
        $LASTEXITCODE | Should -Be 0
        @(Get-ZipEntry $built.Zip) -join ',' | Should -Be (@(Get-ZipEntry $Built.Zip) -join ',')
    }

    It 'gives the same zip for the same files' {
        $again = Invoke-Package (Join-Path $TestDrive 'dist-again')
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
}

Describe 'install.ps1' {
    It 'checks the SHA256 and installs the release in -Destination' {
        $destination = Join-Path $TestDrive 'installed'
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Output | Should -Match "SHA256 checked: $($Built.ZipSha256.ToUpperInvariant())"
        Test-Path -LiteralPath (Join-Path $destination 'engine\Tuneup.psm1') | Should -BeTrue
        $plan = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $destination 'tuneup.ps1') -StateRoot (Join-Path $TestDrive 'state') -WhatIf -Json
        $LASTEXITCODE | Should -Be 0
        ($plan | Out-String | ConvertFrom-Json).toolVersion | Should -Be $Version
    }

    It 'replaces an earlier copy and leaves any other folder alone' {
        $destination = Join-Path $TestDrive 'twice'
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        [System.IO.File]::WriteAllText((Join-Path $destination 'stale.txt'), 'old')
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $destination 'stale.txt') | Should -BeFalse
        $other = Join-Path $TestDrive 'other'
        New-Item -ItemType Directory -Path $other | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $other 'keep.txt'), 'mine')
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $other)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'is not a copy of windows-tuneup'
        Test-Path -LiteralPath (Join-Path $other 'keep.txt') | Should -BeTrue
    }

    It 'installs nothing when the SHA256 does not match' {
        $destination = Join-Path $TestDrive 'mismatch'
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Version', $Version, '-Sha256', ('0' * 64), '-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'it is not that release. Nothing was installed.'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'asks for a version and a SHA256 when it is the copy of the repository' {
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Source', $Dist, '-Destination', (Join-Path $TestDrive 'none'))
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'has no release in it'
    }

    It 'only downloads over HTTPS' {
        $destination = Join-Path $TestDrive 'plain-http'
        $run = Invoke-Installer $Built.Installer @('-Source', 'http://example.invalid/releases', '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'only downloads over HTTPS'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'refuses a zip with an entry outside its folder' {
        $source = Join-Path $TestDrive 'evil'
        New-Item -ItemType Directory -Path $source | Out-Null
        $zip = Join-Path $source 'windows-tuneup-9.9.9.zip'
        $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in 'windows-tuneup-9.9.9/tuneup.ps1', 'windows-tuneup-9.9.9/engine/Tuneup.psm1', '../escaped.txt') {
                $writer = New-Object System.IO.StreamWriter -ArgumentList $archive.CreateEntry($name).Open()
                try { $writer.Write('x') } finally { $writer.Dispose() }
            }
        } finally {
            $archive.Dispose()
        }
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Version', '9.9.9', '-Sha256', $hash, '-Source', $source, '-Destination', (Join-Path $TestDrive 'evil-out'))
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'entry outside its folder: \.\./escaped\.txt'
        Test-Path -LiteralPath (Join-Path $TestDrive 'evil-out') | Should -BeFalse
    }

    It 'refuses a zip whose entries are not under the folder of its version' {
        $source = Join-Path $TestDrive 'stray'
        New-Item -ItemType Directory -Path $source | Out-Null
        $zip = Join-Path $source 'windows-tuneup-9.9.9.zip'
        $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in 'windows-tuneup-9.9.9/tuneup.ps1', 'windows-tuneup-9.9.9/engine/Tuneup.psm1', 'other-folder/payload.ps1') {
                $writer = New-Object System.IO.StreamWriter -ArgumentList $archive.CreateEntry($name).Open()
                try { $writer.Write('x') } finally { $writer.Dispose() }
            }
        } finally {
            $archive.Dispose()
        }
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        $run = Invoke-Installer (Join-Path $Repo 'install.ps1') @('-Version', '9.9.9', '-Sha256', $hash, '-Source', $source, '-Destination', (Join-Path $TestDrive 'stray-out'))
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'entry outside its folder: other-folder/payload\.ps1'
        Test-Path -LiteralPath (Join-Path $TestDrive 'stray-out') | Should -BeFalse
    }

    It 'extracts to the current folder when not elevated' -Skip:$Elevated {
        $folder = Join-Path $TestDrive 'here'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist) -WorkingFolder $folder
        $run.ExitCode | Should -Be 0
        $run.Output | Should -Match 'never as administrator'
        Test-Path -LiteralPath (Join-Path $folder "$Top\tuneup.ps1") | Should -BeTrue
    }

    It 'installs with a folder that only administrators can change when elevated' -Skip:(-not $Elevated) {
        $destination = Join-Path $TestDrive 'admin-only'
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 0 -Because $run.Output
        Get-InstallFolderProblem $destination | Should -BeNullOrEmpty
        Get-InstallFolderProblem (Join-Path $destination 'engine') | Should -BeNullOrEmpty
    }

    It 'refuses to replace an elevated copy that users can change' -Skip:(-not $Elevated) {
        $destination = Join-Path $TestDrive 'weakened'
        (Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)).ExitCode | Should -Be 0
        $acl = [System.IO.Directory]::GetAccessControl($destination)
        $users = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([System.Security.Principal.WellKnownSidType]::BuiltinUsersSid, $null)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $users, 'Modify', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
        [System.IO.Directory]::SetAccessControl($destination, $acl)
        $run = Invoke-Installer $Built.Installer @('-Source', $Dist, '-Destination', $destination)
        $run.ExitCode | Should -Be 1
        $run.Output | Should -Match 'cannot be trusted'
    }
}

Describe 'the folder checks of install.ps1' {
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

    It 'does not trust a folder owned by a user' -Skip:$Elevated {
        $folder = Join-Path $TestDrive 'owned-by-user'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Get-InstallFolderProblem $folder | Should -Match 'not by Administrators'
    }

    It 'does not trust a link, whatever it points to' {
        $target = Join-Path $TestDrive 'link-target'
        $link = Join-Path $TestDrive 'link'
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        try {
            Get-InstallFolderProblem $link | Should -Match 'is a link'
        } finally {
            [System.IO.Directory]::Delete($link)
        }
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
}
