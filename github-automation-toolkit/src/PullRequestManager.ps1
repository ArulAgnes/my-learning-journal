#Requires -Version 5.1
<#
.SYNOPSIS
    PullRequestManager.ps1 - the Pull Request Automation Lab and Pull Shark
    data access (merged-PR counting via the GitHub search API).
.DESCRIPTION
    Helps you inspect a repository, find a genuine improvement, implement it,
    open a pull request and - only when repository rules and checks allow -
    merge it (optionally self-merged for your own repos). Never spams, never
    bypasses branch protection, never claims a merge GitHub didn't confirm.
#>

# ---------------------------------------------------------------------------
# Read-only GitHub data (used by Pull Shark tracker and reports)
# ---------------------------------------------------------------------------
function Get-MergedPullRequestCount {
    <#
    .SYNOPSIS
        Returns the total_count of merged PRs authored by the given user via
        the GitHub search API, or $null when the API call fails.
    #>
    param([Parameter(Mandatory = $true)][string]$Username)
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @(
        'api', '--method', 'GET', 'search/issues',
        '-f', "q=type:pr is:merged author:$Username",
        '-f', 'per_page=1'
    )
    if (-not $res.Success) { return $null }
    try {
        $json = ($res.Output -join "`n") | ConvertFrom-Json
        return [int]$json.total_count
    } catch {
        return $null
    }
}

function Get-RecentMergedPulls {
    param(
        [Parameter(Mandatory = $true)][string]$Username,
        [int]$Limit = 20
    )
    $perPage = [math]::Min([math]::Max($Limit, 1), 100)
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @(
        'api', '--method', 'GET', 'search/issues',
        '-f', "q=type:pr is:merged author:$Username sort:updated-desc",
        '-f', "per_page=$perPage"
    )
    if (-not $res.Success) { return $null }
    try {
        $json = ($res.Output -join "`n") | ConvertFrom-Json
        return @($json.items)
    } catch {
        return $null
    }
}

function Get-PullRequestStatus {
    param(
        [Parameter(Mandatory = $true)][string]$FullName,
        [Parameter(Mandatory = $true)][int]$Number
    )
    return Invoke-GhJson -Arguments @(
        'pr', 'view', $Number.ToString(), '--repo', $FullName, '--json',
        'number,title,url,state,mergedAt,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,headRefName'
    )
}

function Get-RepositoryDefaultBranch {
    param([Parameter(Mandatory = $true)][string]$FullName)
    $details = Get-RepositoryDetails -FullName $FullName
    if ($null -eq $details) { return 'main' }
    if ($details.defaultBranchRef -and $details.defaultBranchRef.name) { return [string]$details.defaultBranchRef.name }
    return 'main'
}

