# The window itself (design, section 17): it loads MainWindow.xaml, puts the texts of the language in it, and
# fills each section from the document of the engine that GuiCore.ps1 brings back. Every change goes through
# tuneup.ps1; nothing here touches the system. All state lives in $script:Gui, since WPF handlers run later,
# outside the function that set them.

$script:Gui = $null
$script:GuiSections = @('Home', 'Optimize', 'Status', 'Undo', 'Health', 'Measure', 'Startup', 'Clean', 'Log')
# The elements GuiWindow.ps1 uses, by x:Name; a test checks that MainWindow.xaml has each one.
$script:GuiElementNames = @(
    'Shell', 'VersionText', 'EnvText', 'AdminChip', 'AdminText', 'RelaunchAdminButton', 'OpenLogButton', 'CancelButton', 'ElapsedText', 'BusyBar',
    'StatusText', 'LanguageBox', 'ThemeBox', 'ThemeHighContrastNote', 'NavPanel', 'ContentScroll', 'SectionTitle', 'NoticePanel',
    'SectionHome', 'HomeAppliedValue', 'HomeAppliedNote', 'HomeStatusButton', 'HomeFreeValue', 'HomeFreeNote', 'HomeCleanButton', 'HomeStartupValue',
    'HomeStartupNote', 'HomeStartupButton', 'HomeSuggestList', 'HomeSuggestButton', 'HomeRunsList',
    'SectionOptimize', 'OptProfilesList', 'OptHighRiskExpander', 'OptHighRiskList', 'OptHighRiskConfirmLabel', 'OptHighRiskConfirm', 'OptExtraExpander', 'OptExtraList', 'OptPlanButton',
    'OptPlanCard', 'OptPlanSummary', 'OptPreflightList', 'OptPlanTabs', 'OptPlanList', 'OptApplyCard', 'OptExportButton', 'OptApplyButton', 'OptAdminNote',
    'SectionStatus', 'StatusReapplyButton', 'StatusTabs', 'StatusList',
    'SectionUndo', 'UndoRunsList',
    'SectionHealth', 'HealthRepairCheck', 'HealthRunButton', 'HealthAdminNote', 'HealthPhaseList', 'HealthResultText', 'HealthResultList', 'HealthRepairButton',
    'SectionMeasure', 'MeasureIdleBox', 'MeasureCompareBox', 'MeasureRunButton', 'MeasureResultText', 'MeasureList',
    'SectionStartup', 'StartupTabs', 'StartupList', 'StartupPlanButton', 'StartupApplyButton',
    'SectionClean', 'CleanList', 'CleanReportList', 'CleanLargeCheck', 'CleanLargeList', 'CleanPreviewButton', 'CleanRemoveButton', 'CleanSummary',
    'SectionLog', 'LogNote', 'LogTabs', 'LogCopyButton', 'LogSaveButton', 'LogFolderButton', 'LogRunsButton', 'LogList',
    'DialogLayer', 'DialogTitle', 'DialogText', 'DialogList', 'DialogDetails', 'DialogCheck', 'DialogSecondary', 'DialogPrimary'
)

# Puts the text of each x:Uid key (gui.*) in the window; a control without text of its own also gets it as
# its accessible name.
function Set-GuiText {
    param([Parameter(Mandatory)]$Root)
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count) {
        $node = $stack.Pop()
        if ($node -is [System.Windows.UIElement] -and $node.Uid -like 'gui.*') {
            $text = Get-TuneupGuiText -Key $node.Uid
            if ($node -is [System.Windows.Controls.TextBlock]) { $node.Text = $text }
            elseif ($node -is [System.Windows.Controls.HeaderedContentControl]) { $node.Header = $text }
            elseif ($node -is [System.Windows.Controls.ContentControl]) { $node.Content = $text }
            [System.Windows.Automation.AutomationProperties]::SetName($node, $text)
        }
        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($node)) {
            if ($child -is [System.Windows.DependencyObject]) { $stack.Push($child) }
        }
    }
}

function Get-GuiBrush {
    param([Parameter(Mandatory)][string]$Key)
    $script:Gui.Window.FindResource($Key)
}

# The window with the tokens of its theme already inside, so every color resolves when it is created (a
# dictionary swapped afterwards does not reach what WPF already resolved): a change of theme opens the window
# again, like a change of language.
function Import-GuiWindow {
    param([Parameter(Mandatory)][string]$Theme)
    $name = switch ($Theme) { 'dark' { 'Dark' } 'highcontrast' { 'HighContrast' } default { 'Light' } }
    $tokens = New-Object System.Xml.XmlDocument
    $tokens.XmlResolver = $null
    $tokens.Load((Join-Path $script:GuiRoot "gui\Themes\$name.xaml"))
    $xml = New-Object System.Xml.XmlDocument
    $xml.XmlResolver = $null
    $xml.Load((Join-Path $script:GuiRoot 'gui\MainWindow.xaml'))
    $namespaces = New-Object System.Xml.XmlNamespaceManager -ArgumentList $xml.NameTable
    $namespaces.AddNamespace('p', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
    $slot = $xml.SelectSingleNode('/p:Window/p:Window.Resources/p:ResourceDictionary/p:ResourceDictionary.MergedDictionaries/p:ResourceDictionary', $namespaces)
    if ($null -eq $slot) { throw 'MainWindow.xaml has no place for the theme' }
    foreach ($node in @($tokens.DocumentElement.ChildNodes)) {
        if ($node.NodeType -eq 'Element') { [void]$slot.AppendChild($xml.ImportNode($node, $true)) }
    }
    $reader = New-Object System.Xml.XmlNodeReader -ArgumentList $xml
    [System.Windows.Markup.XamlReader]::Load($reader)
}

# A row of a list (RowTemplate in MainWindow.xaml): every row has every property, so no binding fails.
function New-GuiRow {
    param(
        [string]$Title = '', [string]$Description = '', [string]$Note = '', [string]$Value = '', [string]$Header = '',
        [string]$Chip1 = '', [string]$Chip1Kind = 'Neutral', [string]$Chip2 = '', [string]$Chip2Kind = 'Neutral', [string]$NoteKind = 'Secondary',
        [switch]$Checkable, [bool]$Enabled = $true, [bool]$Selected = $false, $Data = $null
    )
    $kind = {
        param([string]$Name)
        switch ($Name) {
            'Success' { @((Get-GuiBrush 'SuccessBg'), (Get-GuiBrush 'SuccessFg')) }
            'Caution' { @((Get-GuiBrush 'CautionBg'), (Get-GuiBrush 'CautionFg')) }
            'Critical' { @((Get-GuiBrush 'CriticalBg'), (Get-GuiBrush 'CriticalFg')) }
            'Info' { @((Get-GuiBrush 'InfoBg'), (Get-GuiBrush 'InfoFg')) }
            default { @((Get-GuiBrush 'NeutralBg'), (Get-GuiBrush 'TextSecondary')) }
        }
    }
    $one = & $kind $Chip1Kind
    $two = & $kind $Chip2Kind
    $noteFg = $(if ($NoteKind -eq 'Secondary') { Get-GuiBrush 'TextSecondary' } else { (& $kind $NoteKind)[1] })
    [pscustomobject]@{
        Title = $Title; Description = $Description; HasDescription = [bool]$Description; Note = $Note; HasNote = [bool]$Note; NoteFg = $noteFg
        Value = $Value; HasValue = [bool]$Value; Header = $Header; HasHeader = [bool]$Header
        Chip1 = $Chip1; HasChip1 = [bool]$Chip1; Chip1Bg = $one[0]; Chip1Fg = $one[1]
        Chip2 = $Chip2; HasChip2 = [bool]$Chip2; Chip2Bg = $two[0]; Chip2Fg = $two[1]
        Checkable = [bool]$Checkable; Enabled = $Enabled; Selected = $Selected; Data = $Data
    }
}

function Set-GuiItemSource {
    param([Parameter(Mandatory)]$Control, [AllowEmptyCollection()][object[]]$Items = @())
    $Control.ItemsSource = $null
    $Control.ItemsSource = [object[]]@($Items)
}

# A row of tabs that filter a list: one radio button per filter, the chosen one checked; picking one runs
# -OnPick with its id.
function Set-GuiTabRow {
    param([Parameter(Mandatory)]$Panel, [Parameter(Mandatory)][object[]]$Tabs, [Parameter(Mandatory)][string]$Selected, [Parameter(Mandatory)][scriptblock]$OnPick)
    $Panel.Children.Clear()
    $group = 'tabs' + $Panel.Name
    foreach ($tab in $Tabs) {
        $button = New-Object System.Windows.Controls.RadioButton
        $button.Style = $script:Gui.Window.FindResource('Tab')
        $button.GroupName = $group
        $button.Content = $tab.Label
        $button.Tag = $tab.Id
        $button.IsChecked = ($tab.Id -eq $Selected)
        $button.Add_Checked($OnPick)
        [void]$Panel.Children.Add($button)
    }
}

# A notice at the top of the section: what happened, why, what to do, and its buttons ([pscustomobject] with
# Label and Run). Errors are announced at once, the rest when the reader is free.
function Show-GuiNotice {
    param(
        [Parameter(Mandatory)][ValidateSet('Error', 'Warning', 'Info', 'Success')][string]$Kind,
        [Parameter(Mandatory)][string]$Title, [string]$Text, [string[]]$Details = @(), [object[]]$Buttons = @()
    )
    $keys = @{ Error = @('CriticalBg', 'CriticalFg'); Warning = @('CautionBg', 'CautionFg'); Info = @('InfoBg', 'InfoFg'); Success = @('SuccessBg', 'SuccessFg') }[$Kind]
    $border = New-Object System.Windows.Controls.Border
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $keys[0])
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'Outline')
    $border.BorderThickness = 1
    $border.CornerRadius = 8
    $border.Padding = '16,12'
    $border.Margin = '0,0,0,16'
    $live = $(if ($Kind -eq 'Error') { [System.Windows.Automation.AutomationLiveSetting]::Assertive } else { [System.Windows.Automation.AutomationLiveSetting]::Polite })
    [System.Windows.Automation.AutomationProperties]::SetLiveSetting($border, $live)
    $stack = New-Object System.Windows.Controls.StackPanel
    $head = New-Object System.Windows.Controls.TextBlock
    $head.Text = $Title
    $head.FontWeight = 'SemiBold'
    $head.TextWrapping = 'Wrap'
    $head.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $keys[1])
    [void]$stack.Children.Add($head)
    if ($Text) {
        $body = New-Object System.Windows.Controls.TextBlock
        $body.Text = $Text
        $body.TextWrapping = 'Wrap'
        $body.Margin = '0,4,0,0'
        $body.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $keys[1])
        [void]$stack.Children.Add($body)
    }
    if (@($Details).Count) {
        $expander = New-Object System.Windows.Controls.Expander
        $expander.Header = Get-TuneupGuiText -Key 'gui.notice.details' -Format @($Details).Count
        $expander.Margin = '0,6,0,0'
        $expander.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $keys[1])
        $box = New-Object System.Windows.Controls.TextBox
        $box.Text = (@($Details) -join [Environment]::NewLine)
        $box.IsReadOnly = $true
        $box.TextWrapping = 'Wrap'
        $box.Margin = '0,6,0,0'
        $expander.Content = $box
        [void]$stack.Children.Add($expander)
    }
    if (@($Buttons).Count) {
        $row = New-Object System.Windows.Controls.WrapPanel
        $row.Margin = '0,10,0,0'
        $first = $true
        foreach ($definition in $Buttons) {
            $button = New-Object System.Windows.Controls.Button
            $button.Content = $definition.Label
            $button.Margin = '0,0,8,0'
            if ($first) { $button.Style = $script:Gui.Window.FindResource('Primary'); $first = $false }
            $button.Tag = $definition.Run
            $button.Add_Click({ param($source) & $source.Tag })
            [void]$row.Children.Add($button)
        }
        [void]$stack.Children.Add($row)
    }
    $border.Child = $stack
    [void]$script:Gui.Ui.NoticePanel.Children.Add($border)
    $script:Gui.Ui.ContentScroll.ScrollToTop()
}

