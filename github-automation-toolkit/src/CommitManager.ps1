#Requires -Version 5.1
<#
.SYNOPSIS
    CommitManager.ps1 - safe git helpers: status, staging, commits, push,
    secret scanning and conflict handling.
.DESCRIPTION
    Every external git call checks $LASTEXITCODE. The toolkit never force
    pushes, never rewrites pushed history and never commits files that look
    like credentials.
#>

function Get-GitStatusPorcelain {
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    $res = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'status', '--porcelain=v1')
    if (-not $res.Success) { return $null }
    return @($res.Output | Where-Object { $_.Trim().Length -gt 0 })
}

function Test-GitRepository {
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    $res = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'rev-parse', '--is-inside-work-tree')
    return ($res.Success -and ($res.Output -join '').Trim() -eq 'true')
}

function Get-CurrentBranch {
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    $res = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'rev-parse', '--abbrev-ref', 'HEAD')
    if (-not $res.Success) { return $null }
    return ($res.Output -join '').Trim()
}

function Get-RemoteUrl {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [string]$Remote = 'origin'
    )
    $res = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'remote', 'get-url', $Remote)
    if (-not $res.Success) { return $null }
    return ($res.Output -join '').Trim()
}

function Test-BranchNameValid {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    # git-check-ref-format covers most rules; add Windows-friendly constraints too
    if ($Name.Length -gt 120) { return $false }
    if ($Name -match '[\s~^:?*\[\\]') { return $false }
    if ($Name.StartsWith('-') -or $Name.StartsWith('/') -or $Name.EndsWith('/')) { return $false }
    if ($Name -match '\.\.' -or $Name -match '@\{') { return $false }
    if ($Name.EndsWith('.lock') -or $Name.Contains('//')) { return $false }
    return $true
}

function Get-MergeConflicts {
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    $status = Get-GitStatusPorcelain -RepoPath $RepoPath
    if ($null -eq $status) { return @() }
    return @($status | Where-Object { $_ -match '^(UU|AA|DD|AU|UA|DU|UD)\s' } | ForEach-Object { $_.Substring(3) })
}

function Show-ConflictGuidance {
    param(
        [Parameter(Mandatory = $true)][string[]]$ConflictFiles,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )
    Write-Fail 'Git reported conflicts. The toolkit will NOT auto-resolve them.'
    foreach ($f in $ConflictFiles) { Write-UI "        conflicted: $f" -Color 'Red' }
    Write-UI '' 
    Write-UI '  Safe recovery steps:' -Color 'Yellow'
    Write-UI '    1. Open each conflicted file, look for <<<<<<< / ======= / >>>>>>> markers.' -Color 'Gray'
    Write-UI '    2. Keep the version you want and remove the markers.' -Color 'Gray'
    Write-UI '    3. git add <file>' -Color 'Gray'
    Write-UI '    4. git commit                 (merge)   or   git rebase --continue' -Color 'Gray'
    Write-UI '    -or- to abort everything and get back to a clean state:' -Color 'Gray'
    Write-UI '       git merge --abort        (if you were merging)' -Color 'Gray'
    Write-UI '       git rebase --abort       (if you were rebasing)' -Color 'Gray'
}

