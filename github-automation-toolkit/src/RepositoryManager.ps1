#Requires -Version 5.1
<#
.SYNOPSIS
    RepositoryManager.ps1 - read repositories, verify permissions, and
    prepare the dedicated learning repository with genuine content.
.DESCRIPTION
    Used during startup and from dashboard menu option [5]. Creating or
    seeding repositories is always gated by confirmation and honours
    dry-run. Never deletes anything; overwrites are backed up first.
#>

function Get-MyRepositories {
    <#
    .SYNOPSIS
        Lists repositories owned by the authenticated user (up to 200).
        Returns an array of repo info objects, or $null on API failure.
    #>
    $data = Invoke-GhJson -Arguments @(
        'repo', 'list', '--limit', '200', '--json',
        'name,description,visibility,isPrivate,isFork,url,pushedAt,stargazerCount,primaryLanguage,hasIssuesEnabled'
    )
    if ($null -eq $data) { return $null }
    return @($data)
}

function Get-RepositoryDetails {
    param([Parameter(Mandatory = $true)][string]$FullName)
    $data = Invoke-GhJson -Arguments @(
        'repo', 'view', $FullName, '--json',
        'name,description,visibility,url,createdAt,pushedAt,stargazerCount,forkCount,isFork,viewerPermission,defaultBranchRef,primaryLanguage,hasIssuesEnabled'
    )
    return $data
}

function Test-RepositoryPermissions {
    param([Parameter(Mandatory = $true)][string]$FullName)
    $details = Get-RepositoryDetails -FullName $FullName
    if ($null -eq $details) { return $null }
    return [string]$details.viewerPermission
}

function Test-GitHubConnectivity {
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('api', 'rate_limit')
    return $res.Success
}

function Get-LearningRepoSettings {
    try { return (Get-ToolkitSettings).learningRepository } catch { return $null }
}

function Test-RepositoryExists {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('api', "repos/$Owner/$Name", '--silent')
    return $res.Success
}