function Clear-GuiNotice { $script:Gui.Ui.NoticePanel.Children.Clear() }

function New-GuiButtonSpec {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][scriptblock]$Run)
    [pscustomobject]@{ Label = $Label; Run = $Run }
}

# A modal dialog over the window: the rest is disabled while it is open, Esc closes it, the focus goes to the
# safe button first and comes back where it was. -OnPrimary gets the dialog state (the check box, the item
# picked in the list).
function Show-GuiDialog {
    param(
        [Parameter(Mandatory)][string]$Title, [string]$Text, [Parameter(Mandatory)][string]$PrimaryLabel, [string]$SecondaryLabel,
        [switch]$Danger, [string]$CheckLabel, [object[]]$ListItems = @(), [string]$Details, [scriptblock]$OnPrimary
    )
    $ui = $script:Gui.Ui
    $script:Gui.DialogReturnFocus = [System.Windows.Input.Keyboard]::FocusedElement
    $ui.DialogTitle.Text = $Title
    $ui.DialogText.Text = $Text
    $ui.DialogText.Visibility = $(if ($Text) { 'Visible' } else { 'Collapsed' })
    $ui.DialogPrimary.Content = $PrimaryLabel
    $ui.DialogPrimary.Style = $script:Gui.Window.FindResource($(if ($Danger) { 'Dangerous' } else { 'Primary' }))
    $ui.DialogSecondary.Content = $(if ($SecondaryLabel) { $SecondaryLabel } else { Get-TuneupGuiText -Key 'gui.dialog.cancel' })
    $ui.DialogCheck.Visibility = $(if ($CheckLabel) { 'Visible' } else { 'Collapsed' })
    $ui.DialogCheck.Content = $CheckLabel
    $ui.DialogCheck.IsChecked = $false
    $ui.DialogList.Visibility = $(if (@($ListItems).Count) { 'Visible' } else { 'Collapsed' })
    $ui.DialogList.ItemsSource = [object[]]@($ListItems)
    $ui.DialogList.DisplayMemberPath = 'Title'
    if (@($ListItems).Count) { $ui.DialogList.SelectedIndex = 0 }
    $ui.DialogDetails.Visibility = $(if ($Details) { 'Visible' } else { 'Collapsed' })
    $ui.DialogDetails.Text = $Details
    $script:Gui.DialogAction = $OnPrimary
    $ui.Shell.IsEnabled = $false
    $ui.DialogLayer.Visibility = 'Visible'
    # Enter never confirms what cannot be undone: the focus starts on the safe button.
    [void]$ui.DialogSecondary.Focus()
}

function Close-GuiDialog {
    $ui = $script:Gui.Ui
    $ui.DialogLayer.Visibility = 'Collapsed'
    $ui.Shell.IsEnabled = $true
    $script:Gui.DialogAction = $null
    if ($script:Gui.DialogReturnFocus -is [System.Windows.IInputElement]) { [void]$script:Gui.DialogReturnFocus.Focus() }
}

