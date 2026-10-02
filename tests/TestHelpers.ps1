function New-TestTweak {
    param(
        [string]$Id = 'test.sample',
        [string]$Type = 'registry',
        [string]$Scope = 'user',
        [string]$Risk = 'low',
        [bool]$Ask = $false,
        [string[]]$Families = @('10', '11'),
        [int]$MinBuild = 19041,
        [string[]]$Editions = @('Home', 'Pro', 'Enterprise', 'Education'),
        [object]$Set = $null,
        [bool]$RebootRequired = $false,
        [string[]]$Requires
    )
    if ($null -eq $Set) {
        $Set = [pscustomobject]@{ path = 'HKCU:\Software\windows-tuneup-test'; name = 'Sample'; kind = 'DWord'; value = 1 }
    }
    $tweak = [pscustomobject]@{
        id             = $Id
        title          = [pscustomobject]@{ es = "Titulo $Id"; en = "Title $Id" }
        why            = [pscustomobject]@{ es = 'Motivo'; en = 'Reason' }
        risk           = $Risk
        ask            = $Ask
        os             = [pscustomobject]@{ families = $Families; minBuild = $MinBuild; editions = $Editions }
        type           = $Type
        scope          = $Scope
        set            = $Set
        rebootRequired = $RebootRequired
        sources        = @('https://example.com/source')
    }
    if ($PSBoundParameters.ContainsKey('Requires')) { $tweak | Add-Member -NotePropertyName requires -NotePropertyValue $Requires }
    $tweak
}

function New-TestEnvironment {
    param(
        [string]$Family = '11',
        [int]$Build = 26100,
        [string]$Edition = 'Pro',
        [bool]$IsManaged = $false,
        [bool]$HasBattery = $false,
        [bool]$IsAdmin = $true,
        [bool]$IsSessionUser = $true
    )
    [pscustomobject]@{
        Family = $Family; Build = $Build; UBR = 0; Edition = $Edition; IsServer = $false
        IsManaged = $IsManaged; IsAdmin = $IsAdmin; IsSessionUser = $IsSessionUser; HasBattery = $HasBattery; PendingReboot = $false
    }
}

function Get-TestCurrentSid {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function New-OwnedSecurity([string]$Sid) {
    $security = New-Object System.Security.AccessControl.DirectorySecurity
    $security.SetOwner((New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $Sid))
    $security
}

# SDDL is the only way to build ACEs with generic rights (GA, GW); FileSystemAccessRule rejects them.
function New-SddlSecurity([string]$Sddl) {
    $security = New-Object System.Security.AccessControl.DirectorySecurity
    $security.SetSecurityDescriptorSddlForm($Sddl)
    $security
}

function Add-TestAccessRule($Security, [string]$Sid, $Rights, [string]$Type = 'Allow', [string]$Propagation = 'None', [string]$Inheritance = 'None') {
    $Security.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
        (New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $Sid),
        [System.Security.AccessControl.FileSystemRights]$Rights,
        [System.Security.AccessControl.InheritanceFlags]$Inheritance,
        [System.Security.AccessControl.PropagationFlags]$Propagation,
        [System.Security.AccessControl.AccessControlType]$Type)))
    $Security
}