function New-FeatureBranch {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string]$BranchName
    )
    if (-not (Test-BranchNameValid -Name $BranchName)) {
        Write-Fail "Branch name '$BranchName' is not valid. Use lowercase words separated by '/' and '-'."
        return $false
    }
    if (Test-DryRun) {
        Write-Info "[DRY-RUN] Would run: git -C `"$RepoPath`" switch -c $BranchName"
        return $true
    }
    $res = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'switch', '-c', $BranchName)
    if (-not $res.Success) {
        foreach ($line in $res.Output) { Write-UI "        $line" -Color 'DarkRed' }
        Write-Fail "Could not create branch '$BranchName' (exit $($res.ExitCode))."
        return $false
    }
    Write-Success "Switched to new branch '$BranchName'"
    return $true
}

function Get-ChangedAndUntrackedFiles {
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    $status = Get-GitStatusPorcelain -RepoPath $RepoPath
    if ($null -eq $status) { return @() }
    $files = @()
    foreach ($line in $status) {
        $path = $line.Substring(3).Trim()
        if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1].Trim() } # renames
        if ($path) { $files += (Join-Path $RepoPath $path) }
    }
    return $files
}

function Protect-StagedSecrets {
    <#
    .SYNOPSIS
        Secret-scan every file that would be committed. Returns $true when clean.
    #>
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    $candidates = Get-ChangedAndUntrackedFiles -RepoPath $RepoPath
    if ($candidates.Count -eq 0) { return $true }
    $findings = @(Test-SecretScan -Paths $candidates)
    if ($findings.Count -gt 0) {
        Write-Fail 'Secret scan found credential-like content. Commit ABORTED.'
        foreach ($f in $findings) { Write-UI ("        {0}: {1}" -f $f.File, $f.Reason) -Color 'Red' }
        Write-Info 'Remove the secret from the file (or add it to .gitignore), then retry.'
        return $false
    }
    return $true
}

function New-ConventionalCommit {
    <#
    .SYNOPSIS
        Interactive helper that builds a Conventional Commit message and
        creates the commit for the already-staged (or newly staged) paths.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [string[]]$Files = @()
    )
    $conflicts = Get-MergeConflicts -RepoPath $RepoPath
    if ($conflicts.Count -gt 0) { Show-ConflictGuidance -ConflictFiles $conflicts -RepoPath $RepoPath; return $false }

    if (-not (Protect-StagedSecrets -RepoPath $RepoPath)) { return $false }

    Write-Banner 'COMMIT HELPER (Conventional Commits)'
    $types = @('feat', 'fix', 'docs', 'test', 'refactor', 'chore', 'ci', 'build', 'perf')
    for ($i = 0; $i -lt $types.Count; $i++) { Write-UI ("  [{0}] {1}" -f ($i + 1), $types[$i]) -Color 'Gray' }
    $typeIndex = Read-MenuChoice -Prompt 'Select commit type' -ValidChoices (1..$types.Count)
    $type = $types[$typeIndex - 1]
    $scope   = Read-Host '  Scope (optional, e.g. docs, lab)'
    $summary = Read-Host '  One-line summary (imperative mood)'
    if ([string]::IsNullOrWhiteSpace($summary)) { Write-Warn 'Empty summary; commit cancelled.'; return $false }
    $summary = $summary.Trim()
    $scopePart = ''
    if (-not [string]::IsNullOrWhiteSpace($scope)) { $scopePart = '(' + $scope.Trim() + ')' }
    $message = '{0}{1}: {2}' -f $type, $scopePart, $summary

    return New-GitCommit -RepoPath $RepoPath -Files $Files -Message $message
}

function New-GitCommit {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [string[]]$Files = @(),
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Message.Trim().Length -lt 10) {
        Write-Warn "Commit message looks too short ('$Message'). Use at least 10 meaningful characters."
        return $false
    }
    if (Test-DryRun) {
        Write-Info "[DRY-RUN] Would commit in '$RepoPath' with message: $Message"
        return $true
    }
    if ($Files.Count -gt 0) {
        $addArgs = @('-C', $RepoPath, 'add', '--') + $Files
        $add = Invoke-ExternalCaptured -FilePath 'git' -Arguments $addArgs
        if (-not $add.Success) { Write-Fail "git add failed (exit $($add.ExitCode))."; return $false }
    }
    # Secret scan the exact paths being committed (or everything staged)
    $staged = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'diff', '--cached', '--name-only')
    if ($staged.Success) {
        $stagedFull = @($staged.Output | Where-Object { $_.Trim() } | ForEach-Object { Join-Path $RepoPath $_.Trim() })
        $findings = @(Test-SecretScan -Paths $stagedFull)
        if ($findings.Count -gt 0) {
            Write-Fail 'Secret scan of staged files found credential-like content. Commit ABORTED.'
            foreach ($f in $findings) { Write-UI ("        {0}: {1}" -f $f.File, $f.Reason) -Color 'Red' }
            return $false
        }
    }
    $commit = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'commit', '-m', $Message)
    if (-not $commit.Success) {
        foreach ($line in $commit.Output) { Write-UI "        $line" -Color 'DarkRed' }
        Write-Fail "git commit failed (exit $($commit.ExitCode))."
        return $false
    }
    foreach ($line in $commit.Output) { Write-UI "        $line" -Color 'Gray' }
    Add-ActivityEntry -Action 'Commit created' -Category 'Commit' -Detail $Message -Result 'SUCCESS'
    return $true
}

function Push-CurrentBranch {
    <#
    .SYNOPSIS
        Pushes the current branch. NEVER force-push. On rejection, explains
        the safe recovery (pull --rebase) instead of forcing.
    #>
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    $branch = Get-CurrentBranch -RepoPath $RepoPath
    if (-not $branch) { Write-Fail 'Could not determine current branch.'; return $false }
    if ($branch -eq 'main' -or $branch -eq 'master') {
        Write-Warn "You are about to push directly to '$branch'. The toolkit usually works from a feature branch."
        if (-not (Read-YesNo "Push to $branch anyway?" $false)) { return $false }
    }
    if (Test-DryRun) {
        Write-Info "[DRY-RUN] Would run: git -C `"$RepoPath`" push -u origin $branch"
        return $true
    }
    $push = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'push', '-u', 'origin', $branch)
    foreach ($line in $push.Output) { Write-UI "        $line" -Color 'Gray' }
    if ($push.Success) {
        Write-Success "Pushed '$branch' to origin."
        Add-ActivityEntry -Action 'Branch pushed' -Category 'Commit' -Detail $branch -Result 'SUCCESS'
        return $true
    }
    $joined = ($push.Output -join "`n").ToLowerInvariant()
    Write-Fail "Push failed (exit $($push.ExitCode)). The toolkit never force-pushes."
    if ($joined -match 'fetch first|non-fast-forward|rejected') {
        Write-Warn 'The remote has commits you do not have locally. Safe fix:'
        Write-UI "    git -C `"$RepoPath`" pull --rebase origin $branch" -Color 'Yellow'
        Write-UI '    resolve any conflicts, then push again.' -Color 'Yellow'
    } elseif ($joined -match 'permission|denied|403') {
        Write-Warn 'Permission problem. Check: gh auth status  and your repo role (Write+).'
    } elseif ($joined -match 'repository not found|could not read') {
        Write-Warn 'Remote not found or no access. Check: git remote -v'
    }
    Add-ActivityEntry -Action 'Branch pushed' -Category 'Commit' -Detail "$branch - push FAILED" -Result 'FAILED'
    return $false
}

function Switch-BackToDefaultBranch {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [string]$DefaultBranch = 'main'
    )
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: git -C `"$RepoPath`" switch $DefaultBranch"; return $true }
    $res = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'switch', $DefaultBranch)
    return $res.Success
}

function Update-DefaultBranch {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [string]$DefaultBranch = 'main'
    )
    if (Test-DryRun) { Write-Info "[DRY-RUN] Would run: git -C `"$RepoPath`" pull --ff-only origin $DefaultBranch"; return $true }
    $res = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('-C', $RepoPath, 'pull', '--ff-only', 'origin', $DefaultBranch)
    if (-not $res.Success) {
        Write-Warn "Could not fast-forward '$DefaultBranch' (exit $($res.ExitCode)). Continuing with local state."
        return $false
    }
    return $true
}