function Show-GuiFailure {
    param([Parameter(Mandatory)][string]$Text, [string]$Details)
    Write-TuneupGuiLog -Level ERROR -Text "$Text $Details"
    Show-GuiDialog -Title (Get-TuneupGuiText -Key 'gui.failure.title') -Text $Text -Details $Details -PrimaryLabel (Get-TuneupGuiText -Key 'gui.failure.copy') `
        -SecondaryLabel (Get-TuneupGuiText -Key 'gui.dialog.close') -OnPrimary { [System.Windows.Clipboard]::SetText($script:Gui.Ui.DialogDetails.Text + [Environment]::NewLine + $script:Gui.Ui.DialogText.Text) }
}

# --- Jobs -----------------------------------------------------------------------------------------------

# Runs an action of the engine and, when it ends, -OnDone with its result (on the thread of the window).
# -Changes: it changes the system, so only one runs at a time and it cannot be stopped. -Elevated: through
# UAC, with the result read back unelevated.
function Invoke-GuiJob {
    param(
        [Parameter(Mandatory)][string]$Action, [hashtable]$Options = @{}, [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$OnDone, [switch]$Changes, [switch]$Elevated
    )
    if ($Changes -and $null -ne $script:Gui.Changing) {
        Show-GuiNotice -Kind Warning -Title (Get-TuneupGuiText -Key 'gui.busy.title') -Text (Get-TuneupGuiText -Key 'gui.busy.text')
        return
    }
    try {
        $job = Start-TuneupGuiJob -Action $Action -Options $Options -Elevated:$Elevated -Label $Label
    } catch {
        Show-GuiFailure -Text (Get-TuneupGuiText -Key 'gui.failure.start') -Details $_.Exception.Message
        return
    }
    $entry = [pscustomobject]@{ Job = $job; OnDone = $OnDone; Changes = [bool]$Changes; Label = $Label }
    $script:Gui.Jobs.Add($entry)
    if ($Changes) {
        $script:Gui.Changing = $entry
        $script:Gui.Ui.ContentScroll.IsEnabled = $false
    }
    Update-GuiBusy
}

function Update-GuiBusy {
    $ui = $script:Gui.Ui
    $running = $script:Gui.Jobs.ToArray()
    if (-not $running.Count) {
        $ui.BusyBar.Visibility = 'Collapsed'
        $ui.CancelButton.Visibility = 'Collapsed'
        $ui.ElapsedText.Text = ''
        if (-not $script:Gui.LastStatus) { $ui.StatusText.Text = Get-TuneupGuiText -Key 'gui.status.ready' }
        return
    }
    $current = $(if ($null -ne $script:Gui.Changing) { $script:Gui.Changing } else { $running[-1] })
    $ui.BusyBar.Visibility = 'Visible'
    $ui.StatusText.Text = Get-TuneupGuiText -Key 'gui.status.running' -Format $current.Label
    $seconds = [int]([datetime]::Now - $current.Job.Started).TotalSeconds
    $ui.ElapsedText.Text = Get-TuneupGuiText -Key 'gui.status.elapsed' -Format ([int][math]::Floor($seconds / 60)), ('{0:00}' -f ($seconds % 60))
    # Only what reads can be stopped, and not through UAC (that process is not ours to stop).
    $stoppable = @($running | Where-Object { -not $_.Changes -and -not $_.Job.Elevated })
    $ui.CancelButton.Visibility = $(if ($stoppable.Count -and $null -eq $script:Gui.Changing) { 'Visible' } else { 'Collapsed' })
}

function Invoke-GuiTick {
    foreach ($entry in $script:Gui.Jobs.ToArray()) {
        if (-not (Test-TuneupGuiJobDone -Job $entry.Job)) { continue }
        [void]$script:Gui.Jobs.Remove($entry)
        try {
            $result = Complete-TuneupGuiJob -Job $entry.Job
        } catch {
            $result = [pscustomobject]@{ ExitCode = $null; Document = $null; Problem = $_.Exception.Message; NeedsRead = $false; Declined = $false; Seconds = 0 }
        }
        if ($result.NeedsRead) {
            # The elevated process wrote its document under its result id: read it without elevation.
            $readOptions = @{ ResultId = $entry.Job.ResultId }
            $exitCode = $result.ExitCode
            $onDone = $entry.OnDone
            $chained = { param($read) if ($null -ne $read.Document -and $read.Document.command -ne 'error') { $read.ExitCode = $exitCode }; & $onDone $read }.GetNewClosure()
            $replacement = [pscustomobject]@{ Job = (Start-TuneupGuiJob -Action 'read-result' -Options $readOptions -Label $entry.Label); OnDone = $chained; Changes = $entry.Changes; Label = $entry.Label }
            $script:Gui.Jobs.Add($replacement)
            if ($entry.Changes) { $script:Gui.Changing = $replacement }
            continue
        }
        if ($entry.Changes) {
            $script:Gui.Changing = $null
            $script:Gui.Ui.ContentScroll.IsEnabled = $true
        }
        try {
            if ($result.Declined) {
                Show-GuiNotice -Kind Warning -Title (Get-TuneupGuiText -Key 'gui.uac.declined') -Text (Get-TuneupGuiText -Key 'gui.uac.declinedText')
            } elseif ($result.Problem) {
                Show-GuiFailure -Text (Get-TuneupGuiText -Key 'gui.failure.output' -Format $entry.Label) -Details $result.Problem
            } else {
                & $entry.OnDone $result
            }
        } catch {
            Show-GuiFailure -Text (Get-TuneupGuiText -Key 'gui.failure.show' -Format $entry.Label) -Details ($_.Exception.Message + [Environment]::NewLine + $_.ScriptStackTrace)
        }
    }
    Update-GuiBusy
    # High contrast turned on or off in Windows: the window opens again with the other colors, in the same
    # section, once nothing is changing and no dialog is open.
    if ($null -eq $script:Gui.Changing -and $null -eq $script:Gui.Reopen -and $script:Gui.Ui.DialogLayer.Visibility -ne 'Visible' -and
        [System.Windows.SystemParameters]::HighContrast -ne ($script:Gui.Theme -eq 'highcontrast')) {
        $script:Gui.Reopen = [pscustomobject]@{ Lang = (Get-TuneupGuiLang); Section = $script:Gui.Section }
        $script:Gui.Window.Close()
    }
}

# An error document as a notice, with what the window can do about its reason. -Retry runs the same action
# elevated when the reason is needs-admin.
function Show-GuiError {
    param([Parameter(Mandatory)]$Document, [scriptblock]$Retry)
    $view = Get-TuneupGuiErrorView -Document $Document
    $buttons = @()
    switch ($view.Action) {
        'elevate' { if ($Retry) { $buttons += New-GuiButtonSpec -Label (Get-TuneupGuiText -Key 'gui.action.elevate') -Run $Retry } else { $buttons += New-GuiButtonSpec -Label (Get-TuneupGuiText -Key 'gui.header.relaunchAdmin') -Run { Restart-GuiElevated } } }
        'unelevated' { $buttons += New-GuiButtonSpec -Label (Get-TuneupGuiText -Key 'gui.action.unelevated') -Run { Restart-GuiUnelevated } }
        'log' { $buttons += New-GuiButtonSpec -Label (Get-TuneupGuiText -Key 'gui.log.openButton') -Run { Show-GuiSection -Name 'Log' } }
    }
    $copyText = (@($view.Message) + @($view.Details) + @($(if ($view.Reason) { "reason: $($view.Reason)" }))) -join [Environment]::NewLine
    $buttons += New-GuiButtonSpec -Label (Get-TuneupGuiText -Key 'gui.failure.copy') -Run ({ [System.Windows.Clipboard]::SetText($copyText) }.GetNewClosure())
    Show-GuiNotice -Kind Error -Title $view.Title -Text $view.Message -Details $view.Details -Buttons $buttons
}

# Runs an action that may need administrator: as it is when the window is elevated or it does not need it;
# otherwise after the dialog that says Windows will ask for permission, through UAC.
function Invoke-GuiAdminJob {
    param(
        [Parameter(Mandatory)][string]$Action, [hashtable]$Options = @{}, [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$OnDone, [bool]$NeedsAdmin, [switch]$Changes
    )
    if (-not $NeedsAdmin -or $script:Gui.IsAdmin) {
        Invoke-GuiJob -Action $Action -Options $Options -Label $Label -OnDone $OnDone -Changes:$Changes
        return
    }
    $script:Gui.Pending = [pscustomobject]@{ Action = $Action; Options = $Options; Label = $Label; OnDone = $OnDone; Changes = [bool]$Changes }
    Show-GuiDialog -Title (Get-TuneupGuiText -Key 'gui.uac.title') -Text (Get-TuneupGuiText -Key 'gui.uac.text') -PrimaryLabel (Get-TuneupGuiText -Key 'gui.uac.continue') -OnPrimary {
        $pending = $script:Gui.Pending
        Invoke-GuiJob -Action $pending.Action -Options $pending.Options -Label $pending.Label -OnDone $pending.OnDone -Changes:$pending.Changes -Elevated
    }
}

function Restart-GuiElevated {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', (Join-Path $script:GuiRoot 'gui.ps1'), '-Section', $script:Gui.Section, '-Lang', (Get-TuneupGuiLang))
    try {
        Start-Process -FilePath (Get-TuneupGuiPowerShell) -ArgumentList (ConvertTo-TuneupGuiCommandLine -Argument $arguments) -Verb RunAs -ErrorAction Stop | Out-Null
        Write-TuneupGuiLog -Level INFO -Text (Get-TuneupGuiText -Key 'gui.log.relaunch')
        $script:Gui.Window.Close()
    } catch {
        Show-GuiNotice -Kind Warning -Title (Get-TuneupGuiText -Key 'gui.uac.declined') -Text (Get-TuneupGuiText -Key 'gui.uac.declinedText')
    }
}

# Elevated as another administrator, the account of the desktop needs a window of its own: explorer.exe opens
# gui.ps1 unelevated (it runs as the account signed in).
function Restart-GuiUnelevated {
    Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'gui.action.unelevated') -Text (Get-TuneupGuiText -Key 'gui.unelevated.text' -Format (Join-Path $script:GuiRoot 'gui.ps1'))
}

# --- Sections -------------------------------------------------------------------------------------------

function Show-GuiSection {
    param([Parameter(Mandatory)][string]$Name, [switch]$Refresh)
    if ($script:GuiSections -notcontains $Name) { $Name = 'Home' }
    $ui = $script:Gui.Ui
    $script:Gui.Section = $Name
    foreach ($section in $script:GuiSections) { $ui["Section$section"].Visibility = $(if ($section -eq $Name) { 'Visible' } else { 'Collapsed' }) }
    $nav = $ui.NavPanel.Children | Where-Object { $_.Tag -eq $Name } | Select-Object -First 1
    if ($null -ne $nav -and -not $nav.IsChecked) { $script:Gui.Navigating = $true; $nav.IsChecked = $true; $script:Gui.Navigating = $false }
    $ui.SectionTitle.Text = Get-TuneupGuiText -Key "gui.nav.$($Name.ToLowerInvariant())"
    Clear-GuiNotice
    $ui.ContentScroll.ScrollToTop()
    if ($Refresh -or -not $script:Gui.Loaded.Contains($Name)) {
        [void]$script:Gui.Loaded.Add($Name)
        & "Update-GuiSection$Name"
    } else {
        & "Show-GuiSection${Name}Data"
    }
}

function Show-GuiSectionHomeData { }
function Show-GuiSectionOptimizeData { }
function Show-GuiSectionStatusData { }
function Show-GuiSectionUndoData { }
function Show-GuiSectionHealthData { }
function Show-GuiSectionMeasureData { }
function Show-GuiSectionStartupData { }
function Show-GuiSectionCleanData { }
function Show-GuiSectionLogData { Update-GuiSectionLog }

function Get-GuiProfileTitle {
    param([Parameter(Mandatory)][string]$Id)
    $file = Join-Path $script:GuiRoot "profiles\$Id.json"
    if (-not [System.IO.File]::Exists($file)) { return $Id }
    $data = [System.IO.File]::ReadAllText($file, $script:GuiUtf8) | ConvertFrom-Json
    $title = $data.title.((Get-TuneupGuiLang))
    if ($title) { $title } else { $Id }
}

function Get-GuiLocalized {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }
    $text = $Value.((Get-TuneupGuiLang))
    if (-not $text) { $text = $Value.en }
    [string]$text
}

# Inicio: four reads at once, each filling its card when it arrives.
function Update-GuiSectionHome {
    $ui = $script:Gui.Ui
    Invoke-GuiJob -Action 'status' -Label (Get-TuneupGuiText -Key 'gui.nav.status') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
        $script:Gui.StatusDoc = $document
        $items = @($document.items)
        $ui = $script:Gui.Ui
        $ui.HomeAppliedValue.Text = [string]@($items | Where-Object { $_.status -eq 'ok' }).Count
        $drift = @($items | Where-Object { $_.status -eq 'drift' }).Count
        $ui.HomeAppliedNote.Text = $(if ($drift) { Get-TuneupGuiText -Key 'gui.home.drift' -Format $drift } elseif ($items.Count) { Get-TuneupGuiText -Key 'gui.home.noDrift' } else { Get-TuneupGuiText -Key 'gui.home.noRuns' })
        $runs = @($items | Group-Object -Property runId | Sort-Object Name -Descending | Select-Object -First 5)
        Set-GuiItemSource -Control $ui.HomeRunsList -Items @($runs | ForEach-Object { New-GuiRow -Title (Format-TuneupGuiRunId -Id $_.Name) -Value (Get-TuneupGuiCountText -Key 'gui.common.tweaks' -Count $_.Count) })
    }
    Invoke-GuiJob -Action 'clean' -Label (Get-TuneupGuiText -Key 'gui.nav.clean') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { return }
        $script:Gui.Ui.HomeFreeValue.Text = Format-TuneupGuiSize -Bytes $document.freeBytes
        $script:Gui.Ui.HomeFreeNote.Text = Get-TuneupGuiText -Key 'gui.home.freeNote' -Format (Format-TuneupGuiSize -Bytes $document.summary.removableBytes)
        Set-GuiCleanDocument -Document $document
    }
    Invoke-GuiJob -Action 'startup' -Label (Get-TuneupGuiText -Key 'gui.nav.startup') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { return }
        $script:Gui.Ui.HomeStartupValue.Text = [string]$document.summary.enabled
        $script:Gui.Ui.HomeStartupNote.Text = Get-TuneupGuiText -Key 'gui.home.startupNote' -Format $document.summary.canDisable, $document.summary.recommended
        Set-GuiStartupDocument -Document $document
    }
    Invoke-GuiJob -Action 'suggest' -Label (Get-TuneupGuiText -Key 'gui.home.suggestTitle') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { return }
        $script:Gui.Suggested = [string[]]@($document.suggestions | ForEach-Object { [string]$_.profile })
        Set-GuiItemSource -Control $script:Gui.Ui.HomeSuggestList -Items @($document.suggestions | ForEach-Object { [pscustomobject]@{ Title = Get-GuiProfileTitle -Id ([string]$_.profile) } })
    }
}

# Optimizar: the profiles, the high-risk tweaks and the rest outside profiles come from -List; the plan from -WhatIf with what is picked.
function Update-GuiSectionOptimize {
    $ui = $script:Gui.Ui
    $ui.OptPlanCard.Visibility = 'Collapsed'
    $ui.OptApplyCard.Visibility = 'Collapsed'
    Invoke-GuiJob -Action 'list' -Label (Get-TuneupGuiText -Key 'gui.nav.optimize') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
        $suggested = @($script:Gui.Suggested)
        $profiles = foreach ($profileData in @($document.profiles)) {
            $id = [string]$profileData.id
            $marks = @()
            if ($id -eq 'base') { $marks += Get-TuneupGuiText -Key 'gui.optimize.always' }
            if ($profileData.needsAdmin) { $marks += Get-TuneupGuiText -Key 'gui.common.adminMark' }
            New-GuiRow -Title ([string]$profileData.title) -Description ([string]$profileData.description) -Note ($marks -join ' ') -Checkable -Enabled ($id -ne 'base') `
                -Selected ($id -eq 'base' -or ($suggested -contains $id)) -Data $id
        }
        Set-GuiItemSource -Control $script:Gui.Ui.OptProfilesList -Items @($profiles)
        $high = @($document.tweaks | Where-Object { $_.risk -eq 'high' } | ForEach-Object { New-GuiRow -Title ([string]$_.title) -Description ([string]$_.why) -Checkable -Data ([string]$_.id) -Chip1 (Get-TuneupGuiText -Key 'risk.high') -Chip1Kind Critical })
        Set-GuiItemSource -Control $script:Gui.Ui.OptHighRiskList -Items $high
        $script:Gui.Ui.OptHighRiskExpander.Header = Get-TuneupGuiText -Key 'gui.optimize.highRisk' -Format $high.Count
        $script:Gui.Ui.OptHighRiskExpander.Visibility = $(if ($high.Count) { 'Visible' } else { 'Collapsed' })
        $script:Gui.Ui.OptHighRiskConfirmLabel.Text = Get-TuneupGuiText -Key 'gui.optimize.highRiskConfirm' -Format (Get-TuneupGuiText -Key 'menu.high.word')
        # The rest that no profile applies (preferences such as dark mode): only when picked by name.
        $extra = @($document.tweaks | Where-Object { $_.risk -ne 'high' -and -not @($_.profiles).Count } | ForEach-Object { New-GuiRow -Title ([string]$_.title) -Description ([string]$_.why) -Checkable -Data ([string]$_.id) })
        Set-GuiItemSource -Control $script:Gui.Ui.OptExtraList -Items $extra
        $script:Gui.Ui.OptExtraExpander.Header = Get-TuneupGuiText -Key 'gui.optimize.extra' -Format $extra.Count
        $script:Gui.Ui.OptExtraExpander.Visibility = $(if ($extra.Count) { 'Visible' } else { 'Collapsed' })
        if ($script:Gui.PlanAfterList) { $script:Gui.PlanAfterList = $false; Update-GuiPlan }
    }
}