function New-LearningRepository {
    <#
    .SYNOPSIS
        Creates the dedicated learning repository when missing (with confirmation).
        Returns the full repository name, or $null when not created/available.
    #>
    param([Parameter(Mandatory = $true)][string]$Owner)

    $cfg = Get-LearningRepoSettings
    if ($null -eq $cfg) { Write-Fail 'learningRepository section missing from settings.json'; return $null }
    $name = [string]$cfg.name
    $full = "$Owner/$name"

    Write-Banner 'LEARNING REPOSITORY'
    if (Test-RepositoryExists -Owner $Owner -Name $name) {
        Write-Success "Learning repository already exists: $full"
        return $full
    }

    Write-Warn "The dedicated learning repository '$full' does not exist yet."
    Write-Info 'A dedicated PUBLIC repo is recommended: PRs and stars only count for'
    Write-Info 'achievements when the work is visible on github.com.'
    if (-not (Read-YesNo "Create '$full' now?" $true)) {
        Write-Warn 'Skipping creation. You can create it later from menu [5].'
        return $null
    }
    if (Test-DryRun) {
        Write-Info "[DRY-RUN] Would run: gh repo create $full --public --description `"$($cfg.description)`""
        return $null
    }
    $visibility = '--public'
    if ([string]$cfg.visibility -eq 'private') { $visibility = '--private' }

    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @(
        'repo', 'create', $full, $visibility,
        '--description', [string]$cfg.description
    )
    foreach ($line in $res.Output) { Write-UI "        $line" -Color 'DarkGray' }
    if (-not $res.Success) {
        Write-Fail "Repository creation failed (exit $($res.ExitCode))."
        return $null
    }
    Add-ActivityEntry -Action 'Learning repository created' -Category 'Repository' -Repository $full -Result 'SUCCESS'
    return $full
}

# ---------------------------------------------------------------------------
# Genuine educational content for the learning repository
# ---------------------------------------------------------------------------
$script:LearningFiles = @{}

function Register-LearningFile {
    param([string]$RelativePath, [string]$Content)
    $script:LearningFiles[$RelativePath] = $Content
}

Register-LearningFile 'README.md' @'
# GitHub Learning Lab

A hands-on repository for learning Git, GitHub, the GitHub CLI, PowerShell and
BAT automation - built together with the GitHub Automation & Learning Lab toolkit.

## What is inside

- `tutorials/` - short, practical lessons (read them in order)
- `examples/`  - small working demonstration scripts
- `docs/`      - troubleshooting and reference material
- `tests/`     - a tiny dependency-free test harness demo

## Golden rules

1. Commit small, meaningful changes with clear messages.
2. Open pull requests that improve the project in a real way.
3. Never fake stars, merges, reviews or collaborations.
4. Back up before overwriting: `git reflog` and `.backups/` are your friends.

## Suggested first steps

```powershell
git clone <this-repo-url>
cd github-learning-lab
code .
```

Then read `tutorials/01-git-basics.md`.
'@

Register-LearningFile 'tutorials/01-git-basics.md' @'
# 01 - Git Basics

Git is a distributed version control system. Every clone is a full repository
with complete history.

## The everyday loop

```bash
git status                 # what changed?
git add README.md          # stage a specific file (never blindly `git add .`)
git commit -m "docs: clarify install steps"
git log --oneline -5       # recent history
```

## The three areas

- **Working tree** - the files you edit on disk.
- **Index (staging area)** - what will go into the next commit.
- **HEAD** - the commit you are currently on.

## Undoing mistakes (safely)

| Situation                     | Safe command                        |
|-------------------------------|-------------------------------------|
| Unstage a file                | `git restore --staged <file>`       |
| Discard unstaged edits        | `git restore <file>` (destroys edits, be sure!) |
| Fix the last commit message   | `git commit --amend` (only before pushing)      |
| Find a "lost" commit          | `git reflog`                        |

## Commit message style

Use Conventional Commits: `type(scope): summary`

- `feat(lab): add batch tutorial`
- `fix(examples): correct path quoting`
- `docs: update troubleshooting`

Types: feat, fix, docs, test, refactor, chore, ci, build, perf.
'@

Register-LearningFile 'tutorials/02-branching-and-merge.md' @'
# 02 - Branching and Merging

Branches are cheap pointers to commits. Use one branch per change.

```bash
git switch -c docs/add-troubleshooting   # create + switch
# ... make changes ...
git add .
git commit -m "docs: add troubleshooting guide"
git push -u origin docs/add-troubleshooting
```

## Merge strategies

- **Merge commit** (`git merge --no-ff`) - keeps full branch topology.
- **Squash** (GitHub "Squash and merge") - one clean commit on main.
- **Rebase** (`git rebase main`) - linear history; never rebase shared branches.

## Handling conflicts

When Git reports a conflict it writes markers into the file:

```
<<<<<<< HEAD
your version
=======
their version
>>>>>>> branch-name
```

1. Open the file, choose the correct content, delete the markers.
2. `git add <file>`
3. Either `git commit` (merge) or `git rebase --continue`.

The toolkit never auto-resolves conflicts; it stops and explains instead.

## Why Pull Shark counts MERGED PRs

GitHub awards Pull Shark when pull requests you opened are merged.
Unmerged or closed-without-merge PRs do not progress the tier counter.
'@

Register-LearningFile 'tutorials/03-github-cli.md' @'
# 03 - GitHub CLI (gh)

`gh` brings GitHub to the terminal. Install: `winget install --id GitHub.cli`.

## Sign in (browser, never a password prompt)

```bash
gh auth login --web -h github.com -p https
gh auth status
gh api user
```

## Everyday commands

```bash
gh repo list --limit 20
gh repo view OWNER/REPO --json stargazerCount,url
gh issue create --title "docs: clarify setup" --body "Steps are unclear for..."
gh issue close 42 --comment "Fixed in #43"
gh pr create --title "docs: add guide" --body "Adds docs/GUIDE.md"
gh pr checks 43
gh pr merge 43 --squash
```

## Searching with the API

```bash
gh api "search/issues?q=type:pr+is:merged+author:@me"
```

`@me` is expanded by `gh`. The `total_count` field is what the toolkit uses
for the Pull Shark tracker.

## Never do this

- Never paste a token into a file, chat, or screenshot.
- Never run `gh auth token | <something>` into an untrusted program.
- Never bypass branch protection with `--admin` unless the repo admin
  explicitly asks you to.
'@

Register-LearningFile 'tutorials/04-batch-scripts.md' @'
# 04 - Batch (.bat) Scripting

Batch files are the double-click launchers of Windows. Key rules:

```bat
@echo off
setlocal EnableExtensions
set "GREETING=Hello"
echo %GREETING% from %~dp0
```

## Essential pieces

- `%~dp0` - folder where the .bat lives (always end paths with it).
- `setlocal` - variables die when the script ends.
- `if exist "file"` - test before you read.
- `errorlevel` - check exit codes: `if errorlevel 1 ( ... )`.
- `call` - run another batch script or subroutine.
- `goto :label` / `:label` - jump (requires CRLF line endings!).

## Exit codes

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Main.ps1"
if errorlevel 1 (
    echo Something failed.
    pause
    exit /b 1
)
```

## Common pitfalls

- LF-only line endings: `goto :label` silently breaks. Use CRLF.
- Spaces in paths: always quote `"%ROOT%src\Main.ps1"`.
- Permanently changing execution policy: not needed; `-ExecutionPolicy Bypass`
  applies to one process only.
'@

Register-LearningFile 'tutorials/05-powershell-automation.md' @'
# 05 - PowerShell Automation

Windows PowerShell 5.1 ships with Windows 11; PowerShell 7 is the modern
cross-platform edition. Write scripts that work on both.

## Habits that pay off

- `#Requires -Version 5.1` at the top.
- `[CmdletBinding()]` + typed params: `param([string]$Name, [switch]$Force)`.
- Check `$LASTEXITCODE` after every external program call.
- `$ErrorActionPreference = 'Stop'` in entry-point scripts, try/catch around
  risky calls.
- Use `Join-Path`, never string-concatenated paths.
- Avoid aliases in scripts (`ls`, `%`, `?`) - write full cmdlet names.

## Calling programs safely

```powershell
$res = & git status --porcelain 2>&1
if ($LASTEXITCODE -ne 0) { throw "git failed" }
```

## JSON without dependencies

```powershell
$data = Get-Content -Raw config\settings.json | ConvertFrom-Json
$data | ConvertTo-Json -Depth 6 | Set-Content out.json -Encoding UTF8
```

## Dry-run pattern

```powershell
if ($WhatIfPreference) { Write-Host "[DRY-RUN] would do X"; return }
```
'@

Register-LearningFile 'examples/gh-commands.ps1' @'
# gh-commands.ps1 - safe read-only examples. Run: pwsh .\gh-commands.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Signed-in account:'
$user = gh api user | ConvertFrom-Json
Write-Host ("  {0} ({1})" -f $user.login, $user.html_url)

Write-Host ''
Write-Host 'Your 5 most recently pushed repositories:'
$repos = gh repo list --limit 5 --json name,pushedAt,stargazerCount | ConvertFrom-Json
foreach ($r in $repos) {
    Write-Host ("  {0,-30} stars={1,-4} pushed={2}" -f $r.name, $r.stargazerCount, $r.pushedAt)
}

Write-Host ''
Write-Host 'Merged PRs you authored (search API total_count):'
$res = gh api 'search/issues?q=type:pr+is:merged+author:@me&per_page=1' | ConvertFrom-Json
Write-Host ("  total_count = {0}" -f $res.total_count)
'@

Register-LearningFile 'examples/hello-toolkit.bat' @'
@echo off
setlocal
REM Minimal double-click demo that launches PowerShell with a bounded scope.
echo Hello from a double-clicked batch file.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Write-Host (''PowerShell says hi at '' + (Get-Date))"
pause
'@

Register-LearningFile 'examples/CalculatorDemo.ps1' @'
# CalculatorDemo.ps1 - tiny dependency-free demo used by tests\Test-Calculator.ps1
function Add-Numbers { param([double]$A, [double]$B); return $A + $B }
function Multiply-Numbers { param([double]$A, [double]$B); return $A * $B }

if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "2 + 3 = $(Add-Numbers 2 3)"
    Write-Host "4 * 5 = $(Multiply-Numbers 4 5)"
}
'@

Register-LearningFile 'tests/Test-Calculator.ps1' @'
# Test-Calculator.ps1 - dependency-free demo test harness for the lab repo.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\examples\CalculatorDemo.ps1')

$failures = 0
function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ("$Expected" -eq "$Actual") {
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } else {
        Write-Host "  FAIL  $Name (expected $Expected, got $Actual)" -ForegroundColor Red
        $script:failures++
    }
}