function Convert-GitRemoteToFullName {
    <#
    .SYNOPSIS
        Parses owner/repo from common GitHub remote URL formats. Returns $null
        when the remote is not a github.com URL.
    #>
    param([Parameter(Mandatory = $true)][string]$RemoteUrl)
    $url = $RemoteUrl.Trim()
    $m = [regex]::Match($url, 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?/?$')
    if ($m.Success) { return ('{0}/{1}' -f $m.Groups[1].Value, $m.Groups[2].Value) }
    return $null
}

# ---------------------------------------------------------------------------
# Improvement detection + implementations (new files only; no destructive edits)
# ---------------------------------------------------------------------------
function New-ImprovementCandidates {
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    $candidates = @()
    $def = { param($k, $t, $d, $rel, $content)
        [pscustomobject]@{ Key = $k; Title = $t; Detail = $d; RelativePath = $rel; Content = $content }
    }

    if (-not (Test-Path (Join-Path $RepoPath 'docs\DEVELOPER_GUIDE.md'))) {
        $content = @'
# Developer Guide

## Setup

1. Install Git and the GitHub CLI (`winget install --id Git.Git -e` / `winget install --id GitHub.cli -e`).
2. Clone this repository and open it in your editor.
3. Run the demo tests: `powershell -File .\tests\Test-Calculator.ps1` (or this repo's equivalent).

## Branching model

- `main` is protected; work happens on short-lived branches: `lab/<topic>-<timestamp>`.
- One concern per branch; keep the diff focused and reviewable.
- Squash-merge after CI is green.

## Commit style

Conventional Commits: `type(scope): summary` - e.g. `docs(guide): clarify setup`.
Types: feat, fix, docs, test, refactor, chore, ci, build, perf.

## Testing before you push

- Run the repository's test entrypoint.
- Verify `git status` shows only intended files.
- Never commit secrets: .env, *.pem, *.key, tokens. The toolkit's pre-commit scan blocks these.
'@
        $candidates += & $def 'docs-developer-guide' 'Add docs/DEVELOPER_GUIDE.md' 'Setup, branching, commits and testing for new contributors' 'docs/DEVELOPER_GUIDE.md' $content
    }

    if (-not (Test-Path (Join-Path $RepoPath 'CONTRIBUTING.md'))) {
        $content = @'
# Contributing

Small, genuine improvements are welcome.

## Ground rules

1. One topic per pull request.
2. Documentation for every behavior change.
3. Tests where a test harness exists; keep diffs reviewable.
4. No secrets or credentials in any commit - ever.

## Pull request checklist

- [ ] The change is genuinely useful (docs, fix, test or example)
- [ ] Relevant docs updated
- [ ] Tests pass (if the repo has tests)
- [ ] Commit messages follow Conventional Commits
'@
        $candidates += & $def 'contributing' 'Add CONTRIBUTING.md' 'Sets contribution ground rules and a PR checklist' 'CONTRIBUTING.md' $content
    }

    if (-not (Test-Path (Join-Path $RepoPath '.editorconfig'))) {
        $content = @'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.{ps1,psd1,psm1,bat,cmd}]
indent_size = 4

[*.md]
trim_trailing_whitespace = false
'@
        $candidates += & $def 'editorconfig' 'Add .editorconfig' 'Consistent encoding and indentation across editors' '.editorconfig' $content
    }

    if (-not (Test-Path (Join-Path $RepoPath '.github\PULL_REQUEST_TEMPLATE.md'))) {
        $content = @'
## What changed

<!-- One short paragraph. -->

## Why

<!-- The problem this solves or the value it adds. -->

## How to verify

- [ ] Tests pass locally
- [ ] Docs updated if behavior changed

## Notes for the reviewer

<!-- Anything you want a second pair of eyes on. -->
'@
        $candidates += & $def 'pr-template' 'Add .github/PULL_REQUEST_TEMPLATE.md' 'Gives every future PR a consistent, review-friendly structure' '.github/PULL_REQUEST_TEMPLATE.md' $content
    }

    if (-not (Test-Path (Join-Path $RepoPath '.github\ISSUE_TEMPLATE\bug_report.md'))) {
        $content = @'
---
name: Bug report
about: Report a reproducible problem
title: ""
labels: bug
---

**What happened?**

**What did you expect to happen?**

**Steps to reproduce**

1.
2.
3.

**Environment**

- OS:
- Version / commit:
'@
        $candidates += & $def 'issue-template' 'Add .github/ISSUE_TEMPLATE/bug_report.md' 'Structured bug reports; less back-and-forth in triage' '.github/ISSUE_TEMPLATE/bug_report.md' $content
    }

    return $candidates
}

function Show-ImprovementPreview {
    param([Parameter(Mandatory = $true)]$Candidate)
    Write-Banner 'PREVIEW MODE'
    Write-Info "Candidate:  $($Candidate.Title)"
    Write-Info "Why:        $($Candidate.Detail)"
    Write-Info "New file:   $($Candidate.RelativePath)"
    Write-UI ''
    Write-UI '  --- content preview (first 40 lines) ---' -Color 'DarkGray'
    $lines = $Candidate.Content -split "`n"
    $shown = 0
    foreach ($line in $lines) {
        if ($shown -ge 40) { Write-UI '  ... (truncated)' -Color 'DarkGray'; break }
        Write-UI ("  | " + $line) -Color 'Gray'
        $shown++
    }
    Write-UI '  ---------------------------------------' -Color 'DarkGray'
}

function Apply-Improvement {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)]$Candidate
    )
    $target = Join-Path $RepoPath $Candidate.RelativePath
    $written = Write-FileSafe -Path $target -Content $Candidate.Content
    return $written
}