function Get-GuiOptimizeRequest {
    $ui = $script:Gui.Ui
    $profiles = @($ui.OptProfilesList.ItemsSource | Where-Object { $_.Selected } | ForEach-Object { [string]$_.Data })
    if (-not $profiles.Count) { $profiles = @('base') }
    $include = @()
    $word = Get-TuneupGuiText -Key 'menu.high.word'
    if ([string]$ui.OptHighRiskConfirm.Text.Trim() -ieq $word) { $include += @($ui.OptHighRiskList.ItemsSource | Where-Object { $_.Selected } | ForEach-Object { [string]$_.Data }) }
    $include += @($ui.OptExtraList.ItemsSource | Where-Object { $_.Selected } | ForEach-Object { [string]$_.Data })
    $include += @($ui.OptPlanList.ItemsSource | Where-Object { $_.Selected -and $_.Data -and $_.Data.ask } | ForEach-Object { [string]$_.Data.id })
    @{ Profile = $profiles; Include = @($include | Select-Object -Unique) }
}

function Update-GuiPlan {
    $request = Get-GuiOptimizeRequest
    $request.PlanOnly = $true
    Invoke-GuiJob -Action 'apply' -Options $request -Label (Get-TuneupGuiText -Key 'gui.optimize.planButton') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
        Set-GuiPlanDocument -Document $document
    }
}

function Set-GuiPlanDocument {
    param([Parameter(Mandatory)]$Document)
    $ui = $script:Gui.Ui
    $script:Gui.PlanDoc = $Document
    $items = @($Document.items)
    $ui.OptPlanSummary.Text = Get-TuneupGuiText -Key 'gui.optimize.summary' -Format $Document.summary.apply, $Document.summary.skip
    # Added with Items.Add, not as ItemsSource: a control that went through the pipeline is a PSObject,
    # which WPF does not take for a control and shows as the name of its type.
    $ui.OptPreflightList.ItemsSource = $null
    $ui.OptPreflightList.Items.Clear()
    foreach ($check in @($Document.preflight)) {
        $border = New-Object System.Windows.Controls.Border
        $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'CautionBg')
        $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, 'Outline')
        $border.BorderThickness = 1; $border.CornerRadius = 8; $border.Padding = '14,10'; $border.Margin = '0,0,0,8'
        $text = New-Object System.Windows.Controls.TextBlock
        $text.Text = [string]$check.message; $text.TextWrapping = 'Wrap'
        $text.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'CautionFg')
        $border.Child = $text
        [void]$ui.OptPreflightList.Items.Add($border)
    }
    $groups = [ordered]@{ apply = @(); 'already-applied' = @(); 'needs-confirmation' = @(); other = @() }
    foreach ($item in $items) {
        $key = $(if ($item.action -eq 'apply') { 'apply' } elseif ($groups.Contains([string]$item.reason)) { [string]$item.reason } else { 'other' })
        $groups[$key] += $item
    }
    $script:Gui.PlanGroups = $groups
    $tabs = @(foreach ($key in $groups.Keys) { [pscustomobject]@{ Id = $key; Label = (Get-TuneupGuiText -Key "gui.plan.tab.$key" -Format @($groups[$key]).Count) } })
    # The first tab that has something; with nothing to apply, the plan says so before anything else.
    $script:Gui.PlanTab = @($groups.Keys | Where-Object { @($groups[$_]).Count }) + @('apply') | Select-Object -First 1
    if (-not @($groups['apply']).Count) { Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'gui.result.nothing') -Text (Get-TuneupGuiText -Key 'gui.optimize.nothingText') }
    Set-GuiTabRow -Panel $ui.OptPlanTabs -Tabs $tabs -Selected $script:Gui.PlanTab -OnPick { param($source) $script:Gui.PlanTab = [string]$source.Tag; Show-GuiPlanList }
    Show-GuiPlanList
    $ui.OptPlanCard.Visibility = 'Visible'
    $ui.OptApplyCard.Visibility = 'Visible'
    Update-GuiApplyButton
}

function Show-GuiPlanList {
    $rows = foreach ($item in @($script:Gui.PlanGroups[$script:Gui.PlanTab])) {
        $risk = Get-TuneupGuiText -Key "risk.$($item.risk)"
        $reason = $(if ($item.reason) { Get-TuneupGuiText -Key "reason.$($item.reason)" } else { '' })
        $ask = $item.reason -eq 'needs-confirmation'
        $admin = $(if ($item.needsAdmin) { Get-TuneupGuiText -Key 'gui.common.adminMark' } else { '' })
        New-GuiRow -Title ([string]$item.title) -Description ([string]$item.why) -Note (($reason, $admin | Where-Object { $_ }) -join ' - ') `
            -Chip1 $risk -Chip1Kind $(switch ($item.risk) { 'high' { 'Critical' } 'medium' { 'Caution' } default { 'Success' } }) -Checkable:$ask `
            -Data ([pscustomobject]@{ id = [string]$item.id; ask = $ask })
    }
    Set-GuiItemSource -Control $script:Gui.Ui.OptPlanList -Items @($rows)
}

function Update-GuiApplyButton {
    $ui = $script:Gui.Ui
    $document = $script:Gui.PlanDoc
    if ($null -eq $document) { return }
    $count = [int]$document.summary.apply
    $ui.OptApplyButton.Content = Get-TuneupGuiText -Key $(if ($count -eq 1) { 'gui.optimize.applyOne' } else { 'gui.optimize.apply' }) -Format $count
    $ui.OptApplyButton.IsEnabled = $count -gt 0
    $needsAdmin = [bool]$document.requiresAdmin -and -not $script:Gui.IsAdmin
    $ui.OptAdminNote.Visibility = $(if ($needsAdmin) { 'Visible' } else { 'Collapsed' })
    $ui.OptAdminNote.Text = Get-TuneupGuiText -Key 'gui.optimize.adminNote'
}

