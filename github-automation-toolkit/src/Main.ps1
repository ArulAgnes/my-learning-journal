#Requires -Version 5.1
<#
.SYNOPSIS
    Main.ps1 - entry point for the GitHub Automation & Learning Lab.
.DESCRIPTION
    Dot-sources the toolkit modules, runs the automatic startup sequence
    (environment, tools, authentication, account verification, repositories,
    learning repo) and shows the main dashboard loop.
#>

$ErrorActionPreference = 'Stop'
$script:ToolkitRoot = Split-Path -Parent $PSScriptRoot
Set-Location $script:ToolkitRoot

foreach ($module in @('Common.ps1', 'Authentication.ps1', 'RepositoryManager.ps1', 'CommitManager.ps1', 'PullRequestManager.ps1', 'IssueManager.ps1', 'AchievementTracker.ps1', 'ReportGenerator.ps1')) {
    $modulePath = Join-Path $PSScriptRoot $module
    if (-not (Test-Path $modulePath)) {
        Write-Host "[X] Missing module: $modulePath" -ForegroundColor Red
        Write-Host '    Re-extract the toolkit ZIP so src\ is complete.' -ForegroundColor Yellow
        exit 1
    }
    . $modulePath
}

Initialize-ToolkitData

$context = Invoke-StartupSequence
if ($null -eq $context) {
    Write-Host ''
    Write-Host '  [X] Startup did not complete. Fix the items above and run the toolkit again.' -ForegroundColor Red
    exit 1
}

function Show-MainMenu {
    param($Context)
    Clear-Host
    $dryBadge = ''
    if ($Context.DryRun) { $dryBadge = '  [DRY-RUN MODE - nothing will be changed]' }
    Write-Host ''
    Write-Host '==============================================' -ForegroundColor DarkCyan
    Write-Host '   GITHUB AUTOMATION & LEARNING LAB' -ForegroundColor White
    Write-Host '==============================================' -ForegroundColor DarkCyan
    Write-Host "ACCOUNT: $($Context.User.Login)$dryBadge" -ForegroundColor Cyan
    Write-Host 'AUTHENTICATION: CONNECTED' -ForegroundColor Green
    Write-Host ''
    Write-Host '[1] Achievement Dashboard'
    Write-Host '[2] Pull Request Automation Lab'
    Write-Host '[3] Commit & Repository Learning Lab'
    Write-Host '[4] Issue Automation Lab'
    Write-Host '[5] Repository Manager'
    Write-Host '[6] Achievement Eligibility Guide'
    Write-Host '[7] Activity History'
    Write-Host '[8] Generate HTML Progress Report'
    Write-Host '[9] Open GitHub Profile'
    Write-Host '[10] Open GitHub Achievements'
    Write-Host '[D] Toggle dry-run mode'
    Write-Host '[0] Exit'
    Write-Host '==============================================' -ForegroundColor DarkCyan
}

function Show-CommitLearningLab {
    param($Context)
    while ($true) {
        Clear-Host
        Write-Banner 'COMMIT & REPOSITORY LEARNING LAB'
        Write-UI '  [1] Interactive Conventional Commit helper' -Color 'White'
        Write-UI '  [2] Create a feature branch' -Color 'White'
        Write-UI '  [3] Show git status and remotes of a local repo' -Color 'White'
        Write-UI '  [4] Push current branch (never force-push)' -Color 'White'
        Write-UI '  [5] Open the learning roadmap in this repo' -Color 'White'
        Write-UI '  [0] Back' -Color 'Gray'
        Write-Divider
        $choice = Read-MenuChoice -Prompt 'Choice' -ValidChoices 0, 1, 2, 3, 4, 5
        $default = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'github-learning-lab'
        if ($choice -eq 0) { return }
        $path = Read-Host "  Local repository path [$default]"
        if ([string]::IsNullOrWhiteSpace($path)) { $path = $default }
        switch ($choice) {
            1 {
                if (Test-GitRepository -RepoPath $path) { $null = New-ConventionalCommit -RepoPath $path } else { Write-Fail 'Not a git repository.' }
            }
            2 {
                if (-not (Test-GitRepository -RepoPath $path)) { Write-Fail 'Not a git repository.' }
                else {
                    $name = Read-Host '  New branch name (e.g. lab/my-first-branch)'
                    if (Test-BranchNameValid -Name $name) { $null = New-FeatureBranch -RepoPath $path -BranchName $name }
                    else { Write-Fail 'Invalid branch name.' }
                }
            }
            3 {
                if (-not (Test-GitRepository -RepoPath $path)) { Write-Fail 'Not a git repository.' }
                else {
                    Write-Info "Branch:  $(Get-CurrentBranch -RepoPath $path)"
                    Write-Info "Remote:  $(Get-RemoteUrl -RepoPath $path)"
                    $status = @(Get-GitStatusPorcelain -RepoPath $path)
                    if ($status.Count -eq 0) { Write-Success 'Working tree clean.' }
                    else { Write-Warn "$($status.Count) changed/untracked path(s):"; foreach ($l in $status) { Write-UI "        $l" -Color 'Gray' } }
                }
            }
            4 { if (Test-GitRepository -RepoPath $path) { $null = Push-CurrentBranch -RepoPath $path } else { Write-Fail 'Not a git repository.' } }
            5 {
                Write-UI ''
                Write-UI '  Learning roadmap:' -Color 'White'
                Write-UI '    1. tutorials/01-git-basics.md        - status/add/commit/log' -Color 'Gray'
                Write-UI '    2. tutorials/02-branching-and-merge.md - branches & conflict handling' -Color 'Gray'
                Write-UI '    3. tutorials/03-github-cli.md        - gh auth, issues, PRs' -Color 'Gray'
                Write-UI '    4. tutorials/04-batch-scripts.md     - .bat mechanics & CRLF' -Color 'Gray'
                Write-UI '    5. tutorials/05-powershell-automation.md - PS 5.1/7 compatible scripts' -Color 'Gray'
                Write-UI '  Seed them from menu option [5] -> Repository Manager -> Seed learning content.' -Color 'DarkGray'
            }
        }
        Read-Host '  Press Enter to continue'
    }
}

