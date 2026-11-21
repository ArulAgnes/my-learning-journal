# Achievement Reference — Eligibility, Mechanics, Honest Paths

> **Reality check up front:** GitHub documents almost none of this officially.
> Everything below is based on community observation and the toolkit’s own API
> behavior. Thresholds can change at any time. Only GitHub can award a badge.

Status legend: **UNLOCKED** (GitHub shows it) · **PROGRESS** (qualifying activity
exists) · **WAITING** (someone else or GitHub must act) · **NOT ELIGIBLE** (requirements
unmet) · **UNAVAILABLE** (cannot be earned at all).

---

## Pull Shark — 2 / 16 / 128 / 1,024 merged PRs

**What counts:** pull requests you *opened* that were merged, in any repository.

**What does not count:** PRs closed without merging; direct pushes; PRs opened by the
repository itself (e.g. some bots).

**Honest paths:**
- Your own learning/lab repos: open a PR, self-merge when rules permit (the toolkit’s
  PR lab does exactly this for genuine missing-file improvements).
- Fork-and-fix real issues in repos you use; typo and doc patches that genuinely help.
- One *meaningful* PR beats ten empty ones — and one spam wave can get your account
  restricted, which would cost you every achievement.

**How the toolkit tracks it:** `gh api search/issues?q=type:pr+is:merged+author:@me`
(full count) plus the 10 most recent merged PRs with links and dates. A merge is
considered confirmed only when `gh pr view --json state` returns `MERGED`.

**Current standing for ArulAgnes:** Pull Shark held (user-reported). Progress to Bronze
(16) via the PR lab.

---

## Quickdraw — close an issue within 5 minutes

**What counts:** an issue you opened being closed within five minutes of creation.

**Honest paths:**
- You spot a typo → open an issue describing it → fix it in the same sitting → close
  with a comment. That is a textbook, legitimate Quickdraw.
- You open a "bug" that turns out to be user error → close with the explanation.

**What not to do:** opening and instantly closing dozens of empty issues. GitHub’s
abuse detection and rate limits exist, and you gain nothing but a ban risk.

**How the toolkit tracks it:** the issue lab stamps creation time; on close it computes
the gap. Separately, `Get-QuickdrawEligibleEvents` searches your closed issues and
reports those whose `closed_at - created_at <= 5 minutes`.

---

## Pair Extraordinaire — 1 / 10 / 24 / 48 merged co-authored PRs

**Mechanic:** commits in the merged PR carry a trailer:

```
Co-authored-by: Real Name <their@email.tld>
```

GitHub links the commit (and the PR) to every co-author. The trailer must use an
email/id GitHub can match to an account.

**Honest path with a friend or colleague:**

1. Pair on something small (e.g. a tutorial in the learning repo).
2. Agree **before** committing to add the trailer — this is consent, not decoration.
3. Use their account-matched email. The toolkit derives the official noreply address
   (`<id>+<login>@users.noreply.github.com`) after you enter their username and it
   verifies they exist.
4. Open the PR, get it genuinely merged.

**What not to do:** inventing a collaborator; trailer-tagging people who didn’t code
with you; alt accounts; bot-accepted "co-authored" commits.

**How the toolkit tracks it:** scan of your N most recent merged PRs
(`pairExtraordinaire.maxMergedPrsToScan`, default 60) fetching each commit message and
matching the trailer needle you supply.

---

## Galaxy Brain — 2 / 8 / 16 / 32 accepted answers

**Mechanic:** in GitHub Discussions, the *asker* or a *maintainer* marks one answer as
the solution ("accepted answer"). The answer’s author (not the asker) is the one who
works toward this achievement.

**Honest path:**
1. Pick repositories in domains you know and contribute to them (tutorials in your
   learning repo are good training material).
2. Find an **unanswered** question you can answer *from real experience*.
3. Post a complete, tested answer. Include commands, versions, links to docs.
4. The asker/maintainer decides acceptance. You cannot — and the toolkit will not —
   mark your own answer accepted.

**Verification:** the toolkit queries
`repository(owner,name){ discussion(number){ answer { author { login } } } }` and counts
only answers whose `author.login` equals you. If no answer exists or it isn’t yours,
it is not counted.

**Finding places to answer:** your own repos with Discussions enabled, plus GitHub’s
unanswered-discussion search (the lab runs it, with a graceful fallback to
https://github.com/discussions).

---

## Starstruck — 16 / 128 / 512 / 4,096 stars (per repository tier thresholds, community-reported)

**What counts:** stars on a repository you own, at the tier thresholds above.

**Honest paths:**
- Solve one annoying problem well (a small but *finished* tool beats a grand unfinished one).
- README with a real screenshot, install in ≤ 3 commands, honest feature list.
- Add it to relevant awesome-lists via PR; post in communities where your audience
  already gathers (subreddits, Discords, forums) — with context, not drive-by links.
- Keep shipping: a maintained repo accumulates stars over months, not hours.

**What not to do:** star farms, alt-account swarms, buying stars, star-for-star
schemes. They get removed, and can get accounts flagged.

**How the toolkit tracks it:** `gh repo list --json stargazerCount` — actual numbers,
per repo, shown against the next threshold.

---

## YOLO — merge a PR without review (community-reported)

On your profile already (user-reported). If you want to understand it: it rewards
*merging* a pull request without review approval — useful when you own the repo and
it’s trivial, but it is not a habit to build in shared projects.

## Public Sponsor — sponsor a developer

External action: enroll in [GitHub Sponsors](https://github.com/sponsors) as a
sponsor of a developer you value. The toolkit cannot do this for you and never fakes
it — but it costs real money, so choose someone genuinely doing useful work.

## Retired — cannot be earned

- **Arctic Code Vault Contributor** — granted to repos in the 2020 GitHub Archive
  Program. Event over.
- **Mars 2020 Helicopter Contributor** — granted in 2021 for qualifying 2020 commits.
  Event over.

## Experimental — unreliable

- **Heart On Your Sleeve** — appeared in preview; rollout and criteria unclear. Treat
  as not reliably obtainable.
- **Open Sourcerer** — DEV-community award, not a stable GitHub achievement.

---

## Recommended order of attack for ArulAgnes

1. **Pull Shark → Bronze (16):** PR lab on the learning repo + typo/doc PRs in real projects.
2. **Quickdraw:** one legitimate same-session issue close (the lab times you).
3. **Galaxy Brain ×2:** two deep, verifiable answers in a community you know.
4. **Pair Extraordinaire ×1:** pair with a colleague on one real PR; add the trailer.
5. **Starstruck 16:** polish `github-learning-lab` or your best project; document it; share it honestly.
