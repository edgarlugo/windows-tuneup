BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\engine\Tuneup.psm1') -Force
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Catalog = @(Import-TuneupCatalog -Path (Join-Path $Repo 'catalog'))
    $script:Profiles = @(Import-TuneupProfileSet -Path (Join-Path $Repo 'profiles'))
    function Get-DocText([string]$Lang, [string]$Name) {
        [System.IO.File]::ReadAllText((Join-Path $Repo "docs\$Lang\$Name"), (New-Object System.Text.UTF8Encoding -ArgumentList $false))
    }
}

Describe 'Blacklist' {
    It 'explains the cases of the design and of the research in both languages' {
        $terms = @('Defender', 'SmartScreen', 'Windows Update', 'WinRE', '/ResetBase', 'Spectre', 'PagingFiles', 'hosts',
            'SvcHostSplitThresholdInKB', 'NetworkThrottlingIndex', 'HPET', 'SharedAccess', 'OneDrive', 'CBS', 'WerSvc', 'Spooler')
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'blacklist.md'
            foreach ($term in $terms) { $text.Contains($term) | Should -BeTrue -Because "$lang $term" }
        }
    }
}

Describe 'Measuring guide' {
    It 'gives the commands of the method and the LTSC edition in both languages' {
        foreach ($lang in 'es', 'en') {
            $text = Get-DocText $lang 'measuring.md'
            foreach ($term in '-Measure -IdleSeconds 120', '-Compare last', '-Profile lite -Yes', 'LTSC 2024', 'reagentc /info', '-Undo last') {
                $text.Contains($term) | Should -BeTrue -Because "$lang $term"
            }
        }
    }
}