function Invoke-GuiApply {
    $document = $script:Gui.PlanDoc
    if ($null -eq $document) { return }
    $request = Get-GuiOptimizeRequest
    $count = [int]$document.summary.apply
    $script:Gui.Pending = [pscustomobject]@{ Request = $request; NeedsAdmin = [bool]$document.requiresAdmin }
    $restart = @($document.items | Where-Object { $_.action -eq 'apply' -and $_.rebootRequired }).Count
    $text = Get-TuneupGuiText -Key 'gui.optimize.confirmText'
    if ($restart) { $text += ' ' + (Get-TuneupGuiText -Key 'gui.optimize.confirmRestart' -Format $restart) }
    Show-GuiDialog -Title (Get-TuneupGuiText -Key 'gui.optimize.confirmTitle' -Format $count) -Text $text -PrimaryLabel ([string]$script:Gui.Ui.OptApplyButton.Content) `
        -SecondaryLabel (Get-TuneupGuiText -Key 'gui.optimize.backToPlan') -OnPrimary {
        $pending = $script:Gui.Pending
        Invoke-GuiAdminJob -Action 'apply' -Options $pending.Request -Label (Get-TuneupGuiText -Key 'gui.optimize.applying') -NeedsAdmin $pending.NeedsAdmin -Changes -OnDone { param($result) Show-GuiApplyResult -Result $result -Retry $null }
    }
}

# What an apply, re-apply or turning off did: a notice by its exit code, one row per tweak that did not go as
# planned, and the lists of the window read again.
function Show-GuiApplyResult {
    param([Parameter(Mandatory)]$Result, [scriptblock]$Retry)
    $document = $Result.Document
    if ($document.command -eq 'error') { Show-GuiError -Document $document -Retry $Retry; return }
    if ($document.command -eq 'plan') {
        Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'gui.result.nothing')
        return
    }
    $summary = $document.summary
    $kind = $(if ($Result.ExitCode -eq 0) { 'Success' } else { 'Warning' })
    $title = Get-TuneupGuiText -Key $(if ($Result.ExitCode -eq 0) { 'gui.result.applied' } else { 'gui.result.partial' }) -Format $summary.applied
    $lines = @($document.results | Where-Object { @('applied', 'skipped') -notcontains $_.status } | ForEach-Object {
            '{0}: {1}{2}' -f $_.title, (Get-TuneupGuiText -Key "status.$($_.status)"), $(if ($_.error) { " ($($_.error))" } elseif ($_.detail) { " ($($_.detail))" } else { '' })
        })
    $notes = @()
    if ($document.rebootRequired) { $notes += Get-TuneupGuiText -Key 'gui.result.reboot' }
    if ($document.signOutRequired) { $notes += Get-TuneupGuiText -Key 'gui.result.signOut' }
    Show-GuiNotice -Kind $kind -Title $title -Text ($notes -join ' ') -Details $lines
    $script:Gui.Loaded.Clear()
    [void]$script:Gui.Loaded.Add($script:Gui.Section)
}

# Estado: every tweak applied, by status; the re-apply of what Windows reverted.
function Update-GuiSectionStatus {
    Invoke-GuiJob -Action 'status' -Label (Get-TuneupGuiText -Key 'gui.nav.status') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
        $script:Gui.StatusDoc = $document
        Show-GuiStatusList
    }
}

function Show-GuiStatusList {
    $ui = $script:Gui.Ui
    $items = @($script:Gui.StatusDoc.items)
    $statuses = @('all', 'ok', 'drift', 'needs-admin', 'not-present', 'unknown')
    if (-not $script:Gui.StatusTab) { $script:Gui.StatusTab = 'all' }
    $tabs = @(foreach ($status in $statuses) {
            $count = $(if ($status -eq 'all') { $items.Count } else { @($items | Where-Object { $_.status -eq $status }).Count })
            if ($status -ne 'all' -and -not $count) { continue }
            [pscustomobject]@{ Id = $status; Label = (Get-TuneupGuiText -Key "gui.statusTab.$status" -Format $count) }
        })
    Set-GuiTabRow -Panel $ui.StatusTabs -Tabs $tabs -Selected $script:Gui.StatusTab -OnPick { param($source) $script:Gui.StatusTab = [string]$source.Tag; Show-GuiStatusList }
    $shown = @($items | Where-Object { $script:Gui.StatusTab -eq 'all' -or $_.status -eq $script:Gui.StatusTab })
    Set-GuiItemSource -Control $ui.StatusList -Items @($shown | ForEach-Object {
            $kind = switch ($_.status) { 'ok' { 'Success' } 'drift' { 'Caution' } 'needs-admin' { 'Caution' } default { 'Neutral' } }
            New-GuiRow -Title ([string]$_.title) -Description (Format-TuneupGuiRunId -Id ([string]$_.runId)) -Chip1 (Get-TuneupGuiText -Key "status.$($_.status)") -Chip1Kind $kind
        })
    if (-not $items.Count) { Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'gui.status.empty') -Text (Get-TuneupGuiText -Key 'gui.status.emptyText') }
    $drift = @($items | Where-Object { $_.status -eq 'drift' }).Count
    $ui.StatusReapplyButton.IsEnabled = $drift -gt 0
    $ui.StatusReapplyButton.ToolTip = $(if ($drift) { $null } else { Get-TuneupGuiText -Key 'gui.status.nothingReverted' })
}

function Invoke-GuiReapply {
    Invoke-GuiJob -Action 'reapply' -Options @{ PlanOnly = $true } -Label (Get-TuneupGuiText -Key 'gui.status.reapply') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
        $count = [int]$document.summary.apply
        if (-not $count) { Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'gui.result.nothing'); return }
        $script:Gui.Pending = [pscustomobject]@{ NeedsAdmin = [bool]$document.requiresAdmin }
        Show-GuiDialog -Title (Get-TuneupGuiText -Key 'gui.status.reapplyTitle' -Format $count) -Text (Get-TuneupGuiText -Key 'gui.optimize.confirmText') `
            -PrimaryLabel (Get-TuneupGuiText -Key 'gui.status.reapply') -OnPrimary {
            Invoke-GuiAdminJob -Action 'reapply' -Label (Get-TuneupGuiText -Key 'gui.status.reapply') -NeedsAdmin $script:Gui.Pending.NeedsAdmin -Changes -OnDone { param($r) Show-GuiApplyResult -Result $r; Update-GuiSectionStatus }
        }
    }
}

# Deshacer: the runs that -Status knows, newest first.
function Update-GuiSectionUndo {
    Invoke-GuiJob -Action 'status' -Label (Get-TuneupGuiText -Key 'gui.nav.undo') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
        $script:Gui.StatusDoc = $document
        $runs = @($document.items | Group-Object -Property runId | Sort-Object Name -Descending)
        if (-not $runs.Count) { Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'gui.undo.empty') -Text (Get-TuneupGuiText -Key 'gui.undo.emptyText') }
        Set-GuiItemSource -Control $script:Gui.Ui.UndoRunsList -Items @($runs | ForEach-Object {
                $date = Format-TuneupGuiRunId -Id $_.Name
                [pscustomobject]@{
                    Id = $_.Name; Title = $date; Description = (Get-TuneupGuiCountText -Key 'gui.common.tweaks' -Count $_.Count)
                    PickLabel = Get-TuneupGuiText -Key 'gui.undo.pick'; PickTag = "pick:$($_.Name)"; PickName = (Get-TuneupGuiText -Key 'gui.undo.pick') + ' ' + $date
                    UndoLabel = Get-TuneupGuiText -Key 'gui.undo.run'; UndoTag = "undo:$($_.Name)"; UndoName = (Get-TuneupGuiText -Key 'gui.undo.run') + ' ' + $date
                }
            })
    }
}

function Invoke-GuiUndo {
    param([Parameter(Mandatory)][string]$RunId, [string]$TweakId)
    $options = @{ Run = $RunId }
    if ($TweakId) { $options.Tweak = @($TweakId) }
    $script:Gui.Pending = [pscustomobject]@{ Options = $options }
    $retry = { Invoke-GuiJob -Action 'undo' -Options $script:Gui.Pending.Options -Label (Get-TuneupGuiText -Key 'gui.undo.running') -Changes -Elevated -OnDone { param($r) Show-GuiUndoResult -Result $r } }
    $script:Gui.UndoRetry = $retry
    Invoke-GuiJob -Action 'undo' -Options $options -Label (Get-TuneupGuiText -Key 'gui.undo.running') -Changes -OnDone { param($r) Show-GuiUndoResult -Result $r }
}

function Show-GuiUndoResult {
    param([Parameter(Mandatory)]$Result)
    $document = $Result.Document
    if ($document.command -eq 'error') { Show-GuiError -Document $document -Retry $script:Gui.UndoRetry; return }
    $kind = $(if ($Result.ExitCode -eq 0) { 'Success' } else { 'Warning' })
    $title = Get-TuneupGuiText -Key $(if ($Result.ExitCode -eq 0) { 'gui.undo.done' } else { 'gui.undo.partial' }) -Format $document.summary.restored
    $lines = @($document.results | Where-Object { $_.status -ne 'restored' } | ForEach-Object {
            '{0}: {1}{2}' -f $_.title, (Get-TuneupGuiText -Key "status.$($_.status)"), $(if ($_.error) { " ($($_.error))" } else { '' })
            foreach ($line in @($_.manual | Where-Object { $_ })) { "    $line" }
        })
    Show-GuiNotice -Kind $kind -Title $title -Details $lines
    $script:Gui.Loaded.Clear()
    Update-GuiSectionUndo
}

function Update-GuiSectionHealth {
    $ui = $script:Gui.Ui
    $ui.HealthAdminNote.Visibility = $(if ($script:Gui.IsAdmin) { 'Collapsed' } else { 'Visible' })
    $phases = @('sfc', 'scan', 'repair', 'sfcAgain') | ForEach-Object { New-GuiRow -Title (Get-TuneupGuiText -Key "gui.health.phase.$_") }
    Set-GuiItemSource -Control $ui.HealthPhaseList -Items @($phases)
    if (-not $ui.HealthResultText.Text) { $ui.HealthResultText.Text = Get-TuneupGuiText -Key 'gui.health.notYet' }
}

function Invoke-GuiHealth {
    param([switch]$Repair)
    $ui = $script:Gui.Ui
    Invoke-GuiAdminJob -Action 'health' -Options @{ Repair = [bool]($Repair -or $ui.HealthRepairCheck.IsChecked) } -Label (Get-TuneupGuiText -Key 'gui.nav.health') -NeedsAdmin $true -OnDone {
        param($result)
        $document = $result.Document
        $ui = $script:Gui.Ui
        if ($document.command -eq 'error') { $ui.HealthResultText.Text = ''; Show-GuiError -Document $document -Retry { Invoke-GuiHealth }; return }
        $state = $(if ($null -ne $document.after) { $document.after } else { $document.before })
        $ui.HealthResultText.Text = Get-TuneupGuiText -Key "health.recommendation.$($document.recommendation)"
        $rows = @(
            New-GuiRow -Title 'SFC' -Value (Get-TuneupGuiText -Key "health.sfc.$($state.sfc.status)")
            New-GuiRow -Title 'DISM' -Value (Get-TuneupGuiText -Key "health.store.$($state.componentStore.state)" -Format ([int]$state.componentStore.detected))
        )
        $rows += @($state.sfc.unrepairedFiles | Where-Object { $_ } | ForEach-Object { New-GuiRow -Title ([string]$_) -Chip1 (Get-TuneupGuiText -Key 'health.sfc.unrepaired') -Chip1Kind Critical })
        Set-GuiItemSource -Control $ui.HealthResultList -Items $rows
        $ui.HealthRepairButton.Visibility = $(if ($document.recommendation -eq 'run-repair') { 'Visible' } else { 'Collapsed' })
        if ($document.rebootRecommended) { Show-GuiNotice -Kind Warning -Title (Get-TuneupGuiText -Key 'gui.result.reboot') }
    }
}

