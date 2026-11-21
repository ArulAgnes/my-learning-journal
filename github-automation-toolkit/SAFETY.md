# Safety Model

The GitHub Automation & Learning Lab touches real repositories. This document is the
contract: what the toolkit will **never** do, what it **always** does, and how it fails.

---

## 1. Hard guarantees (never)

1. **Never force-push.** There is no `--force`, `--force-with-lease` or `+refspec`
   anywhere in the source. The push helper explains non-fast-forward rejections and
   suggests `git pull --rebase` instead.
2. **Never deletes** repositories, branches, tags, releases or issues.
3. **Never rewrites published history** — no rebase of shared branches, no amend of
   pushed commits.
4. **Never stores credentials.** No passwords, tokens, secrets or OAuth codes appear
   in source, config, logs or reports. GitHub authentication lives in the GitHub
   CLI’s own credential store (Windows Credential Manager).
5. **Never disables safeguards**: no branch-protection bypass, no `--admin` merges,
   no required-check suppression, no `core.hooksPath` tampering.
6. **Never fabricates events**: it logs a merge only after `gh pr view` confirms
   `state == MERGED`; it counts a Galaxy Brain answer only after GraphQL confirms the
   accepted-answer author is you; it never invents collaborators.
7. **Never uploads secrets**: every commit the toolkit makes passes a secret-scan
   gate (`.env`, `*.pem`, `*.key`, `id_rsa`, `ghp_*`, `github_pat_*`, private-key
   headers, `api_key`/`client_secret`-style assignments). Findings abort the commit.
8. **Never overwrites without backup**: any file it would replace is copied to
   `.backups\<name>.<timestamp>.bak` first.
9. **Never changes machine-wide execution policy** — it uses per-process
   `-ExecutionPolicy Bypass` only.
10. **Never creates fake engagement**: no star schemes, no empty PRs, no issue farms,
    no bot accounts, no self-acceptance of own answers, no second-account simulation.

## 2. Always-on behaviors

- `$LASTEXITCODE` is checked after **every** external command (git, gh, winget).
- Settings (`config\settings.json`) that can disable safety gates are honored only
  when explicitly set; defaults are the safe values.
- **Dry-run mode** (`"dryRun": true`, toggle with `[D]`): every mutating path prints
  what it *would* do and performs nothing. If the settings file is unreadable, the
  toolkit behaves as if dry-run were **on** (fail-safe).
- **Preview mode** (`"previewMode": true`, the default): the PR lab shows the exact
  file and content it would add and stops there.
- **Per-run limits**: `pullRequestLab.maxPullRequestsPerRun` (default 3) and
  `issueLab.maxIssuesPerRun` (default 1) cap automated creation per session.
- **Confirmations**: creation, closing, merging and enabling real (non-dry-run) mode
  always ask first. Declining is always an accepted answer.
- **Conflict handling**: the toolkit detects unmerged paths, prints recovery steps,
  and stops. It never auto-resolves.
- **Activity log**: every GitHub-facing action appends to `data\activity-log.json`
  with timestamp, category, result (SUCCESS/FAILED/WAITING/PREVIEW) and URL.

## 3. What the toolkit CANNOT guarantee

- GitHub may refuse operations (permissions, protections, rate limits). Refusals are
  reported; they are never worked around.
- Secret scanning is heuristic. It catches common shapes, not every possible secret
  format. Review your diffs.
- Search-API counts (merged PRs, fast-closed issues) can lag or approximate GitHub’s
  internal state. Achievement eligibility is decided by GitHub alone.
- Star growth, answer acceptance and co-authorship require other humans. The toolkit
  facilitates legitimate paths; it cannot guarantee outcomes.

## 4. Data handling & privacy

| Data | Where it lives | Sent anywhere? |
|---|---|---|
| GitHub credentials | Windows Credential Manager (via `gh`) | Only to github.com by `gh` |
| `data\activity-log.json` | Local disk, toolkit folder | Never uploaded by the toolkit |
| Generated reports | `reports\*.html` | Never uploaded; safe to share (no tokens embedded) |
| Draft discussion answers | `data\draft-*.md` | Only if you copy them to GitHub yourself |

## 5. Reporting a problem

If the toolkit ever does something unexpected:

1. Stop (close the window).
2. Copy `data\activity-log.json` before experimenting — it’s the audit trail.
3. Check `.backups\` for the pre-change copy of any overwritten file.
4. Revert with normal git commands (`git restore`, `git reset --soft` — never with
   `--force` on shared branches).

## 6. Abuse resistance

The quality gates are deliberately annoying: placeholder issue titles (`test`,
`asdf`), tiny bodies, unverified collaborators, and self-marked answers are all
refused. This protects **you** from earning a reputation as a spam account — which
would be far worse for your GitHub journey than slow progress.
