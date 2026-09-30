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
        [bool]$RebootRequired = $false
    )
    if ($null -eq $Set) {
        $Set = [pscustomobject]@{ path = 'HKCU:\Software\windows-tuneup-test'; name = 'Sample'; kind = 'DWord'; value = 1 }
    }
    [pscustomobject]@{
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
}

function New-TestEnvironment {
    param(
        [string]$Family = '11',
        [int]$Build = 26100,
        [string]$Edition = 'Pro',
        [bool]$IsManaged = $false
    )
    [pscustomobject]@{
        Family = $Family; Build = $Build; UBR = 0; Edition = $Edition; IsServer = $false
        IsManaged = $IsManaged; IsAdmin = $true; HasBattery = $false; PendingReboot = $false
    }
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