function Update-GuiSectionMeasure {
    $ui = $script:Gui.Ui
    if ($ui.MeasureIdleBox.SelectedIndex -lt 0) { $ui.MeasureIdleBox.SelectedIndex = 2 }
    if ($ui.MeasureCompareBox.SelectedIndex -lt 0) { $ui.MeasureCompareBox.SelectedIndex = 0 }
    if (-not $ui.MeasureResultText.Text) { $ui.MeasureResultText.Text = Get-TuneupGuiText -Key 'gui.measure.empty' }
}

function Invoke-GuiMeasure {
    $ui = $script:Gui.Ui
    $options = @{ IdleSeconds = [int]$ui.MeasureIdleBox.SelectedItem.Tag }
    if ([string]$ui.MeasureCompareBox.SelectedItem.Tag) { $options.Compare = @([string]$ui.MeasureCompareBox.SelectedItem.Tag) }
    Invoke-GuiJob -Action 'measure' -Options $options -Label (Get-TuneupGuiText -Key 'gui.nav.measure') -OnDone {
        param($result)
        $document = $result.Document
        $ui = $script:Gui.Ui
        if ($document.command -eq 'error') { $ui.MeasureResultText.Text = ''; Show-GuiError -Document $document; return }
        $ui.MeasureResultText.Text = Get-TuneupGuiText -Key 'gui.measure.saved' -Format ([string]$document.id)
        $metrics = $document.measurement.metrics
        $byMetric = @{}
        foreach ($item in @($document.comparison.items | Where-Object { $_ })) { $byMetric[[string]$item.metric] = $item }
        $rows = foreach ($property in @($metrics.PSObject.Properties)) {
            $value = $(if ($null -eq $property.Value) { Get-TuneupGuiText -Key 'gui.measure.missing' } else { [string]$property.Value })
            $compared = $byMetric[$property.Name]
            $delta = $(if ($null -ne $compared -and $null -ne $compared.delta) { Get-TuneupGuiText -Key 'gui.measure.delta' -Format $compared.before, ('{0:+0.##;-0.##;0}' -f [double]$compared.delta) } else { '' })
            New-GuiRow -Title (Get-TuneupGuiText -Key "metric.$($property.Name)") -Value $value -Note $delta
        }
        Set-GuiItemSource -Control $ui.MeasureList -Items @($rows)
    }
}

function Update-GuiSectionStartup {
    Invoke-GuiJob -Action 'startup' -Label (Get-TuneupGuiText -Key 'gui.nav.startup') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
        Set-GuiStartupDocument -Document $document
        Show-GuiStartupList
    }
}

function Set-GuiStartupDocument {
    param([Parameter(Mandatory)]$Document)
    $script:Gui.StartupDoc = $Document
    $script:Gui.StartupRows = @(foreach ($entry in @($Document.entries)) {
            $chip = ''; $kind = 'Neutral'; $note = ''
            if ($entry.recommended) { $chip = Get-TuneupGuiText -Key 'gui.startup.recommended'; $kind = 'Info'; $note = Get-TuneupGuiText -Key "startup.recommend.$($entry.recommendedReason)" }
            elseif ($entry.protected) { $chip = Get-TuneupGuiText -Key 'gui.startup.protected'; $note = Get-TuneupGuiText -Key "startup.protected.$($entry.protected)" }
            elseif (-not $entry.enabled) { $chip = Get-TuneupGuiText -Key 'gui.startup.off' }
            $usage = $(if ($entry.running -eq $true -and $null -ne $entry.memoryMB) { Get-TuneupGuiText -Key 'startup.usage.running' -Format $entry.memoryMB } elseif ($entry.running -eq $true) { Get-TuneupGuiText -Key 'startup.usage.runningNoMemory' } else { '' })
            $publisher = $(if ($entry.publisher) { " ($($entry.publisher))" } else { '' })
            New-GuiRow -Title ([string]$entry.name + $publisher) -Description (Get-TuneupGuiText -Key "startup.source.$($entry.source)") -Note $note -Value $usage `
                -Chip1 $chip -Chip1Kind $kind -Chip2 $(if ($entry.canDisable -and $entry.needsAdmin) { Get-TuneupGuiText -Key 'gui.common.adminMark' } else { '' }) -Chip2Kind Caution `
                -Checkable -Enabled ([bool]$entry.canDisable) -Data $entry
        })
}

function Show-GuiStartupList {
    $ui = $script:Gui.Ui
    if ($null -eq $script:Gui.StartupDoc) { Update-GuiSectionStartup; return }
    if (-not $script:Gui.StartupTab) { $script:Gui.StartupTab = 'canDisable' }
    $rows = @($script:Gui.StartupRows)
    $filters = [ordered]@{
        recommended = { param($row) $row.Data.recommended }
        canDisable  = { param($row) $row.Data.canDisable }
        protected   = { param($row) $row.Data.protected }
        all         = { param($row) $null -ne $row }
    }
    $tabs = @(foreach ($key in $filters.Keys) { [pscustomobject]@{ Id = $key; Label = (Get-TuneupGuiText -Key "gui.startup.tab.$key" -Format @($rows | Where-Object { & $filters[$key] $_ }).Count) } })
    Set-GuiTabRow -Panel $ui.StartupTabs -Tabs $tabs -Selected $script:Gui.StartupTab -OnPick { param($source) $script:Gui.StartupTab = [string]$source.Tag; Show-GuiStartupList }
    $filter = $filters[$script:Gui.StartupTab]
    Set-GuiItemSource -Control $ui.StartupList -Items @($rows | Where-Object { & $filter $_ })
    if (-not $script:Gui.StartupDoc.isAdmin) { Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'startup.unelevatedNote') }
    Update-GuiStartupButton
}

function Update-GuiStartupButton {
    $count = @($script:Gui.StartupRows | Where-Object { $_.Selected }).Count
    $script:Gui.Ui.StartupApplyButton.Content = Get-TuneupGuiText -Key $(if ($count -eq 1) { 'gui.startup.applyOne' } else { 'gui.startup.apply' }) -Format $count
    $script:Gui.Ui.StartupApplyButton.IsEnabled = $count -gt 0
    $script:Gui.Ui.StartupPlanButton.IsEnabled = $count -gt 0
}

function Invoke-GuiStartup {
    param([switch]$PlanOnly)
    $picked = @($script:Gui.StartupRows | Where-Object { $_.Selected })
    if (-not $picked.Count) { return }
    $ids = @($picked | ForEach-Object { [string]$_.Data.id })
    $needsAdmin = [bool]@($picked | Where-Object { $_.Data.needsAdmin }).Count
    if ($PlanOnly) {
        Invoke-GuiJob -Action 'startup-disable' -Options @{ Disable = $ids; PlanOnly = $true } -Label (Get-TuneupGuiText -Key 'gui.common.seePlan') -OnDone {
            param($result)
            $document = $result.Document
            if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
            $lines = @($document.items | ForEach-Object { '{0}: {1}' -f $_.title, $(if ($_.action -eq 'apply') { Get-TuneupGuiText -Key 'gui.startup.willTurnOff' } else { Get-TuneupGuiText -Key "reason.$($_.reason)" }) })
            Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'gui.optimize.summary' -Format $document.summary.apply, $document.summary.skip) -Details $lines
        }
        return
    }
    $script:Gui.Pending = [pscustomobject]@{ Ids = $ids; NeedsAdmin = $needsAdmin }
    Show-GuiDialog -Title ([string]$script:Gui.Ui.StartupApplyButton.Content + '?') -Text (Get-TuneupGuiText -Key 'gui.startup.confirmText') -PrimaryLabel ([string]$script:Gui.Ui.StartupApplyButton.Content) -OnPrimary {
        $pending = $script:Gui.Pending
        Invoke-GuiAdminJob -Action 'startup-disable' -Options @{ Disable = $pending.Ids } -Label (Get-TuneupGuiText -Key 'gui.startup.running') -NeedsAdmin $pending.NeedsAdmin -Changes -OnDone {
            param($result)
            Show-GuiApplyResult -Result $result
            Update-GuiSectionStartup
        }
    }
}

function Update-GuiSectionClean {
    $large = [bool]$script:Gui.Ui.CleanLargeCheck.IsChecked
    Invoke-GuiJob -Action 'clean' -Options @{ Large = $large } -Label (Get-TuneupGuiText -Key 'gui.nav.clean') -OnDone {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
        Set-GuiCleanDocument -Document $document
        Show-GuiCleanList
    }
}