Write-Host 'CalculatorDemo tests'
Assert-Equal 5 (Add-Numbers 2 3) 'Add-Numbers 2 3 = 5'
Assert-Equal 20 (Multiply-Numbers 4 5) 'Multiply-Numbers 4 5 = 20'

if ($failures -gt 0) { exit 1 }
Write-Host 'All demo tests passed.' -ForegroundColor Green
'@

Register-LearningFile 'docs/TROUBLESHOOTING.md' @'
# Troubleshooting

## "git is not recognized" / "gh is not recognized"
Install via winget, then OPEN A NEW WINDOW:

```
winget install --id Git.Git -e
winget install --id GitHub.cli -e
```

## gh auth status says "not logged in"
```
gh auth login --web
```
Approve in the browser with the device code shown in the terminal.

## Push rejected (non-fast-forward)
Someone (maybe you, from another machine) pushed first.
```
git pull --rebase origin <branch>
```
Resolve any conflicts, then `git push`. The toolkit will never force-push.

## Permission denied on a repository
Check your role: `gh api repos/OWNER/REPO --jq .permissions`
You need Write/Maintain/Admin to push branches and merge PRs.

## Rate limit exceeded
`gh api rate_limit` shows your budget. Authenticated searches share one
limit; wait and retry. The toolkit degrades gracefully and marks data
as unavailable instead of crashing.

