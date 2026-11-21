#Requires -Version 5.1
<#
.SYNOPSIS
    IssueManager.ps1 - the Quickdraw learning workflow.
.DESCRIPTION
    Demonstrates the genuine lifecycle of an issue: create -> inspect ->
    resolve -> close. Quickdraw (community-reported) rewards closing an
    issue within 5 minutes of opening it. The lab never mass-creates
    issues and refuses low-quality titles.
#>

function Get-QuickdrawEligibleEvents {
    <#
    .SYNOPSIS
        Finds recently created+closed issues authored by the user that were
        closed within the eligibility window. Pure read-only via search API.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Username,
        [int]$WindowMinutes = 5,
        [int]$Limit = 50
    )
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @(
        'api', '--method', 'GET', 'search/issues',
        '-f', "q=type:issue author:$Username is:closed",
        '-f', "per_page=$Limit"
    )
    if (-not $res.Success) { return [pscustomobject]@{ Ok = $false; Hits = @() } }
    try {
        $json = ($res.Output -join "`n") | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{ Ok = $false; Hits = @() }
    }
    $fast = @()
    foreach ($item in @($json.items)) {
        try {
            $created = [datetime]$item.created_at
            $closed  = [datetime]$item.closed_at
            $minutes = ($closed - $created).TotalMinutes
            if ($minutes -ge 0 -and $minutes -le $WindowMinutes) {
                $fast += [pscustomobject]@{
                    Number   = [int]$item.number
                    Title    = [string]$item.title
                    Url      = [string]$item.html_url
                    Minutes  = [math]::Round($minutes, 2)
                    ClosedAt = $item.closed_at
                }
            }
        } catch { }
    }
    return [pscustomobject]@{ Ok = $true; Hits = @($fast) }
}

function Test-IssueTitleQuality {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [int]$MinimumLength = 12
    )
    $t = $Title.Trim()
    if ($t.Length -lt $MinimumLength) { return [pscustomobject]@{ Ok = $false; Reason = "Title is shorter than $MinimumLength characters." } }
    if ($t -notmatch '[a-zA-Z]{4,}') { return [pscustomobject]@{ Ok = $false; Reason = 'Title needs real words, not symbols.' } }
    if ($t -match '^(test|testing|asdf|foo|bar|todo|xxx|\.+)$') { return [pscustomobject]@{ Ok = $false; Reason = "'$t' is a placeholder, not a real issue." } }
    if ($t -cmatch '^[A-Z ]+$') { return [pscustomobject]@{ Ok = $false; Reason = 'Write a specific sentence, not SHOUTING.' } }
    return [pscustomobject]@{ Ok = $true; Reason = '' }
}