function Set-GuiCleanDocument {
    param([Parameter(Mandatory)]$Document)
    $script:Gui.CleanDoc = $Document
    $previous = ''
    $script:Gui.CleanRows = @(foreach ($rule in @($Document.rules | Where-Object { -not $_.reportOnly })) {
            $header = $(if ($rule.category -ne $previous) { Get-TuneupGuiText -Key "clean.category.$($rule.category)" } else { '' })
            $previous = [string]$rule.category
            # Without administrator a folder of the machine may not be readable at all: that is not "empty".
            $size = $(if ($rule.needsAdmin -and -not $Document.isAdmin -and -not $rule.files -and ($rule.unreadable -or -not $rule.paths.Count)) { Get-TuneupGuiText -Key 'clean.unmeasured' }
                elseif ($rule.paths.Count) { Format-TuneupGuiSize -Bytes $rule.bytes } else { Get-TuneupGuiText -Key 'clean.absent' })
            $reason = $(if ($rule.reason) { Get-TuneupGuiText -Key "clean.reason.$($rule.reason)" -Format ((@($rule.runningApps) + @($rule.runningServices)) -join ', ') } else { '' })
            $noteKind = $(if (@('app-running', 'service-running') -contains $rule.reason) { 'Caution' } else { 'Secondary' })
            New-GuiRow -Title ([string]$rule.title) -Description ([string]$rule.why) -Value $size -Note $reason -NoteKind $noteKind -Header $header `
                -Chip1 $(if ($rule.needsAdmin) { Get-TuneupGuiText -Key 'gui.common.adminMark' } else { '' }) -Chip1Kind Caution -Checkable -Enabled ([bool]$rule.canRemove) -Data $rule
        })
}

function Show-GuiCleanList {
    $ui = $script:Gui.Ui
    $document = $script:Gui.CleanDoc
    if ($null -eq $document) { Update-GuiSectionClean; return }
    Set-GuiItemSource -Control $ui.CleanList -Items @($script:Gui.CleanRows)
    Set-GuiItemSource -Control $ui.CleanReportList -Items @($document.rules | Where-Object { $_.reportOnly -and $_.paths.Count } | ForEach-Object {
            New-GuiRow -Title ([string]$_.title) -Description ([string]$_.why) -Value (Format-TuneupGuiSize -Bytes $_.bytes) -Note (Get-TuneupGuiText -Key 'gui.clean.byHand' -Format $_.hint)
        })
    $largest = @()
    if ($null -ne $document.largest) {
        $largest = @($document.largest.items | ForEach-Object { New-GuiRow -Title ([string]$_.path) -Value (Format-TuneupGuiSize -Bytes $_.bytes) -Note $(if ($_.partial) { Get-TuneupGuiText -Key 'clean.largest.partial' } else { '' }) })
    }
    Set-GuiItemSource -Control $ui.CleanLargeList -Items $largest
    if (-not $document.isAdmin) { Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'clean.unelevatedNote') }
    Update-GuiCleanButton
}

function Update-GuiCleanButton {
    $picked = @($script:Gui.CleanRows | Where-Object { $_.Selected })
    $bytes = [long](@($picked | ForEach-Object { [long]$_.Data.bytes } | Measure-Object -Sum).Sum)
    $ui = $script:Gui.Ui
    $ui.CleanRemoveButton.Content = Get-TuneupGuiText -Key $(if ($picked.Count -eq 1) { 'gui.clean.removeOne' } else { 'gui.clean.remove' }) -Format $picked.Count, (Format-TuneupGuiSize -Bytes $bytes)
    $ui.CleanRemoveButton.IsEnabled = $picked.Count -gt 0
    $ui.CleanPreviewButton.IsEnabled = $picked.Count -gt 0
    $ui.CleanSummary.Text = $(if ($picked.Count) { Get-TuneupGuiText -Key 'gui.clean.summary' -Format (Format-TuneupGuiSize -Bytes $bytes) } else { Get-TuneupGuiText -Key 'gui.clean.pick' })
}

function Invoke-GuiClean {
    param([switch]$PlanOnly)
    $picked = @($script:Gui.CleanRows | Where-Object { $_.Selected })
    if (-not $picked.Count) { return }
    $ids = @($picked | ForEach-Object { [string]$_.Data.id })
    $needsAdmin = [bool]@($picked | Where-Object { $_.Data.needsAdmin }).Count
    $onDone = {
        param($result)
        $document = $result.Document
        if ($document.command -eq 'error') { Show-GuiError -Document $document; return }
        $removal = $document.removal
        $lines = @($removal.results | ForEach-Object {
                $why = $(if ($_.reason) { ' - ' + (Get-TuneupGuiText -Key "clean.reason.$($_.reason)" -Format ((@($_.runningApps) + @($_.runningServices)) -join ', ')) } else { '' })
                '{0}: {1}{2}' -f $_.title, (Format-TuneupGuiSize -Bytes $_.freedBytes), $why
            })
        if ($removal.planOnly) {
            Show-GuiNotice -Kind Info -Title (Get-TuneupGuiText -Key 'clean.planOnly' -Format (Format-TuneupGuiSize -Bytes $removal.freedBytes)) -Details $lines
            return
        }
        $kept = [int](@($removal.results | Measure-Object -Property keptFiles -Sum).Sum)
        $title = Get-TuneupGuiText -Key 'gui.clean.freed' -Format (Format-TuneupGuiSize -Bytes $removal.freedBytes), (Format-TuneupGuiSize -Bytes $removal.freeBytesAfter)
        $text = $(if ($kept) { Get-TuneupGuiText -Key 'gui.clean.kept' -Format $kept } else { '' })
        Show-GuiNotice -Kind $(if ($result.ExitCode -eq 0) { 'Success' } else { 'Warning' }) -Title $title -Text $text -Details $lines
        Update-GuiSectionClean
    }
    if ($PlanOnly) {
        Invoke-GuiJob -Action 'clean-remove' -Options @{ Remove = $ids; PlanOnly = $true } -Label (Get-TuneupGuiText -Key 'gui.clean.preview') -OnDone $onDone
        return
    }
    $bytes = [long](@($picked | ForEach-Object { [long]$_.Data.bytes } | Measure-Object -Sum).Sum)
    $script:Gui.Pending = [pscustomobject]@{ Ids = $ids; NeedsAdmin = $needsAdmin; OnDone = $onDone }
    Show-GuiDialog -Title (Get-TuneupGuiText -Key 'gui.clean.confirmTitle' -Format $picked.Count, (Format-TuneupGuiSize -Bytes $bytes)) -Text (Get-TuneupGuiText -Key 'gui.clean.confirmText') `
        -PrimaryLabel ([string]$script:Gui.Ui.CleanRemoveButton.Content) -SecondaryLabel (Get-TuneupGuiText -Key 'gui.clean.keep') -Danger -OnPrimary {
        $pending = $script:Gui.Pending
        Invoke-GuiAdminJob -Action 'clean-remove' -Options @{ Remove = $pending.Ids } -Label (Get-TuneupGuiText -Key 'gui.clean.running') -NeedsAdmin $pending.NeedsAdmin -Changes -OnDone $pending.OnDone
    }
}

function Update-GuiSectionLog {
    $ui = $script:Gui.Ui
    $ui.LogNote.Text = Get-TuneupGuiText -Key 'gui.log.note' -Format (Hide-TuneupGuiProfile -Text ([string](Get-TuneupGuiLogFolder)))
    if (-not $script:Gui.LogTab) { $script:Gui.LogTab = 'all' }
    $lines = @(Get-TuneupGuiLogLine)
    $tabs = @(foreach ($level in 'all', 'INFO', 'WARN', 'ERROR') {
            $count = $(if ($level -eq 'all') { $lines.Count } else { @($lines | Where-Object { $_.Level -eq $level }).Count })
            [pscustomobject]@{ Id = $level; Label = (Get-TuneupGuiText -Key "gui.log.tab.$level" -Format $count) }
        })
    Set-GuiTabRow -Panel $ui.LogTabs -Tabs $tabs -Selected $script:Gui.LogTab -OnPick { param($source) $script:Gui.LogTab = [string]$source.Tag; Update-GuiSectionLog }
    $shown = @($lines | Where-Object { $script:Gui.LogTab -eq 'all' -or $_.Level -eq $script:Gui.LogTab })
    [array]::Reverse($shown)
    Set-GuiItemSource -Control $ui.LogList -Items @($shown | ForEach-Object {
            $keys = switch ($_.Level) { 'ERROR' { @('CriticalBg', 'CriticalFg') } 'WARN' { @('CautionBg', 'CautionFg') } default { @('InfoBg', 'InfoFg') } }
            [pscustomobject]@{ Time = $_.Time; Text = $_.Text; LevelText = (Get-TuneupGuiText -Key "gui.log.level.$($_.Level)"); LevelBg = (Get-GuiBrush $keys[0]); LevelFg = (Get-GuiBrush $keys[1]) }
        })
}

function Get-GuiLogText {
    (@(Get-TuneupGuiLogLine) | ForEach-Object { '{0} {1,-5} {2}' -f $_.Time, $_.Level, $_.Text }) -join [Environment]::NewLine
}

# --- The window -----------------------------------------------------------------------------------------

function Get-GuiEnvironmentText {
    try {
        $key = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $build = [int]$key.CurrentBuild
        $family = $(if ($build -ge 22000) { '11' } else { '10' })
        $edition = switch -Regex ([string]$key.EditionID) { '^Core' { 'Home' } '^Professional' { 'Pro' } '^Enterprise' { 'Enterprise' } '^Education' { 'Education' } default { [string]$key.EditionID } }
        Get-TuneupGuiText -Key 'gui.header.env' -Format $family, $edition, $build
    } catch {
        'Windows'
    }
}

function Register-GuiEvent {
    $ui = $script:Gui.Ui
    $window = $script:Gui.Window
    foreach ($nav in $ui.NavPanel.Children) {
        $nav.Add_Checked({ param($source) if (-not $script:Gui.Navigating) { Show-GuiSection -Name ([string]$source.Tag) } })
    }
    foreach ($button in @($ui.HomeStatusButton, $ui.HomeCleanButton, $ui.HomeStartupButton)) {
        $button.Add_Click({ param($source) Show-GuiSection -Name ([string]$source.Tag) })
    }
    $ui.HomeSuggestButton.Add_Click({ $script:Gui.PlanAfterList = $true; Show-GuiSection -Name 'Optimize' -Refresh })
    $ui.RelaunchAdminButton.Add_Click({ Restart-GuiElevated })
    $ui.OpenLogButton.Add_Click({ Show-GuiSection -Name 'Log' })
    $ui.CancelButton.Add_Click({
            foreach ($entry in @($script:Gui.Jobs.ToArray() | Where-Object { -not $_.Changes -and -not $_.Job.Elevated })) {
                Stop-TuneupGuiJob -Job $entry.Job
                [void]$script:Gui.Jobs.Remove($entry)
            }
            $script:Gui.Ui.StatusText.Text = Get-TuneupGuiText -Key 'gui.status.cancelled'
            $script:Gui.LastStatus = $true
            $script:Gui.Loaded.Remove($script:Gui.Section) | Out-Null
            Update-GuiBusy
        })

    # Check boxes inside the lists: the row keeps what was picked, and the buttons follow.
    $checkHandler = [System.Windows.RoutedEventHandler] {
        $source = $args[0]
        $e = $args[1]
        $box = $e.OriginalSource
        if ($box -isnot [System.Windows.Controls.CheckBox] -or $null -eq $box.DataContext -or $null -eq $box.DataContext.PSObject.Properties['Selected']) { return }
        $box.DataContext.Selected = [bool]$box.IsChecked
        switch ($source.Name) {
            'StartupList' { Update-GuiStartupButton }
            'CleanList' { Update-GuiCleanButton }
        }
    }
    foreach ($list in @($ui.OptProfilesList, $ui.OptHighRiskList, $ui.OptExtraList, $ui.OptPlanList, $ui.StartupList, $ui.CleanList)) {
        $list.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $checkHandler)
    }
    $ui.UndoRunsList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
            $e = $args[1]
            $tag = [string]$e.OriginalSource.Tag
            if ($tag -notmatch '^(pick|undo):(.+)$') { return }
            $runId = $Matches[2]
            $script:Gui.UndoRun = $runId
            if ($Matches[1] -eq 'undo') {
                Show-GuiDialog -Title (Get-TuneupGuiText -Key 'gui.undo.confirmTitle' -Format (Format-TuneupGuiRunId -Id $runId)) -Text (Get-TuneupGuiText -Key 'gui.undo.confirmText') `
                    -PrimaryLabel (Get-TuneupGuiText -Key 'gui.undo.run') -OnPrimary { Invoke-GuiUndo -RunId $script:Gui.UndoRun }
                return
            }
            $tweaks = @($script:Gui.StatusDoc.items | Where-Object { $_.runId -eq $runId } | ForEach-Object { [pscustomobject]@{ Title = [string]$_.title; Id = [string]$_.id } })
            Show-GuiDialog -Title (Get-TuneupGuiText -Key 'gui.undo.pickTitle') -ListItems $tweaks -PrimaryLabel (Get-TuneupGuiText -Key 'gui.undo.one') -OnPrimary {
                $item = $script:Gui.Ui.DialogList.SelectedItem
                if ($null -ne $item) { Invoke-GuiUndo -RunId $script:Gui.UndoRun -TweakId $item.Id }
            }
        })

    $ui.OptPlanButton.Add_Click({ Update-GuiPlan })
    $ui.OptApplyButton.Add_Click({ Invoke-GuiApply })
    $ui.OptExportButton.Add_Click({
            $dialog = New-Object Microsoft.Win32.SaveFileDialog
            $dialog.FileName = 'windows-tuneup-plan.json'
            $dialog.Filter = 'JSON|*.json'
            if ($dialog.ShowDialog($script:Gui.Window)) { [System.IO.File]::WriteAllText($dialog.FileName, ($script:Gui.PlanDoc | ConvertTo-Json -Depth 10), $script:GuiUtf8) }
        })
    $ui.StatusReapplyButton.Add_Click({ Invoke-GuiReapply })
    $ui.HealthRunButton.Add_Click({ Invoke-GuiHealth })
    $ui.HealthRepairButton.Add_Click({ Invoke-GuiHealth -Repair })
    $ui.MeasureRunButton.Add_Click({ Invoke-GuiMeasure })
    $ui.StartupPlanButton.Add_Click({ Invoke-GuiStartup -PlanOnly })
    $ui.StartupApplyButton.Add_Click({ Invoke-GuiStartup })
    $ui.CleanPreviewButton.Add_Click({ Invoke-GuiClean -PlanOnly })
    $ui.CleanRemoveButton.Add_Click({ Invoke-GuiClean })
    $ui.CleanLargeCheck.Add_Click({ Update-GuiSectionClean })
    $ui.LogCopyButton.Add_Click({ [System.Windows.Clipboard]::SetText((Get-GuiLogText)) })
    $ui.LogSaveButton.Add_Click({
            $dialog = New-Object Microsoft.Win32.SaveFileDialog
            $dialog.FileName = 'windows-tuneup-gui.log'
            $dialog.Filter = 'Log|*.log|Text|*.txt'
            if ($dialog.ShowDialog($script:Gui.Window)) { [System.IO.File]::WriteAllText($dialog.FileName, (Get-GuiLogText), $script:GuiLogEncoding) }
        })
    $ui.LogFolderButton.Add_Click({ Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + (Get-TuneupGuiLogFolder) + '"') })
    $ui.LogRunsButton.Add_Click({
            $folder = $(if ($script:Gui.IsAdmin) { [System.IO.Path]::Combine([Environment]::GetFolderPath('CommonApplicationData'), 'windows-tuneup\runs') } else { [System.IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'windows-tuneup\runs') })
            if (-not [System.IO.Directory]::Exists($folder)) { $folder = Split-Path $folder -Parent }
            if ([System.IO.Directory]::Exists($folder)) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $folder + '"') }
        })

    $ui.DialogPrimary.Add_Click({
            $action = $script:Gui.DialogAction
            Close-GuiDialog
            if ($null -ne $action) { & $action }
        })
    $ui.DialogSecondary.Add_Click({ Close-GuiDialog })

    $ui.LanguageBox.Add_SelectionChanged({
            if ($script:Gui.Initializing) { return }
            $lang = [string]$script:Gui.Ui.LanguageBox.SelectedItem.Tag
            $script:Gui.Settings.lang = $lang
            Save-TuneupGuiSetting -Settings $script:Gui.Settings
            # A new window in the other language, in the same section.
            $script:Gui.Reopen = [pscustomobject]@{ Lang = $lang; Section = $script:Gui.Section }
            $script:Gui.Window.Close()
        })
    $ui.ThemeBox.Add_SelectionChanged({
            if ($script:Gui.Initializing) { return }
            $script:Gui.Settings.theme = [string]$script:Gui.Ui.ThemeBox.SelectedItem.Tag
            Save-TuneupGuiSetting -Settings $script:Gui.Settings
            $script:Gui.Reopen = [pscustomobject]@{ Lang = (Get-TuneupGuiLang); Section = $script:Gui.Section }
            $script:Gui.Window.Close()
        })

    $window.Add_PreviewKeyDown({
            $e = $args[1]
            if ($script:Gui.Ui.DialogLayer.Visibility -eq 'Visible' -and $e.Key -eq 'Escape') { Close-GuiDialog; $e.Handled = $true; return }
            if ($e.Key -eq 'F5' -and $script:Gui.Ui.DialogLayer.Visibility -ne 'Visible') { Show-GuiSection -Name $script:Gui.Section -Refresh; $e.Handled = $true }
        })
    $window.Add_Closing({
            $e = $args[1]
            if ($null -ne $script:Gui.Changing -and -not $script:Gui.CloseConfirmed) {
                $e.Cancel = $true
                Show-GuiDialog -Title (Get-TuneupGuiText -Key 'gui.close.title') -Text (Get-TuneupGuiText -Key 'gui.close.text') -PrimaryLabel (Get-TuneupGuiText -Key 'gui.close.confirm') `
                    -OnPrimary { $script:Gui.CloseConfirmed = $true; $script:Gui.Window.Close() }
            }
        })
    $window.Dispatcher.Add_UnhandledException({
            $e = $args[1]
            $e.Handled = $true
            Show-GuiFailure -Text (Get-TuneupGuiText -Key 'gui.failure.unexpected') -Details ($e.Exception.ToString())
        })
}

