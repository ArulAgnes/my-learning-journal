# Manual Test Plan (Windows 11)

The automated suite (`Run-Tests.ps1`) covers logic that does not need Windows or
GitHub credentials. The scenarios below need a real Windows machine with
configurable tools and a GitHub account. Run them on a test repository, never on
something you care about.

Mark each row PASS/FAIL and record the date + Windows build + PowerShell version
and paste the result into `CHANGELOG.md` under a "Tested on" note.

## A. Environment and startup

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| A1 | Missing Git | Uninstall Git (or rename `git.exe` on PATH) and double-click the BAT | Toolkit detects missing Git, offers `winget install --id Git.Git`, exits gracefully if declined |
| A2 | Missing GitHub CLI | Same for `gh.exe` | Toolkit offers `winget install --id GitHub.cli`, exits gracefully if declined |
| A3 | winget absent | Temporarily remove App Installer | Toolkit prints manual download links, does not crash |
| A4 | Logged out | `gh auth logout`, double-click BAT | Startup offers browser sign-in, device code shown, continues after approval |
| A5 | Logged in | Normal double-click | "AUTHENTICATION: CONNECTED", account = signed-in user |
| A6 | Wrong account signed in | `gh auth login` with a different account | Warning shown; asks before continuing; dashboard uses the signed-in account |
| A7 | No network | Disable Wi-Fi / unplug Ethernet | Repo list marks unavailable; dashboard still opens; no stack traces |
| A8 | Corrupt settings.json | Add a `{` typo | Readable error naming the file; exit without data loss |

## B. Repository manager

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| B1 | Existing repo | Menu 5 -> 1, 2, 3 on an existing repo | List/details/permissions shown |
| B2 | Non-existent learning repo | Menu 5 -> 4, answer Yes | Repo created as `ArulAgnes/github-learning-lab` (public) |
| B3 | Learning repo already exists | Menu 5 -> 4 again | "already exists", no duplicate creation |
| B4 | Seed content into empty clone | Clone the repo, Menu 5 -> 5 | ~14 files with real content; re-running backs up existing files to `.backups\` |
| B5 | No permission repo | Menu 5 -> 3 on a read-only repo | Reports `Read` permission honestly |

## C. Commit lab and safety

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| C1 | Secret detection | Put `ghp_<36 random-ish chars>` into a test file, commit via helper | Commit refused, file path + reason printed |
| C2 | `.env` file | Create `.env`, commit via helper | Commit refused (blocked file name) |
| C3 | Conflict state | Create a merge conflict, then commit | Toolkit stops, prints safe recovery steps, resolves nothing itself |
| C4 | Failed push | Disconnect network, push branch | Clear error; suggests `git pull --rebase`; NO force-push happens |
| C5 | Direct push to main | Choose push on `main` at the prompt | Extra confirmation required; decline by default |

## D. PR lab

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| D1 | Preview mode | Settings `previewMode: true`, run lab | Files previewed; zero writes, zero branches, zero PRs |
| D2 | New repo, clean slate | Empty learning repo clone | Candidates offered (docs/templates); each is a real file |
| D3 | PR creation | Accept a candidate on a scratch repo | Branch pushed, PR opened, URL shown and logged |
| D4 | Failed PR creation | Remove push permission (or use read-only repo) | Clear error, log entry `FAILED`, no merge attempted |
| D5 | Failed merge | Branch protection requiring 1 review | `gh pr merge` refused; toolkit reports GitHub refused; does not retry with admin flags |
| D6 | Merge success | Self-merge allowed, no required checks | PR merged via squash; toolkit re-reads state and only then logs `SUCCESS` |
| D7 | Per-run limit | Set `maxPullRequestsPerRun: 1` | Lab stops after 1 PR |

## E. Issue lab (Quickdraw)

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| E1 | Quality gate | Title `test` | Refused with reason |
| E2 | Create + close fast | Create issue, fix trivially, close within 5 min | Logged with minutes; "window met" shown |
| E3 | Close after window | Wait > 5 minutes then close | Logged as outside window; not counted |

## F. Reports

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| F1 | HTML report | Menu 8 | `reports\achievement-report-*.html` opens offline; sections render; no `<script>` tags |
| F2 | Offline report | Disconnect network, Menu 8 | Report still generates with UNAVAILABLE chips; no crash |

## G. Sign-off

- Date tested:
- Windows build:
- PowerShell versions tested: 5.1 / 7.x
- GitHub CLI version:
- Result summary (X/34 passed):
