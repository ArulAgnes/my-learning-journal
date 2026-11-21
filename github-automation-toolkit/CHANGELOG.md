# Changelog

All notable changes to the GitHub Automation & Learning Lab are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project
uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-21

### Added
- `RUN-GITHUB-TOOLKIT.bat`: double-click launcher (prefers PowerShell 7, falls back
  to Windows PowerShell 5.1; per-process execution-policy bypass; pause-on-error).
- `src/Main.ps1`: automatic startup (OS/PowerShell check → Git/GitHub CLI detection
  → optional winget install → browser-based `gh auth login` → account verification
  against `expectedGitHubUsername` → repository scan → dashboard loop).
- `src/Common.ps1`: console UI helpers, progress bars, external-process wrapper with
  `$LASTEXITCODE` checks, settings load/save, append-only JSON activity log,
  secret scanner, `.backups/`-based file backup, HTML escaping, offline-safe HTML
  report utilities.
- `src/Authentication.ps1`: environment detection, winget-based installation offers,
  `gh` authentication flow, account confirmation, startup context.
- `src/RepositoryManager.ps1`: repository listing/details/permissions, learning
  repository creation, seeded educational content (5 tutorials, 3 examples, demo test
  harness, troubleshooting and achievement guides).
- `src/CommitManager.ps1`: git status/branch/commit/push helpers, Conventional
  Commit builder, secret-scan gate before every commit, conflict detection with
  safe-recovery guidance (never auto-resolve), no-force-push enforcement.
- `src/PullRequestManager.ps1`: merged-PR counting via search API, genuine improvement
  candidates (docs/developer guide, CONTRIBUTING, .editorconfig, PR/issue templates),
  preview mode, per-run limit, branch creation, PR creation, mergeability/checks
  evaluation, optional self-merge with post-merge verification.
- `src/IssueManager.ps1`: Quickdraw workflow — quality-gated issue creation, inspect,
  optional close with comment, 5-minute eligibility timing and search-API scan of
  fast-closed issues.
- `src/AchievementTracker.ps1`: Pull Shark / Starstruck / Pair Extraordinaire /
  Galaxy Brain trackers with pure, unit-tested tier calculators; collaborator
  verification (incl. official noreply email derivation); GraphQL verification that
  an accepted answer belongs to you; full eligibility reference (obtainable / retired /
  experimental).
- `src/ReportGenerator.ps1`: self-contained HTML progress report (works offline, no
  scripts, five status levels: UNLOCKED / PROGRESS / WAITING / NOT ELIGIBLE /
  UNAVAILABLE).
- Docs: README (feature map, honest eligibility table), INSTALLATION (double-click
  walkthrough, winget steps, honest test report), SAFETY (guarantees, threat model),
  achievement deep-reference.
- Tests: `tests/Run-Tests.ps1` (dependency-free), `tests/TestCommon.ps1`,
  `tests/MANUAL-TEST-PLAN.md` (34 Windows scenarios).

### Safety
- No force-push, no deletions, no credential storage, secret scan on every commit,
  automatic backups before overwrite, dry-run fail-safe default.

### Known limitations
- Automated tests were not executed on Windows in the authoring environment; see
  INSTALLATION.md → Test report and tests/MANUAL-TEST-PLAN.md.
- GitHub achievement criteria are undocumented; all thresholds are community-reported.
- Galaxy Brain and Pair Extraordinaire progress depends on other humans.

### Tested on
- Authoring environment: static review only (Linux, no PowerShell runtime).
- Windows 11 / PowerShell 5.1 / PowerShell 7: **pending user verification** (run
  `tests\Run-Tests.ps1` and the manual plan).
