# Installation Guide

This guide takes you from nothing to a running toolkit by double-clicking one file.
It assumes **Windows 11**, but Windows 10 (1809+) works too.

---

## 1. Prerequisites (two programs)

The toolkit needs **Git** and the **GitHub CLI**. You can install them yourself, or let
the toolkit offer to do it on first run (via winget).

### Check whether you have them

Press `Win + R`, type `cmd`, press Enter, then run:

```bat
git --version
gh --version
```

Both commands should print a version. If either says *"not recognized"*, continue below.

### Install Git

Option A (recommended) — winget (built into Windows 11):

```bat
winget install --id Git.Git --exact
```

Option B — installer from <https://git-scm.com/download/win>.
Defaults are fine; on the "PATH environment" screen keep *Git from the command line and
also from 3rd-party software*.

### Install the GitHub CLI

```bat
winget install --id GitHub.cli --exact
```

or <https://cli.github.com/>.

> **Important:** after installing either tool, **close all terminals and open a new
> one** — PATH changes don’t apply to already-open windows.

---

## 2. Extract the toolkit

1. Find the downloaded `github-automation-toolkit.zip`.
2. Right-click → **Extract All…**
3. Choose a simple path without spaces, for example:

   ```
   C:\Tools\github-automation-toolkit
   ```

4. You should see this structure:

   ```
   C:\Tools\github-automation-toolkit
   ├── RUN-GITHUB-TOOLKIT.bat
   ├── src\
   ├── config\
   ├── data\
   ├── docs\
   ├── tests\
   └── …
   ```

---

## 3. Double-click to launch

1. Open the extracted folder in File Explorer.
2. Double-click **`RUN-GITHUB-TOOLKIT.bat`**.
3. If Windows SmartScreen appears ("Windows protected your PC"), click
   **More info → Run anyway** (this happens because the file is an unsigned community
   script, not because of detection — you can review `RUN-GITHUB-TOOLKIT.bat` first; it
   is short and readable).
4. A console window opens and the toolkit runs through its startup checklist:

   ```
   Step 1/9  Checking Windows and PowerShell...
   Step 2/9  Checking Git installation...
   Step 3/9  Checking GitHub CLI installation...
   Step 4/9  Verifying required tools...
   Step 5/9  Checking GitHub authentication...
   Step 6/9  Starting browser-based GitHub sign-in...   (first run only)
   Step 7/9  Reading the authenticated GitHub account...
   Step 8/9  Verifying the account...
   Step 9/9  Reading your repositories...
   ```

5. **First run only:** your browser opens at <https://github.com/login/device>.
   Enter the device code printed in the console, sign in to GitHub, approve the
   `repo`, `read:user` and `gist` scopes requested by the GitHub CLI.
6. The dashboard appears:

   ```
   ==============================================
          GITHUB AUTOMATION & LEARNING LAB
   ==============================================
   ACCOUNT: ArulAgnes
   AUTHENTICATION: CONNECTED
   ```

### What the launcher does (and does not) do

| Behavior | Detail |
|---|---|
| PowerShell selection | Prefers PowerShell 7 (`pwsh.exe`) if installed, else uses the Windows PowerShell 5.1 that ships with Windows |
| Execution policy | Runs with `-ExecutionPolicy Bypass` **for this process only**. Your machine-wide execution policy is never changed |
| Console behavior | On non-zero exit codes the window pauses so you can read the error |
| Credentials | The launcher never sees or stores any password or token |

---

## 4. First-time setup checklist

Inside the toolkit:

1. **[5] Repository Manager → [4] Ensure / create the learning repository** — creates
   `ArulAgnes/github-learning-lab` (public) if missing.
2. **[5] → [5] Seed learning content** — point it at a local clone
   (`gh repo clone ArulAgnes/github-learning-lab`) to fill it with tutorials.
3. **[6] Achievement Eligibility Guide** — read what is achievable honestly.
4. Press **[D]** to arm **dry-run mode** and walk through menu [2] (PR lab) to preview
   what it would do. Press **[D]** again to disarm.
5. **[8] Generate HTML Progress Report** — open
   `reports\achievement-report-<timestamp>.html` to see your baseline.

Logs live in `data\activity-log.json`; backups are written to `.backups\` next to any
file the toolkit ever overwrites.

---

## 5. Uninstalling

The toolkit is self-contained. To remove it:

1. Delete the `github-automation-toolkit` folder (your reports are in `reports\` — copy them out first if you want them).
2. Optionally remove `github-learning-lab` on GitHub (only you can delete it — the
   toolkit never deletes anything).
3. Optionally `gh auth logout`.

Nothing is written outside the toolkit folder except the GitHub CLI’s own credential
store and your git configuration (only if you configure it yourself).

---

## Test report

**Status of automated verification as of v1.0.0 (2026-11-21):**

| Check | Environment | Result |
|---|---|---|
| All required files present, non-empty | Linux sandbox (authoring) | PASS (verified by script) |
| Syntax parse-check of every `.ps1` | Windows PowerShell 5.1 / PowerShell 7 **not available in the authoring environment**; the check is built into `tests\Run-Tests.ps1` and runs on your machine | PENDING on Windows |
| Logic test suite (`tests\Run-Tests.ps1`) | Authoring environment cannot execute PowerShell; suite is authored for Windows 5.1/7 | **Not executed — see below** |
| Live GitHub API calls | Not executed (no Windows host, credentials not used) | PENDING |
| 34-scenario manual plan | [tests/MANUAL-TEST-PLAN.md](tests/MANUAL-TEST-PLAN.md) | PENDING on your PC |

**Honest statement:** the toolkit was written to be Windows PowerShell 5.1 compatible
and has been statically reviewed, but the authoring environment has no Windows and no
PowerShell runtime. Before trusting it with important repositories, run the automated
suite and the manual plan:

```bat
cd C:\Tools\github-automation-toolkit
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Record results in `CHANGELOG.md` under a "Tested on" line. If any test fails, please
open an issue in the repository you use for this project — or fix and re-run.

### Quick smoke test (no browser or network needed)

```bat
cd C:\Tools\github-automation-toolkit
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Expected tail:

```
  RESULT: N passed, 0 failed, M skipped
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| BAT opens and closes instantly | Right-click → Edit to read errors; the BAT pauses on failure. Or run from `cmd` and read the message |
| SmartScreen blocks the file | Click **More info → Run anyway** after reviewing the script |
| `winget` not found | Install *App Installer* from the Microsoft Store, or use the manual installers linked above |
| `gh auth login` device code expires | Just run the toolkit again; a fresh code is issued |
| Tool says "expected account" mismatch | Sign out (`gh auth logout`) and sign in with ArulAgnes, or press `y` to continue with the other account |
| Rate limit errors | `gh api rate_limit`; wait for reset, then retry. Trackers show UNAVAILABLE instead of crashing |
| Report won’t open | Reports are in `reports\`; open via File Explorer. They work offline (no internet needed to view) |
