@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # tuneup.ps1 is an interactive console tool; Write-Host is intended.
        'PSAvoidUsingWriteHost',
        # Confirmation is asked once for the whole plan, not per function.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