function Test-PullRequestChecks {
    <#
    .SYNOPSIS
        Returns an object describing the check/merge state: Ok, Pending or Blocked.
    #>
    param(
        [Parameter(Mandatory = $true)]$Status
    )
    $result = [pscustomobject]@{
        Ok       = $false
        Pending  = $false
        Reason   = ''
        Failures = @()
    }
    if ($null -eq $Status) { $result.Reason = 'Status unavailable'; return $result }

    $mergeState = [string]$Status.mergeStateStatus
    $failing = @()
    $pending = @()
    if ($Status.statusCheckRollup) {
        foreach ($check in @($Status.statusCheckRollup)) {
            $conclusion = [string]$check.conclusion
            $state      = [string]$check.status
            $name       = [string]$check.name
            if (-not $name) { $name = [string]$check.context }
            if ($conclusion -in @('FAILURE', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED', 'STARTUP_FAILURE')) { $failing += $name; continue }
            if ($state -in @('FAILURE', 'ERROR')) { $failing += $name; continue }
            if (-not $conclusion -and $state -in @('QUEUED', 'IN_PROGRESS', 'PENDING', 'WAITING', 'REQUESTED', 'EXPECTED')) { $pending += $name; continue }
            # SUCCESS / NEUTRAL / SKIPPED / COMPLETED with no conclusion are not blocking
        }
    }

    if ($failing.Count -gt 0) {
        $result.Reason   = 'Failing checks: ' + ($failing -join ', ')
        $result.Failures = $failing
        return $result
    }
    if ($pending.Count -gt 0) {
        $result.Pending = $true
        $result.Reason  = 'Checks still running: ' + ($pending -join ', ')
        return $result
    }
    switch ($mergeState) {
        'CLEAN'    { $result.Ok = $true;  $result.Reason = 'Merging is allowed by repository rules' }
        'UNSTABLE' { $result.Ok = $true;  $result.Reason = 'No required checks block merging (unstable non-required checks)'; }
        'HAS_HOOKS'{ $result.Ok = $true;  $result.Reason = 'Mergeable (status hooks present)' }
        'BLOCKED'  { $result.Reason = 'Blocked by repository protection rules (review or required checks missing)' }
        'BEHIND'   { $result.Reason = 'Branch is behind the base branch; update it first' }
        'DIRTY'    { $result.Reason = 'Merge conflicts with the base branch' }
        'DRAFT'    { $result.Reason = 'Pull request is a draft' }
        'UNKNOWN'  { $result.Reason = 'GitHub has not computed mergeability yet; retry in a few seconds' }
        default    { $result.Reason = "mergeStateStatus=$mergeState" }
    }
    return $result
}

function Invoke-PullRequestLab {
    <#
    .SYNOPSIS
        Guided, safety-first PR workflow. One genuine improvement per run;
        stops at the configured per-run limit.
    #>
    param($Context)

    Write-Banner 'PULL REQUEST AUTOMATION LAB'
    $settings = Get-ToolkitSettings
    $maxPerRun  = 3
    $mergeMethod = 'squash'
    $selfMerge   = $true
    $branchPrefix = 'lab/'
    try { $maxPerRun   = [int]$settings.pullRequestLab.maxPullRequestsPerRun } catch { }
    try { $mergeMethod  = [string]$settings.pullRequestLab.defaultMergeMethod } catch { }
    try { $selfMerge    = [bool]$settings.pullRequestLab.selfMergeAllowed } catch { }
    try { $branchPrefix = [string]$settings.pullRequestLab.branchPrefix } catch { }
    if ($mergeMethod -notin @('merge', 'squash', 'rebase')) { $mergeMethod = 'squash' }

    Write-Info "Per-run limit: $maxPerRun PR(s)   Preview mode: $($settings.previewMode)   Self-merge: $selfMerge"
    Write-Info 'This lab makes ONE genuine improvement per iteration - no spam, ever.'
    Write-UI ''

    $default = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'github-learning-lab'
    $path = Read-Host "  Local path of the target repository [$default]"
    if ([string]::IsNullOrWhiteSpace($path)) { $path = $default }
    if (-not (Test-Path $path)) { Write-Fail 'Path not found. Clone it first: gh repo clone <owner>/<repo> "<path>"'; return }
    if (-not (Test-GitRepository -RepoPath $path)) { Write-Fail 'That path is not a git repository.'; return }

    $remote = Get-RemoteUrl -RepoPath $path
    if (-not $remote) { Write-Fail 'No origin remote configured. Add one: git remote add origin <url>'; return }
    $fullName = Convert-GitRemoteToFullName -RemoteUrl $remote
    if (-not $fullName) { Write-Fail "origin ($remote) is not a github.com repository URL."; return }
    Write-Success "Target repository: $fullName"

    $created = 0
    while ($true) {
        if ($created -ge $maxPerRun) {
            Write-Warn "Per-run limit ($maxPerRun) reached. Run the lab again for more."
            break
        }

        $statusLines = Get-GitStatusPorcelain -RepoPath $path
        if ($null -ne $statusLines -and @($statusLines).Count -gt 0) {
            Write-Fail 'Working tree is not clean. Commit or stash your changes before running the lab.'
            foreach ($l in @($statusLines)) { Write-UI "        $l" -Color 'DarkRed' }
            break
        }

        $candidates = @(New-ImprovementCandidates -RepoPath $path)
        if ($candidates.Count -eq 0) {
            Write-Success 'No obvious missing-file improvements detected. The lab does not invent busywork.'
            Write-Info 'Suggestion: work on a real feature or doc fix yourself - the toolkit can commit and PR it via menu [3].'
            break
        }

        Write-Banner 'IMPROVEMENT OPPORTUNITIES'
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            Write-UI ("  [{0}] {1} - {2}" -f ($i + 1), $candidates[$i].Title, $candidates[$i].Detail) -Color 'White'
        }
        Write-UI '  [0] Exit the lab' -Color 'Gray'
        $pick = Read-MenuChoice -Prompt 'Pick an improvement' -ValidChoices (0..$candidates.Count)
        if ($pick -eq 0) { break }
        $candidate = $candidates[$pick - 1]

        $preview = $false
        try { $preview = [bool]$settings.previewMode } catch { }
        if (Read-YesNo 'Run in PREVIEW mode (show changes, touch nothing)?' $preview) {
            Show-ImprovementPreview -Candidate $candidate
            Add-ActivityEntry -Action 'PR lab preview' -Category 'PullRequest' -Repository $fullName -Result 'PREVIEW' -Detail $candidate.Key
            break
        }

        $defaultBranch = Get-RepositoryDefaultBranch -FullName $fullName
        $branch = '{0}{1}-{2}' -f $branchPrefix, $candidate.Key, (Get-Date -Format 'yyyyMMddHHmm')

        Write-Step "Creating branch $branch from $defaultBranch..."
        if (-not (Switch-BackToDefaultBranch -RepoPath $path -DefaultBranch $defaultBranch)) { break }
        $null = Update-DefaultBranch -RepoPath $path -DefaultBranch $defaultBranch
        if (-not (New-FeatureBranch -RepoPath $path -BranchName $branch)) { break }

        $written = Apply-Improvement -RepoPath $path -Candidate $candidate
        if (-not $written) { Write-Fail 'Could not write the improvement file.'; break }

        $commitMsg = 'docs: add {0}' -f $candidate.RelativePath
        if ($candidate.Key -eq 'editorconfig') { $commitMsg = 'chore: add .editorconfig for consistent formatting' }
        elseif ($candidate.Key -eq 'pr-template') { $commitMsg = 'chore: add GitHub pull request template' }
        elseif ($candidate.Key -eq 'issue-template') { $commitMsg = 'chore: add GitHub bug report issue template' }

        if (-not (New-GitCommit -RepoPath $path -Files @($written) -Message $commitMsg)) { break }
        if (-not (Push-CurrentBranch -RepoPath $path)) { break }

        Write-Step 'Opening pull request...'
        $prBody = "## What changed`n`nAdds `$($candidate.RelativePath)` - $($candidate.Detail).`n`n## Why`n`n$($candidate.Title).`n`n## How to verify`n`n- [ ] Review the new file`n- [ ] CI (if configured) is green`n"
        $prArgs = @('pr', 'create', '--repo', $fullName, '--title', $commitMsg, '--body', $prBody, '--head', $branch)
        if (Test-DryRun) {
            Write-Info "[DRY-RUN] Would run: gh $($prArgs -join ' ')"
            $created++
            break
        }
        $prRes = Invoke-ExternalCaptured -FilePath 'gh' -Arguments $prArgs
        foreach ($line in $prRes.Output) { Write-UI "        $line" -Color 'Gray' }
        if (-not $prRes.Success) {
            Write-Fail "Pull request creation failed (exit $($prRes.ExitCode))."
            Add-ActivityEntry -Action 'PR create' -Category 'PullRequest' -Repository $fullName -Result 'FAILED' -Detail $candidate.Key
            break
        }
        $prUrl = ($prRes.Output | Where-Object { $_ -match 'https?://\S+' } | Select-Object -First 1)
        Write-Success "Pull request opened: $prUrl"
        Add-ActivityEntry -Action 'PR opened' -Category 'PullRequest' -Repository $fullName -Result 'SUCCESS' -Detail $candidate.Key -Url $prUrl

        $prNumber = 0
        if ($prUrl -match '/pull/(\d+)') { $prNumber = [int]$Matches[1] }

        if ($prNumber -gt 0) {
            Start-Sleep -Seconds 3
            $st = Get-PullRequestStatus -FullName $fullName -Number $prNumber
            $eval = Test-PullRequestChecks -Status $st
            Write-Info "PR status: $($eval.Reason)"

            if ($selfMerge) {
                $canMerge = $eval.Ok
                if (-not $canMerge) { Write-Warn 'Not merging: repository rules or checks do not permit it right now.' }
                elseif (-not (Read-YesNo 'Repository permits merging. Self-merge this PR now?' $false)) { $canMerge = $false; Write-Info 'Left open for review.' }
                if ($canMerge) {
                    $mergeRes = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('pr', 'merge', $prNumber.ToString(), '--repo', $fullName, "--$mergeMethod")
                    if (-not $mergeRes.Success) {
                        foreach ($line in $mergeRes.Output) { Write-UI "        $line" -Color 'DarkRed' }
                        Write-Fail 'Merge was refused by GitHub (protections stay enforced; the toolkit does not bypass them).'
                        Add-ActivityEntry -Action 'PR merge' -Category 'PullRequest' -Repository $fullName -Result 'FAILED' -Detail "#$prNumber" -Url $prUrl
                    } else {
                        foreach ($line in $mergeRes.Output) { Write-UI "        $line" -Color 'Gray' }
                        # Verify - never claim a merge GitHub did not confirm
                        Start-Sleep -Seconds 2
                        $verify = Get-PullRequestStatus -FullName $fullName -Number $prNumber
                        if ($verify -and [string]$verify.state -eq 'MERGED') {
                            Write-Success "GitHub CONFIRMED merge of #$prNumber at $($verify.mergedAt)."
                            Add-ActivityEntry -Action 'PR merged' -Category 'PullRequest' -Repository $fullName -Result 'SUCCESS' -Detail "#$prNumber ($mergeMethod)" -Url $prUrl
                        } else {
                            Write-Warn "GitHub did not confirm the merge yet. Verify manually: $prUrl"
                            Add-ActivityEntry -Action 'PR merge' -Category 'PullRequest' -Repository $fullName -Result 'WAITING' -Detail "#$prNumber merge unconfirmed" -Url $prUrl
                        }
                    }
                }
            } else {
                Write-Info 'Self-merge disabled in settings. Leave the PR open for human review.'
            }
        }

        $created++
        if (-not (Read-YesNo 'Make another genuine improvement this run?' $false)) { break }
    }
}