function Show-ActivityHistory {
    Clear-Host
    Write-Banner 'ACTIVITY HISTORY'
    $entries = @(Get-ActivityLog)
    if ($entries.Count -eq 0) {
        Write-Info 'No recorded activity yet. Everything you do with the toolkit is logged here.'
        Read-Host '  Press Enter to continue'
        return
    }
    Write-Info "$($entries.Count) log entries (showing the 30 most recent):"
    Write-UI ''
    foreach ($e in @($entries | Sort-Object { $_.timestamp } -Descending | Select-Object -First 30)) {
        $result = [string]$e.result
        $color = 'Gray'
        if ($result -eq 'SUCCESS') { $color = 'Green' }
        elseif ($result -eq 'FAILED') { $color = 'Red' }
        elseif ($result -eq 'WAITING' -or $result -eq 'PREVIEW') { $color = 'Yellow' }
        Write-UI ("  {0}  [{1,-7}] {2,-28} {3}" -f (Format-IsoTimestamp $e.timestamp), $result, $e.action, $e.detail) -Color $color
    }
    Write-UI ''
    Write-Info "Full log: $(Join-Path $script:ToolkitRoot 'data\activity-log.json')"
    Read-Host '  Press Enter to continue'
}

function Invoke-DryRunToggle {
    param($Context)
    try {
        $settings = Get-ToolkitSettings
        $settings.dryRun = -not [bool]$settings.dryRun
        Save-ToolkitSettings -Settings $settings
        $Context.DryRun = [bool]$settings.dryRun
        if ($Context.DryRun) { Write-Warn 'DRY-RUN enabled. No GitHub or git operations will change anything.' }
        else { Write-Success 'DRY-RUN disabled. Real operations are armed; confirmations still protect you.' }
    } catch {
        Write-Fail "Could not toggle dry-run: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 1
}

while ($true) {
    Show-MainMenu -Context $context
    $raw = Read-Host '  Choose an option'
    switch ($raw.Trim().ToUpperInvariant()) {
        '1' { Show-AchievementDashboard -Context $context }
        '2' { Invoke-PullRequestLab -Context $context ; Read-Host '  Press Enter to continue' }
        '3' { Show-CommitLearningLab -Context $context }
        '4' { Invoke-QuickdrawLab -Context $context ; Read-Host '  Press Enter to continue' }
        '5' { Show-RepositoryManagerMenu -Context $context }
        '6' { Clear-Host; Show-AchievementReference; Read-Host '  Press Enter to continue' }
        '7' { Show-ActivityHistory }
        '8' { Invoke-ReportGenerator -Context $context }
        '9' { Open-WebPage "https://github.com/$($context.User.Login)" | Out-Null }
        '10' { Open-WebPage "https://github.com/$($context.User.Login)?tab=achievements" | Out-Null }
        'D' { Invoke-DryRunToggle -Context $context }
        '0' {
            Clear-Host
            Write-Banner 'GOODBYE'
            Write-Success 'Progress is built one genuine commit at a time. See you in the lab!'
            Add-ActivityEntry -Action 'Toolkit exited' -Category 'General' -Result 'SUCCESS'
            exit 0
        }
        default { Write-Warn 'Choose a number from the menu (or D / 0).' }
    }
}