function Get-TestAccessRule($Security) {
    @($Security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
}

function Set-TestTrust([string]$Owner, [string[]]$Trusted, [string[]]$BaseTrusted) {
    InModuleScope Tuneup -Parameters @{ Owner = $Owner; Trusted = $Trusted; BaseTrusted = $BaseTrusted } {
        param($Owner, $Trusted, $BaseTrusted)
        $script:StateOwnerSid = $Owner
        $script:TrustedSids = $Trusted
        $script:BaseTrustedSids = $BaseTrusted
    }
}

# The state folders are hardened for Administrators; tests can only own files as the current user.
function Use-CurrentUserAsTrusted {
    $me = Get-TestCurrentSid
    Set-TestTrust -Owner $me -Trusted @('S-1-5-18', 'S-1-5-32-544', $me) `
        -BaseTrusted @('S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464', 'S-1-5-32-544', $me)
}

function Reset-TestTrust {
    Set-TestTrust -Owner 'S-1-5-32-544' -Trusted @('S-1-5-18', 'S-1-5-32-544') `
        -BaseTrusted @('S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464', 'S-1-5-32-544')
}

function Grant-EveryoneWrite([string]$Path) {
    $acl = Get-Acl -LiteralPath $Path
    $inheritance = 'None'
    if ((Get-Item -LiteralPath $Path -Force).PSIsContainer) { $inheritance = 'ContainerInherit, ObjectInherit' }
    Add-TestAccessRule -Security $acl -Sid 'S-1-1-0' -Rights 'Write' -Inheritance $inheritance | Out-Null
    $acl.SetAuditRuleProtection($acl.AreAccessRulesProtected, $true)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# %TEMP% may give other SIDs write access, so a fake machine root lives in a hardened base folder.
# Call Use-CurrentUserAsTrusted first.
function New-TestMachineRoot {
    $base = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $base | Out-Null
    Set-TuneupStateSecurity -Path $base
    Join-Path $base 'windows-tuneup'
}

function New-RunFolder([string]$Root, [string]$Id, [object[]]$Tweaks = @((New-TestTweak)), [string]$UserSid = (Get-TestCurrentSid)) {
    $dir = Join-Path $Root "runs\$Id"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($tweak in $Tweaks) {
        Add-TuneupJournalEntry -Path (Join-Path $dir 'snapshot.jsonl') -Tweak $tweak -State $null -Root 'custom'
    }
    Save-TuneupJson -Path (Join-Path $dir 'run.json') -Root 'custom' `
        -Object ([pscustomobject]@{ schemaVersion = 1; userSid = $UserSid; machine = $true; createdAt = 'now' })
    $dir
}

function New-TestMachineTweak {
    New-TestTweak -Id 'test.machine' -Scope 'machine' `
        -Set ([pscustomobject]@{ path = 'HKLM:\Software\windows-tuneup-test'; name = 'Sample'; kind = 'DWord'; value = 1 })
}

function New-TestProfile {
    param(
        [string]$Id,
        [string[]]$Include = @(),
        [string[]]$Keep = @(),
        [string[]]$Aliases = @()
    )
    [pscustomobject]@{
        id          = $Id
        aliases     = $Aliases
        title       = [pscustomobject]@{ es = $Id; en = $Id }
        description = [pscustomobject]@{ es = 'Descripcion'; en = 'Description' }
        include     = $Include
        keep        = $Keep
    }
}

# Questions and answers for the menu and the confirmations: each read takes the next scripted answer
# ($null stands for the end of the input) and fails when there are none left, so a test that asks
# more than it planned fails instead of waiting. What is written is kept in Output.
function New-TestIo {
    param([object[]]$Answers = @())
    $queue = New-Object System.Collections.Queue
    foreach ($answer in $Answers) { $queue.Enqueue($answer) }
    $output = New-Object System.Collections.Generic.List[string]
    $read = { if ($queue.Count -eq 0) { throw 'The test has no more answers' }; $queue.Dequeue() }.GetNewClosure()
    $write = { param([AllowEmptyString()][string]$Text, [switch]$NoNewline) $output.Add($Text) }.GetNewClosure()
    [pscustomobject]@{ PSTypeName = 'Tuneup.Io'; Read = $read; Write = $write; Output = $output; Pending = $queue }
}

# A folder of modules named like the ones of Windows, each with functions named like their cmdlets: one
# that PowerShell loaded writes its name into $Marker. A program of the user could put such a folder first
# in PSModulePath (HKCU\Environment), which an elevated process inherits.
function New-PlantedModuleFolder([string]$Folder, [string]$Marker) {
    $modules = @{
        'Microsoft.PowerShell.Utility'  = @('Sort-Object', 'Select-Object', 'New-Object', 'ConvertTo-Json', 'ConvertFrom-Json', 'Add-Member', 'Add-Type', 'Get-Date', 'Write-Host', 'Read-Host', 'Out-String')
        'Microsoft.PowerShell.Security' = @('Get-Acl', 'Set-Acl')
        'CimCmdlets'                    = @('Get-CimInstance', 'Invoke-CimMethod')
        'ScheduledTasks'                = @('Get-ScheduledTask')
        'Appx'                          = @('Get-AppxPackage')
        'Dism'                          = @('Get-WindowsOptionalFeature', 'Get-WindowsCapability')
        'Storage'                       = @('Get-Partition', 'Get-PhysicalDisk')
    }
    foreach ($name in $modules.Keys) {
        $path = Join-Path $Folder $name
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $text = "[System.IO.File]::AppendAllText('$Marker', '$name ')`r`n"
        foreach ($command in $modules[$name]) { $text += "function $command { [System.IO.File]::AppendAllText('$Marker', '$command ') }`r`n" }
        [System.IO.File]::WriteAllText((Join-Path $path "$name.psm1"), $text)
    }
}