## Execution policy blocks scripts
The toolkit launches with `-ExecutionPolicy Bypass` for its own process.
It never changes your machine-wide policy.
'@

Register-LearningFile 'docs/ACHIEVEMENT-ROADMAP.md' @'
# Achievement Roadmap (honest edition)

| Achievement        | What GitHub rewards                              | How to pursue it honestly              |
|--------------------|--------------------------------------------------|----------------------------------------|
| Pull Shark         | Your PRs get merged (2/16/128/1024)              | Real fixes, docs, tests - no spam      |
| Quickdraw          | Close an issue within 5 minutes of opening       | Legitimate triage of your own issues |
| Pair Extraordinaire| Co-authored merged PRs (1/10/24/48)              | Pair with a real human, co-author tag  |
| Galaxy Brain       | Your answers marked as accepted in Discussions   | Answer questions you know deeply       |
| Starstruck         | Repo stars (16/128/512/4096)                     | Build something useful, document it    |
| YOLO               | Merge a PR without review (reported)             | Already held by ArulAgnes              |
| Public Sponsor     | Sponsor a developer via GitHub Sponsors          | External action, your choice           |
| Arctic Code Vault  | Retired - no longer obtainable                   | n/a                                    |
| Mars 2020          | Retired - no longer obtainable                   | n/a                                    |

Numbers in parentheses are community-reported thresholds; GitHub does not
publish official criteria and they can change without notice.
'@

Register-LearningFile 'CONTRIBUTING.md' @'
# Contributing

Thanks for helping improve this learning lab.

## Ground rules

1. One topic per pull request; keep diffs reviewable.
2. Update or add a doc page for every behavior change.
3. Run `tests\Test-Calculator.ps1` before opening the PR.
4. Commit messages follow Conventional Commits: `type(scope): summary`.
5. No secrets, tokens or `.env` files - the pre-commit scan will refuse.

## Pull request checklist

- [ ] Change is genuinely useful (docs, example, fix, test)
- [ ] README or relevant doc updated
- [ ] Demo test passes
'@

