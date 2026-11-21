#Requires -Version 5.1
<#
.SYNOPSIS
    Run-Tests.ps1 - dependency-free test suite for the GitHub Automation
    & Learning Lab. Run it on Windows with:

        powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1

        (or with PowerShell 7:  pwsh -NoProfile -File .\tests\Run-Tests.ps1)

.DESCRIPTION
    Covers: settings parsing, activity log round-trip, tier calculators,
    secret scanning, branch validation, HTML escaping, backups, PR check
    evaluation, issue title quality, HTML report generation and a syntax
    parse-check of every shipped PowerShell file.

    Network calls are NOT made: the HTML report is generated with
    -UseCachedDataOnly and everything else is pure logic or temp files.
#>

$ErrorActionPreference = 'Stop'
$ToolkitRoot = Split-Path -Parent $PSScriptRoot
$src = Join-Path $ToolkitRoot 'src'

. (Join-Path $PSScriptRoot 'TestCommon.ps1')

# Dot-source every module (same order as Main.ps1)
foreach ($module in @('Common.ps1', 'Authentication.ps1', 'RepositoryManager.ps1', 'CommitManager.ps1', 'PullRequestManager.ps1', 'IssueManager.ps1', 'AchievementTracker.ps1', 'ReportGenerator.ps1')) {
    $modulePath = Join-Path $src $module
    Assert-True (Test-Path $modulePath) "$module must exist"
    . $modulePath
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('github-toolkit-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {

    Write-TestSuite 'Required deliverable files'
    $required = @(
        'RUN-GITHUB-TOOLKIT.bat',
        'src/Main.ps1', 'src/Authentication.ps1', 'src/RepositoryManager.ps1',
        'src/CommitManager.ps1', 'src/PullRequestManager.ps1', 'src/IssueManager.ps1',
        'src/AchievementTracker.ps1', 'src/ReportGenerator.ps1', 'src/Common.ps1',
        'config/settings.json', 'data/activity-log.json',
        'README.md', 'INSTALLATION.md', 'SAFETY.md', 'CHANGELOG.md'
    )
    It 'all required files exist and are non-empty' {
        foreach ($rel in $required) {
            $full = Join-Path $ToolkitRoot $rel
            Assert-True (Test-Path $full) "Missing: $rel"
            Assert-GreaterThan (Get-Item $full).Length 0 "$rel is empty"
        }
    }
    It 'tests folder contains this suite' {
        Assert-True (Test-Path (Join-Path $ToolkitRoot 'tests/Run-Tests.ps1'))
        Assert-True (Test-Path (Join-Path $ToolkitRoot 'tests/TestCommon.ps1'))
    }

    Write-TestSuite 'PowerShell syntax parse-check (all shipped .ps1)'
    It 'every src and tests .ps1 tokenizes without errors' {
        $files = @(Get-ChildItem -Path (Join-Path $ToolkitRoot 'src'), (Join-Path $ToolkitRoot 'tests') -Filter *.ps1 -Recurse)
        Assert-GreaterThan $files.Count 0 'expected script files'
        foreach ($f in $files) {
            $errors = $null
            [void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -Path $f.FullName), [ref]$errors)
            $count = 0
            if ($errors) { $count = @($errors).Count }
            Assert-Equal 0 $count "syntax errors in $($f.Name): $((@($errors) | ForEach-Object { $_.Message }) -join '; ')"
        }
    }

    Write-TestSuite 'Settings'
    It 'settings.json parses and has required keys' {
        $s = Get-ToolkitSettings -Path (Join-Path $ToolkitRoot 'config/settings.json')
        Assert-Equal 'ArulAgnes' $s.expectedGitHubUsername
        Assert-NotNull $s.pullRequestLab
        Assert-NotNull $s.issueLab
        Assert-NotNull $s.logging
        Assert-True ($s.safety.neverForcePush -eq $true) 'neverForcePush safety flag must stay true'
        Assert-True ($s.safety.scanSecretsBeforeCommit -eq $true) 'secret scan safety flag must stay true'
    }
    It 'unexpected settings file throws a readable error' {
        $threw = $false
        try { Get-ToolkitSettings -Path (Join-Path $tempRoot 'missing.json') | Out-Null } catch { $threw = $true }
        Assert-True $threw 'expected an exception for a missing settings file'
    }

    Write-TestSuite 'Activity log round-trip (isolated temp file)'
    It 'entries are appended and read back with required fields' {
        $logPath = Join-Path $tempRoot 'activity-log.json'
        Set-Content -Path $logPath -Value '[]' -Encoding UTF8
        Add-ActivityEntry -Action 'test action' -Category 'Test' -Repository 'owner/repo' -Result 'SUCCESS' -Detail 'hello' -Path $logPath | Out-Null
        Add-ActivityEntry -Action 'test two' -Category 'Test' -Result 'FAILED' -Path $logPath | Out-Null
        $entries = @(Get-ActivityLog -Path $logPath)
        Assert-Equal 2 $entries.Count
        Assert-Equal 'test action' $entries[0].action
        Assert-Equal 'SUCCESS' $entries[0].result
        Assert-Equal 'owner/repo' $entries[0].repository
    }
    It 'an empty log reads as an empty array' {
        $logPath = Join-Path $tempRoot 'empty-log.json'
        Set-Content -Path $logPath -Value '   ' -Encoding UTF8
        $entries = @(Get-ActivityLog -Path $logPath)
        Assert-Equal 0 $entries.Count
    }
    It 'a corrupt log is backed up and read as empty' {
        $logPath = Join-Path $tempRoot 'corrupt-log.json'
        Set-Content -Path $logPath -Value 'this is not json {' -Encoding UTF8
        $entries = @(Get-ActivityLog -Path $logPath)
        Assert-Equal 0 $entries.Count
        $backups = @(Get-ChildItem (Join-Path $tempRoot '.backups') -Filter 'corrupt-log*' -ErrorAction SilentlyContinue)
        Assert-GreaterThan $backups.Count 0 'corrupt log should be preserved as a backup'
    }

    Write-TestSuite 'Pull Shark / Starstruck / Pair Extraordinaire / Galaxy Brain tier math'
    It 'Pull Shark tiers at documented boundaries' {
        Assert-Equal 'None'         (Get-PullSharkTier -MergedCount 0).CurrentTier
        Assert-Equal 2              (Get-PullSharkTier -MergedCount 0).NextThreshold
        Assert-Equal 'Pull Shark'   (Get-PullSharkTier -MergedCount 2).CurrentTier
        Assert-Equal 'Pull Shark'   (Get-PullSharkTier -MergedCount 15).CurrentTier
        Assert-Equal 'Bronze'       (Get-PullSharkTier -MergedCount 16).CurrentTier.Replace('Pull Shark ', '')
        Assert-Equal 'Bronze'       (Get-PullSharkTier -MergedCount 17).CurrentTier.Replace('Pull Shark ', '')
        Assert-Equal 111            (Get-PullSharkTier -MergedCount 17).Remaining
        Assert-Equal 'Silver'       (Get-PullSharkTier -MergedCount 128).CurrentTier.Replace('Pull Shark ', '')
        Assert-Equal 'Gold'         (Get-PullSharkTier -MergedCount 1024).CurrentTier.Replace('Pull Shark ', '')
        Assert-True  (Get-PullSharkTier -MergedCount 1024).MaxedOut
    }
    It 'Starstruck tiers at documented boundaries' {
        Assert-Equal 'None'       (Get-StarstruckTier -Stars 5).CurrentTier
        Assert-Equal 'Starstruck' (Get-StarstruckTier -Stars 16).CurrentTier
        Assert-Equal 107          (Get-StarstruckTier -Stars 21).Remaining
        Assert-Equal 'Bronze'     (Get-StarstruckTier -Stars 128).CurrentTier.Replace('Starstruck ', '')
        Assert-Equal 'Silver'     (Get-StarstruckTier -Stars 512).CurrentTier.Replace('Starstruck ', '')
        Assert-Equal 'Gold'       (Get-StarstruckTier -Stars 4096).CurrentTier.Replace('Starstruck ', '')
    }
    It 'Pair Extraordinaire tiers at documented boundaries' {
        Assert-Equal 'None' (Get-PairExtraordinaireTier -CoAuthoredMerged 0).CurrentTier
        Assert-Equal 1      (Get-PairExtraordinaireTier -CoAuthoredMerged 0).NextThreshold
        Assert-Equal 'Pair Extraordinaire' (Get-PairExtraordinaireTier -CoAuthoredMerged 1).CurrentTier
        Assert-Equal 'Bronze' (Get-PairExtraordinaireTier -CoAuthoredMerged 10).CurrentTier.Replace('Pair Extraordinaire ', '')
        Assert-Equal 'Silver' (Get-PairExtraordinaireTier -CoAuthoredMerged 24).CurrentTier.Replace('Pair Extraordinaire ', '')
        Assert-Equal 'Gold'   (Get-PairExtraordinaireTier -CoAuthoredMerged 48).CurrentTier.Replace('Pair Extraordinaire ', '')
    }
    It 'Galaxy Brain reads thresholds from settings and tiers correctly' {
        Assert-Equal 'None' (Get-GalaxyBrainTier -AcceptedAnswers 1).CurrentTier
        Assert-Equal 'Galaxy Brain' (Get-GalaxyBrainTier -AcceptedAnswers 2).CurrentTier
        Assert-Equal 'Gold' (Get-GalaxyBrainTier -AcceptedAnswers 99).CurrentTier.Replace('Galaxy Brain ', '')
    }
    It 'progress percent stays inside 0-100' {
        foreach ($c in @(0, 1, 2, 7, 16, 100, 128, 500, 1025)) {
            $t = Get-PullSharkTier -MergedCount $c
            Assert-True ($t.Percent -ge 0 -and $t.Percent -le 100) "percent out of range at $c"
        }
    }

    Write-TestSuite 'Secret scanning'
    It 'a clean file produces no findings' {
        $f = Join-Path $tempRoot 'clean.md'
        Set-Content -Path $f -Value '# Just docs' -Encoding UTF8
        $findings = @(Test-SecretScan -Paths @($f))
        Assert-Equal 0 $findings.Count
    }
    It 'detects a token-like string built at runtime' {
        $fake = ('ghp' + '_' + ('A' * 36))
        $f = Join-Path $tempRoot 'notes.txt'
        Set-Content -Path $f -Value ("token: $fake") -Encoding UTF8
        $findings = @(Test-SecretScan -Paths @($f))
        Assert-GreaterThan $findings.Count 0 'expected the token to be detected'
    }
    It 'detects a .env file by name' {
        $f = Join-Path $tempRoot '.env'
        Set-Content -Path $f -Value 'SOME_VALUE=hello' -Encoding UTF8
        $findings = @(Test-SecretScan -Paths @($f))
        Assert-GreaterThan $findings.Count 0 'expected .env to be flagged'
    }
    It 'detects a private key header' {
        $f = Join-Path $tempRoot 'key-material.txt'
        Set-Content -Path $f -Value ("-{5}BEGIN " + "OPENSSH PRIVATE KEY" + "-{5}") -Encoding UTF8
        $findings = @(Test-SecretScan -Paths @($f))
        Assert-GreaterThan $findings.Count 0 'expected the key header to be detected'
    }
    It 'detects an api_key-style assignment' {
        $f = Join-Path $tempRoot 'config.txt'
        Set-Content -Path $f -Value ('client_secret = "abcdefghijklmnop1234"') -Encoding UTF8
        $findings = @(Test-SecretScan -Paths @($f))
        Assert-GreaterThan $findings.Count 0 'expected the assignment to be detected'
    }

    Write-TestSuite 'Git helpers and safety'
    It 'branch name validation accepts good names and rejects bad ones' {
        Assert-True  (Test-BranchNameValid -Name 'lab/docs-20260101-0101')
        Assert-True  (Test-BranchNameValid -Name 'fix/typo')
        Assert-False (Test-BranchNameValid -Name 'bad branch')
        Assert-False (Test-BranchNameValid -Name '-starts-with-dash')
        Assert-False (Test-BranchNameValid -Name 'has..dots')
        Assert-False (Test-BranchNameValid -Name 'trailing/')
        Assert-False (Test-BranchNameValid -Name 'double//slash')
        Assert-False (Test-BranchNameValid -Name '')
    }
    It 'Test-CommandExists returns false for a nonsense command' {
        Assert-False (Test-CommandExists -Name 'definitely-not-a-real-command-xyz-123')
    }
    It 'Backup-FileSafe preserves the original content' {
        $f = Join-Path $tempRoot 'keepme.txt'
        Set-Content -Path $f -Value 'original-content' -Encoding UTF8
        $backup = Backup-FileSafe -Path $f
        Assert-NotNull $backup
        Assert-True (Test-Path $backup)
        Assert-Equal 'original-content' (Get-Content -Raw -Path $backup).Trim()
    }
    It 'Write-FileSafe backs up an existing file instead of clobbering it' {
        $f = Join-Path $tempRoot 'doc.txt'
        Set-Content -Path $f -Value 'version-one' -Encoding UTF8
        Write-FileSafe -Path $f -Content 'version-two' | Out-Null
        $backup = @(Get-ChildItem (Join-Path $tempRoot '.backups') -Filter 'doc.txt*' -ErrorAction SilentlyContinue) | Select-Object -First 1
        Assert-NotNull $backup 'expected a backup of doc.txt'
        Assert-Equal 'version-one' (Get-Content -Raw -Path $backup.FullName).Trim()
        Assert-Equal 'version-two' (Get-Content -Raw -Path $f).Trim()
    }

    Write-TestSuite 'PR check evaluation (no network)'
    It 'CLEAN mergeStateStatus with no checks is mergeable' {
        $status = [pscustomobject]@{ mergeStateStatus = 'CLEAN'; statusCheckRollup = $null }
        $eval = Test-PullRequestChecks -Status $status
        Assert-True $eval.Ok
    }
    It 'BLOCKED mergeStateStatus is not mergeable' {
        $status = [pscustomobject]@{ mergeStateStatus = 'BLOCKED'; statusCheckRollup = $null }
        $eval = Test-PullRequestChecks -Status $status
        Assert-False $eval.Ok
        Assert-Contains $eval.Reason 'Blocked'
    }
    It 'a failing check blocks merging even when mergeStateStatus is CLEAN' {
        $status = [pscustomobject]@{ mergeStateStatus = 'CLEAN'; statusCheckRollup = @( [pscustomobject]@{ name = 'ci/build'; status = 'COMPLETED'; conclusion = 'FAILURE' } ) }
        $eval = Test-PullRequestChecks -Status $status
        Assert-False $eval.Ok
        Assert-Contains $eval.Reason 'ci/build'
    }
    It 'a queued check marks the PR as pending' {
        $status = [pscustomobject]@{ mergeStateStatus = 'CLEAN'; statusCheckRollup = @( [pscustomobject]@{ name = 'ci/build'; status = 'IN_PROGRESS'; conclusion = $null } ) }
        $eval = Test-PullRequestChecks -Status $status
        Assert-True $eval.Pending
        Assert-False $eval.Ok
    }
    It 'conflicting DIRTY state reports conflicts' {
        $status = [pscustomobject]@{ mergeStateStatus = 'DIRTY'; statusCheckRollup = $null }
        $eval = Test-PullRequestChecks -Status $status
        Assert-Contains $eval.Reason 'conflict'
    }

    Write-TestSuite 'Issue quality gates'
    It 'rejects placeholder titles' {
        Assert-False (Test-IssueTitleQuality -Title 'test').Ok
        Assert-False (Test-IssueTitleQuality -Title 'asdf').Ok
        Assert-False (Test-IssueTitleQuality -Title 'short').Ok
        Assert-True  (Test-IssueTitleQuality -Title 'docs: clarify Windows install steps').Ok
    }

    Write-TestSuite 'HTML report generation (offline mode)'
    It 'UseCachedDataOnly produces a valid self-contained report' {
        $dataBackup = $null
        $realLog = Join-Path $ToolkitRoot 'data/activity-log.json'
        if (Test-Path $realLog) {
            $dataBackup = Join-Path $tempRoot 'activity-log.backup.json'
            Copy-Item -Path $realLog -Destination $dataBackup -Force
        }
        try {
            $report = New-HtmlProgressReport -OutputFolder $tempRoot -UseCachedDataOnly
            Assert-True (Test-Path $report)
            $html = Get-Content -Raw -Path $report
            Assert-Contains $html 'Pull Shark'
            Assert-Contains $html 'Achievement eligibility'
            Assert-Contains $html 'UNLOCKED'
            Assert-Contains $html 'github.com'
            Assert-Contains $html '<html'
            Assert-True ($html -notmatch '<script') 'report must not embed scripts'
        } finally {
            if ($dataBackup -and (Test-Path $dataBackup)) { Copy-Item -Path $dataBackup -Destination $realLog -Force }
        }
    }
    It 'ConvertTo-HtmlSafe escapes markup' {
        $escaped = ConvertTo-HtmlSafe '<b>"Tom & Jerry"</b>'
        Assert-Contains $escaped '&lt;b&gt;'
        Assert-Contains $escaped '&amp;'
        Assert-Contains $escaped '&quot;'
    }

    Write-TestSuite 'HTML help files'
    $readme = Get-Content -Raw (Join-Path $ToolkitRoot 'README.md')
    It 'README documents the double-click launch and honest achievement claims' {
        Assert-Contains $readme 'RUN-GITHUB-TOOLKIT.bat'
        Assert-Contains $readme 'Pull Shark'
        Assert-Contains $readme 'community-reported'
    }

    $ok = Complete-TestRun
} finally {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    if ($ok) { exit 0 } else { exit 1 }
}