# Opens the window and waits until it closes. Gives what to open next: a language change reopens it.
function Show-TuneupGui {
    param([string]$Section = 'Home', [Parameter(Mandatory)]$Settings)
    $theme = Get-TuneupGuiTheme -Choice $Settings.theme -HighContrast ([System.Windows.SystemParameters]::HighContrast)
    $window = Import-GuiWindow -Theme $theme
    $ui = @{}
    foreach ($name in $script:GuiElementNames) {
        $element = $window.FindName($name)
        if ($null -eq $element) { throw "MainWindow.xaml has no element named $name" }
        $ui[$name] = $element
    }
    $script:Gui = [pscustomobject]@{
        Window = $window; Ui = $ui; Settings = $Settings; Theme = $theme; Section = $Section; IsAdmin = (Test-TuneupGuiAdmin)
        Jobs = (New-Object System.Collections.Generic.List[object]); Changing = $null; Loaded = (New-Object System.Collections.Generic.HashSet[string])
        Pending = $null; DialogAction = $null; DialogReturnFocus = $null; Navigating = $false; Initializing = $true; CloseConfirmed = $false; Reopen = $null; LastStatus = $false
        StatusDoc = $null; PlanDoc = $null; PlanGroups = $null; PlanTab = $null; StatusTab = $null; StartupDoc = $null; StartupRows = @(); StartupTab = $null
        CleanDoc = $null; CleanRows = @(); LogTab = $null; UndoRun = $null; UndoRetry = $null; Suggested = @(); PlanAfterList = $false
    }
    Set-GuiText -Root $window
    $versionFile = Join-Path $script:GuiRoot 'engine\Version.ps1'
    $ui.VersionText.Text = $(if ([System.IO.File]::ReadAllText($versionFile) -match "TuneupVersion\s*=\s*'([^']+)'") { $Matches[1] } else { '' })
    $ui.EnvText.Text = Get-GuiEnvironmentText
    $adminKeys = $(if ($script:Gui.IsAdmin) { @('SuccessBg', 'SuccessFg', 'gui.header.admin') } else { @('CautionBg', 'CautionFg', 'gui.header.notAdmin') })
    $ui.AdminChip.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $adminKeys[0])
    $ui.AdminText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $adminKeys[1])
    $ui.AdminText.Text = Get-TuneupGuiText -Key $adminKeys[2]
    $ui.RelaunchAdminButton.Visibility = $(if ($script:Gui.IsAdmin) { 'Collapsed' } else { 'Visible' })
    $ui.LanguageBox.SelectedIndex = $(if ((Get-TuneupGuiLang) -eq 'es') { 0 } else { 1 })
    $ui.ThemeBox.SelectedIndex = @('system', 'light', 'dark').IndexOf([string]$Settings.theme)
    if ($theme -eq 'highcontrast') {
        # Windows decides the colors: the choice stays saved for when high contrast is off.
        $ui.ThemeBox.IsEnabled = $false
        $ui.ThemeHighContrastNote.Visibility = 'Visible'
    }
    $ui.StatusText.Text = Get-TuneupGuiText -Key 'gui.status.ready'
    Register-GuiEvent
    Set-TuneupGuiLogListener -Listener { param($entry) if ($null -ne $entry -and $null -ne $script:Gui -and $script:Gui.Section -eq 'Log') { Update-GuiSectionLog } }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Add_Tick({ Invoke-GuiTick })
    $timer.Start()
    $script:Gui.Initializing = $false
    $window.Add_ContentRendered({ Show-GuiSection -Name $script:Gui.Section })
    [void]$window.ShowDialog()
    $timer.Stop()
    Set-TuneupGuiLogListener -Listener $null
    $script:Gui.Reopen
}