function Install-LearningContent {
    <#
    .SYNOPSIS
        Seeds the local clone of the learning repository with genuine
        educational files. Existing files are backed up, never destroyed.
        Returns the count of files written.
    #>
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
        Write-Fail "$RepoPath does not look like a git repository (no .git folder)."
        return 0
    }
    Write-Banner 'SEED LEARNING CONTENT'
    if (Test-DryRun) {
        Write-Info '[DRY-RUN] Would write these files:'
        foreach ($k in ($script:LearningFiles.Keys | Sort-Object)) { Write-UI "        - $k" -Color 'DarkGray' }
        return 0
    }
    $written = 0
    foreach ($k in ($script:LearningFiles.Keys | Sort-Object)) {
        $target = Join-Path $RepoPath $k
        Write-FileSafe -Path $target -Content $script:LearningFiles[$k] | Out-Null
        $written++
        Write-Success "wrote $k"
    }
    Add-ActivityEntry -Action 'Learning content seeded' -Category 'Repository' -Repository (Split-Path -Leaf $RepoPath) -Result 'SUCCESS' -Detail "$written files written"
    return $written
}

function Show-RepositoryManagerMenu {
    param($Context)
    while ($true) {
        Clear-Host
        Write-Banner 'REPOSITORY MANAGER'
        Write-UI '  [1] List my repositories (with stars)' -Color 'White'
        Write-UI '  [2] Show details for a repository' -Color 'White'
        Write-UI '  [3] Check viewer permission for a repository' -Color 'White'
        Write-UI '  [4] Ensure / create the learning repository' -Color 'White'
        Write-UI '  [5] Seed learning content into a local clone' -Color 'White'
        Write-UI '  [6] Open my GitHub profile in the browser' -Color 'White'
        Write-UI '  [0] Back to main menu' -Color 'Gray'
        Write-Divider
        $choice = Read-MenuChoice -Prompt 'Choice' -ValidChoices 0, 1, 2, 3, 4, 5, 6
        switch ($choice) {
            1 {
                $repos = Get-MyRepositories
                if ($null -eq $repos) { Write-Fail 'Repository list unavailable. Check network and gh auth status.'; Read-Host '  Press Enter to continue'; break }
                $repos = @($repos)
                Write-Banner 'YOUR REPOSITORIES'
                foreach ($r in $repos) {
                    $vis = if ($r.isPrivate) { 'private' } else { 'public ' }
                    Write-UI ("  {0,-38} {1}  stars:{2,-5} pushed:{3}" -f $r.name, $vis, $r.stargazerCount, (Format-IsoTimestamp $r.pushedAt)) -Color 'Gray'
                }
                Read-Host '  Press Enter to continue'
            }
            2 {
                $owner = $Context.User.Login
                $name  = Read-Host '  Repository name (just the name)'
                if ([string]::IsNullOrWhiteSpace($name)) { break }
                $d = Get-RepositoryDetails -FullName "$owner/$name"
                if ($null -eq $d) { break }
                Write-Banner ("REPO: $owner/$name")
                Write-Info "URL:        $($d.url)"
                Write-Info "Visibility: $($d.visibility)   Default branch: $($d.defaultBranchRef.name)"
                Write-Info "Stars:      $($d.stargazerCount)    Forks: $($d.forkCount)"
                Write-Info "Permission: $($d.viewerPermission)  Language: $($d.primaryLanguage.name)"
                Write-Info "Pushed:     $($d.pushedAt)"
                Read-Host '  Press Enter to continue'
            }
            3 {
                $owner = $Context.User.Login
                $name  = Read-Host '  Repository name (just the name)'
                if ([string]::IsNullOrWhiteSpace($name)) { break }
                $perm = Test-RepositoryPermissions -FullName "$owner/$name"
                if ($perm) { Write-Success "Viewer permission: $perm" }
                Read-Host '  Press Enter to continue'
            }
            4 {
                $null = New-LearningRepository -Owner $Context.User.Login
                Read-Host '  Press Enter to continue'
            }
            5 {
                $default = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'github-learning-lab'
                $path = Read-Host "  Local path of the learning repo clone [$default]"
                if ([string]::IsNullOrWhiteSpace($path)) { $path = $default }
                if (-not (Test-Path $path)) {
                    Write-Warn 'Path does not exist. Clone first: gh repo clone <owner>/<repo> "<path>"'
                    Read-Host '  Press Enter to continue'
                    break
                }
                $null = Install-LearningContent -RepoPath $path
                Read-Host '  Press Enter to continue'
            }
            6 { Open-WebPage "https://github.com/$($Context.User.Login)" | Out-Null }
            0 { return }
        }
    }
}
