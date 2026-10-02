# The version of the tool. A release tag (v<version>) must match it: the release workflow checks.
$script:TuneupVersion = '0.1.0'

function Get-TuneupVersion {
    $script:TuneupVersion
}