function Invoke-QuickdrawLab {
    param($Context)

    Write-Banner 'QUICKDRAW LAB - genuine issue triage'
    $settings = Get-ToolkitSettings
    $window = 5
    $maxIssues = 1
    try { $window = [int]$settings.issueLab.quickdrawWindowMinutes } catch { }
    try { $maxIssues = [int]$settings.issueLab.maxIssuesPerRun } catch { }

    Write-Info 'Quickdraw (community-reported): GitHub grants it when an issue you opened'
    Write-Info "is closed within $window minutes of creation. It rewards fast, legitimate triage"
    Write-Info 'of your own tracker - for example, spotting a duplicate or an already-fixed bug.'
    Write-UI ''
    Write-Warn 'This lab creates AT MOST one issue per run, and only issues that a real'
    Write-Warn 'repository would want. It never farms empty issues.'
    Write-UI ''

    $default = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'github-learning-lab'
    $repo = Read-Host "  Repository to work in (owner/name) [ArulAgnes/github-learning-lab]"
    if ([string]::IsNullOrWhiteSpace($repo)) { $repo = 'ArulAgnes/github-learning-lab' }
    if ($repo -notmatch '^[^/\s]+/[^/\s]+$') { Write-Fail 'Use the form owner/name.'; return }

    $perm = Test-RepositoryPermissions -FullName $repo
    if ($null -ne $perm -and $perm -notin @('Admin', 'Maintain', 'Write')) {
        Write-Fail "You have '$perm' permission on $repo. You need Write or better to close issues."
        return
    }

    Write-Banner 'STEP 1 - Pick a genuine reason for an issue'
    Write-UI '  Good candidates:' -Color 'White'
    Write-UI '    a) A typo or unclear sentence you just spotted in the docs' -Color 'Gray'
    Write-UI '    b) A bug you already know how to reproduce' -Color 'Gray'
    Write-UI '    c) A duplicate you now recognize' -Color 'Gray'
    Write-UI '    d) A task you completed and immediately verified (e.g. doc link fixed)' -Color 'Gray'
    Write-UI ''
    $title = Read-Host '  Issue title (specific, >= 12 chars)'
    $minLen = 12
    try { $minLen = [int]$settings.issueLab.minimumTitleLength } catch { }
    $quality = Test-IssueTitleQuality -Title $title -MinimumLength $minLen
    if (-not $quality.Ok) {
        Write-Fail "Title rejected: $($quality.Reason)"
        Write-Info 'Quality gates exist so the lab never creates junk issues.'
        return
    }
    $body = Read-Host '  Issue body (what/why, one or two sentences)'
    if ([string]::IsNullOrWhiteSpace($body) -or $body.Trim().Length -lt 20) {
        Write-Fail 'Body too short. Add a genuine description (>= 20 characters).'
        return
    }

    if (Test-DryRun) {
        Write-Info '[DRY-RUN] Would run: gh issue create --repo <repo> --title ... --body ...'
        return
    }

    Write-Banner 'STEP 2 - Create the issue'
    $created = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('issue', 'create', '--repo', $repo, '--title', $title.Trim(), '--body', $body.Trim())
    foreach ($line in $created.Output) { Write-UI "        $line" -Color 'Gray' }
    if (-not $created.Success) { Write-Fail "Issue creation failed (exit $($created.ExitCode))."; return }
    $issueUrl = ($created.Output | Where-Object { $_ -match 'https?://\S+' } | Select-Object -First 1)
    $issueNumber = 0
    if ($issueUrl -match '/issues/(\d+)') { $issueNumber = [int]$Matches[1] }
    Write-Success "Issue created: $issueUrl"
    $createdAt = Get-Date

    Write-Banner 'STEP 3 - Inspect it'
    if ($issueNumber -gt 0) {
        $view = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('issue', 'view', $issueNumber.ToString(), '--repo', $repo)
        foreach ($line in $view.Output) { Write-UI "        $line" -Color 'DarkGray' }
    }

    Write-Banner 'STEP 4 - Resolve or leave open'
    Write-Info 'Only close now if the issue is GENUINELY resolved or no longer needed'
    Write-Info '(for example: you fixed it in a commit made minutes ago, or it was a duplicate).'
    Write-Info "Close within $window minutes of creation for Quickdraw eligibility."
    $elapsed = [math]::Round(((Get-Date) - $createdAt).TotalSeconds)
    Write-Info "Elapsed since creation: ${elapsed}s"

    if (Read-YesNo 'Close the issue now with a resolution comment?' $false) {
        $comment = Read-Host '  Resolution comment (what fixed or answered it)'
        if ([string]::IsNullOrWhiteSpace($comment)) { $comment = 'Resolved; closing.' }
        $closed = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('issue', 'close', $issueNumber.ToString(), '--repo', $repo, '--comment', $comment.Trim())
        if (-not $closed.Success) {
            Write-Fail "Close failed (exit $($closed.ExitCode))."
            return
        }
        $minutes = [math]::Round(((Get-Date) - $createdAt).TotalMinutes, 2)
        $within  = $minutes -le $window
        Add-ActivityEntry -Action 'Issue closed' -Category 'Quickdraw' -Repository $repo -Result 'SUCCESS' -Detail ("#{0} closed in {1} min (Quickdraw window {2} min: {3})" -f $issueNumber, $minutes, $window, $(if ($within) { 'MET' } else { 'NOT MET' })) -Url $issueUrl
        if ($within) {
            Write-Success "Closed in $minutes minutes - inside the $window-minute Quickdraw window."
            Write-Info 'Whether GitHub awards Quickdraw is entirely up to GitHub; the toolkit just tracks eligibility.'
        } else {
            Write-Warn "Closed in $minutes minutes - outside the $window-minute window. Not Quickdraw-eligible this time."
        }
    } else {
        Write-Info 'Issue left open. Close it later with: gh issue close <number> --repo <repo>'
        Add-ActivityEntry -Action 'Issue opened' -Category 'Quickdraw' -Repository $repo -Result 'SUCCESS' -Detail "#$issueNumber" -Url $issueUrl
    }
}

function Get-QuickdrawStats {
    param([string]$Username, [int]$WindowMinutes = 5)
    Write-Banner 'QUICKDRAW HISTORY'
    $result = @(Get-QuickdrawEligibleEvents -Username $Username -WindowMinutes $WindowMinutes)
    if ($null -eq $result -or -not $result.Ok) {
        Write-Warn 'Could not query the search API. Showing local log only.'
    } else {
        $fast = @($result.Hits)
        Write-Info "Issues closed within $WindowMinutes minutes of creation (search API): $($fast.Count)"
        foreach ($e in $fast) {
            Write-UI ("    #{0}  {1}  ({2} min)" -f $e.Number, $e.Title, $e.Minutes) -Color 'Gray'
            Write-UI ("         {0}" -f $e.Url) -Color 'DarkGray'
        }
    }
    $log = @(Get-ActivityLog) | Where-Object { $_.category -eq 'Quickdraw' }
    Write-Info "Quickdraw events recorded by this toolkit: $($log.Count)"
}
