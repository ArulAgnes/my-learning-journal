#Requires -Version 5.1
<#
.SYNOPSIS
    AchievementTracker.ps1 - trackers, calculators and the achievement
    eligibility reference for the GitHub achievements currently obtainable.
.DESCRIPTION
    Thresholds shown are community-reported; GitHub does not publish
    official criteria and they may change. "GitHub-confirmed" states are
    reported only when the API shows the underlying event (e.g. mergedAt).
    The Galaxy Brain and Pair Extraordinaire flows never fabricate people,
    answers or merges.
#>

# ---------------------------------------------------------------------------
# Pure tier calculators (no network; unit-tested in tests/)
# ---------------------------------------------------------------------------
function Get-TierInfo {
    <#
    .SYNOPSIS
        Generic tier calculator. Thresholds ascending. Returns tier info.
    #>
    param(
        [Parameter(Mandatory = $true)][int]$Count,
        [Parameter(Mandatory = $true)][int[]]$Thresholds,
        [Parameter(Mandatory = $true)][string[]]$TierNames
    )
    $tierIndex = -1
    for ($i = 0; $i -lt $Thresholds.Count; $i++) {
        if ($Count -ge $Thresholds[$i]) { $tierIndex = $i }
    }
    $current = 'None'
    if ($tierIndex -ge 0) { $current = $TierNames[$tierIndex] }
    $nextName = $null
    $nextThreshold = $null
    $nextIndex = $tierIndex + 1
    if ($nextIndex -lt $Thresholds.Count) {
        $nextName = $TierNames[$nextIndex]
        $nextThreshold = $Thresholds[$nextIndex]
    }
    $remaining = 0
    if ($null -ne $nextThreshold) { $remaining = $nextThreshold - $Count }
    $percent = 100
    if ($null -ne $nextThreshold) {
        $prev = 0
        if ($tierIndex -ge 0) { $prev = $Thresholds[$tierIndex] }
        $span = $nextThreshold - $prev
        if ($span -le 0) { $percent = 100 } else { $percent = [math]::Min(100, [math]::Floor((($Count - $prev) / $span) * 100)) }
    }
    return [pscustomobject]@{
        Count         = $Count
        CurrentTier   = $current
        NextTier      = $nextName
        NextThreshold = $nextThreshold
        Remaining     = $remaining
        Percent       = $percent
        MaxedOut      = ($null -eq $nextThreshold)
    }
}

function Get-PullSharkTier {
    param([Parameter(Mandatory = $true)][int]$MergedCount)
    return Get-TierInfo -Count $MergedCount -Thresholds @(2, 16, 128, 1024) -TierNames @('Pull Shark', 'Pull Shark Bronze', 'Pull Shark Silver', 'Pull Shark Gold')
}

function Get-StarstruckTier {
    param([Parameter(Mandatory = $true)][int]$Stars)
    return Get-TierInfo -Count $Stars -Thresholds @(16, 128, 512, 4096) -TierNames @('Starstruck', 'Starstruck Bronze', 'Starstruck Silver', 'Starstruck Gold')
}

function Get-PairExtraordinaireTier {
    param([Parameter(Mandatory = $true)][int]$CoAuthoredMerged)
    return Get-TierInfo -Count $CoAuthoredMerged -Thresholds @(1, 10, 24, 48) -TierNames @('Pair Extraordinaire', 'Pair Extraordinaire Bronze', 'Pair Extraordinaire Silver', 'Pair Extraordinaire Gold')
}

function Get-GalaxyBrainTier {
    param([Parameter(Mandatory = $true)][int]$AcceptedAnswers)
    $thresholds = @(2, 8, 16, 32)
    $names      = @('Galaxy Brain', 'Galaxy Brain Bronze', 'Galaxy Brain Silver', 'Galaxy Brain Gold')
    try { $thresholds = @((Get-ToolkitSettings).galaxyBrain.thresholds | ForEach-Object { [int]$_ }) } catch { }
    return Get-TierInfo -Count $AcceptedAnswers -Thresholds $thresholds -TierNames $names
}

# ---------------------------------------------------------------------------
# Pull Shark
# ---------------------------------------------------------------------------
function Show-PullSharkStatus {
    param([Parameter(Mandatory = $true)]$User)
    Write-Banner 'PULL SHARK TRACKER'
    Write-Info "Community-reported thresholds: 2 merged PRs -> initial, 16 -> Bronze, 128 -> Silver, 1,024 -> Gold."
    $count = Get-MergedPullRequestCount -Username $User.Login
    if ($null -eq $count) {
        Write-Fail 'Could not reach the GitHub search API. Showing no numbers rather than guessing.'
        return
    }
    $tier = Get-PullSharkTier -MergedCount $count
    Write-UI ''
    Write-UI "  QUALIFIYING MERGED PRs: $count" -Color 'White'
    if ($tier.CurrentTier -eq 'None') { Write-Warn 'No tier yet (need 2 merged PRs).' }
    else { Write-Success "Current tier: $($tier.CurrentTier)" }
    if ($tier.MaxedOut) {
        Write-Success 'Maximum known tier reached. Rare air.'
    } else {
        Write-Info "Next tier:    $($tier.NextTier) at $($tier.NextThreshold) merged PRs"
        Write-Info "Remaining:    $($tier.Remaining) qualifying PRs"
        Write-ProgressBar -Current ($tier.Count) -Target ([int]$tier.NextThreshold) -Label $tier.NextTier
    }
    Write-UI ''
    $recent = @(Get-RecentMergedPulls -Username $User.Login -Limit 10)
    if ($recent.Count -gt 0) {
        Write-Info 'Most recent merged PRs (via search API):'
        $lastDate = $null
        foreach ($pr in $recent) {
            $repo = ''
            if ($pr.repository_url) { $repo = ($pr.repository_url -replace '.*/repos/', '') }
            Write-UI ("    {0}  {1}" -f $repo, $pr.html_url) -Color 'Gray'
        }
        try { $lastDate = ($recent | ForEach-Object { [datetime]$_.closed_at } | Sort-Object -Descending | Select-Object -First 1) } catch { }
        $lastLog = (@(Get-ActivityLog) | Where-Object { $_.action -eq 'PR merged' -and $_.result -eq 'SUCCESS' } | Sort-Object { $_.timestamp } | Select-Object -Last 1)
        if ($lastLog) { Write-Info "Last merge confirmed by THIS toolkit: $(Format-IsoTimestamp $lastLog.timestamp)" }
        elseif ($lastDate) { Write-Info "Most recent merged PR close date (search API): $($lastDate.ToString('yyyy-MM-dd'))" }
    } else {
        Write-Info 'No merged PRs found for this account yet.'
    }
    Write-UI ''
    Write-Warn 'Numbers come from GitHub search and can lag or approximate. A PR counts when GitHub records it as merged.'
}

# ---------------------------------------------------------------------------
# Starstruck
# ---------------------------------------------------------------------------
function Get-StarstruckStatus {
    param([Parameter(Mandatory = $true)]$User)
    $repos = Get-MyRepositories
    if ($null -eq $repos) { return $null }
    $repos = @($repos)
    $total = 0
    $rows  = @()
    foreach ($r in $repos) {
        $stars = 0
        try { $stars = [int]$r.stargazerCount } catch { }
        $total += $stars
        $rows += [pscustomobject]@{ Name = $r.name; Stars = $stars; Url = $r.url; Private = [bool]$r.isPrivate }
    }
    return [pscustomobject]@{ Total = $total; Rows = @($rows | Sort-Object Stars -Descending) }
}

function Show-StarstruckStatus {
    param([Parameter(Mandatory = $true)]$User)
    Write-Banner 'STARSTRUCK TRACKER'
    Write-Info "Community-reported thresholds (per-repo stars drive GitHub's tiers): 16, 128, 512, 4,096."
    $status = Get-StarstruckStatus -User $User
    if ($null -eq $status) { Write-Fail 'Could not read star counts from the API.'; return }
    if ($status.Rows.Count -eq 0) { Write-Info 'No repositories found.'; return }

    Write-UI ''
    Write-UI '  REPOSITORY STAR COUNTS (actual, from the API)' -Color 'White'
    foreach ($row in $status.Rows) {
        $vis = if ($row.Private) { 'private' } else { 'public ' }
        Write-UI ("    {0,-40} {1}  {2,4} star(s)" -f $row.Name, $vis, $row.Stars) -Color 'Gray'
    }
    Write-UI ''
    $top = ($status.Rows | Select-Object -First 1)
    Write-Info "Highest-starred repo: $($top.Name) with $($top.Stars) stars"
    Write-Info "Total stars across all repos: $($status.Total)"
    Write-UI ''
    $perRepo = Get-StarstruckTier -Stars $top.Stars
    Write-UI "  PER-REPO TIER (best repo): $($perRepo.CurrentTier)" -Color 'White'
    if (-not $perRepo.MaxedOut) {
        Write-Info "Next tier: $($perRepo.NextTier) at $($perRepo.NextThreshold) stars (need $($perRepo.Remaining) more)"
        Write-ProgressBar -Current $perRepo.Count -Target ([int]$perRepo.NextThreshold) -Label $perRepo.NextTier
    } else {
        Write-Success 'Maximum known Starstruck tier reached.'
    }
    Write-UI ''
    Write-Warn 'GitHub does not publish official Starstruck mechanics (per-repo vs account-wide).'
    Write-Info 'Honest ways to grow stars: solve a real problem, write clear docs, package it well,'
    Write-Info 'share it where the audience for it already lives. Never buy stars or use fake engagement.'
}

# ---------------------------------------------------------------------------
# Pair Extraordinaire
# ---------------------------------------------------------------------------
function Test-Collaborator {
    param([Parameter(Mandatory = $true)][string]$Login)
    $data = Invoke-GhJson -Arguments @('api', "users/$Login")
    if ($null -eq $data) { return $null }
    if ([string]$data.type -ne 'User') { return $null }
    return [pscustomobject]@{
        Login   = [string]$data.login
        Id      = [int64]$data.id
        Profile = [string]$data.html_url
        NoreplyEmail = ('{0}+{1}@users.noreply.github.com' -f $data.id, $data.login)
    }
}

function Get-CoAuthoredMergedPulls {
    param(
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$CoAuthorNeedle,  # e.g. noreply email or name
        [int]$MaxScan = 60
    )
    $prs = @(Get-RecentMergedPulls -Username $Username -Limit $MaxScan)
    if ($null -eq $prs) { return [pscustomobject]@{ Ok = $false; Hits = @() } }
    $hits = @()
    foreach ($pr in $prs) {
        $repoFull = $null
        if ($pr.repository_url) { $repoFull = ($pr.repository_url -replace '.*/repos/', '') }
        if (-not $repoFull) { continue }
        $commits = Invoke-GhJson -Arguments @('api', "repos/$repoFull/pulls/$($pr.number)/commits", '--paginate', '--jq', '.[].commit.message')
        # Fallback for older gh without --jq: parse manually
        if ($null -eq $commits) {
            $raw = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('api', "repos/$repoFull/pulls/$($pr.number)/commits")
            if (-not $raw.Success) { continue }
            try { $commits = @((($raw.Output -join "`n") | ConvertFrom-Json) | ForEach-Object { $_.commit.message }) } catch { continue }
        }
        $joined = (@($commits) -join "`n")
        if ($joined -match [regex]::Escape($CoAuthorNeedle)) {
            $hits += [pscustomobject]@{
                Number = [int]$pr.number
                Repo   = $repoFull
                Url    = [string]$pr.html_url
                Title  = [string]$pr.title
            }
        }
    }
    return [pscustomobject]@{ Ok = $true; Hits = @($hits) }
}

function Invoke-PairExtraordinaireLab {
    param($Context)
    Write-Banner 'PAIR EXTRAORDINAIRE LAB'
    Write-Info 'Pair Extraordinaire rewards genuine collaboration committed with a Co-authored-by trailer.'
    Write-UI ''
    Write-UI '  Commit trailer format:' -Color 'White'
    Write-UI '      Co-authored-by: Collaborator Name <email@example.com>' -Color 'Gray'
    Write-UI ''
    Write-Warn 'Hard rules: the collaborator must be a real person, must agree to the trailer,'
    Write-Warn 'and the email must belong to them (their noreply email works).'
    Write-Warn 'Never invent a collaborator or co-author a fake identity.'
    Write-UI ''

    $login = Read-Host '  Collaborator GitHub username (leave empty for status only)'
    if ([string]::IsNullOrWhiteSpace($login)) {
        Show-PairExtraordinaireStatus -User $Context.User -CoAuthorNeedle ''
        return
    }

    $collab = Test-Collaborator -Login $login.Trim()
    if ($null -eq $collab) {
        Write-Fail "Could not verify a GitHub user named '$login'. Check the spelling."
        return
    }
    Write-Success "Verified collaborator: $($collab.Login)  ($($collab.Profile))"
    Write-Info "Their official noreply email: $($collab.NoreplyEmail)"
    Write-UI ''
    Write-Warn 'Before creating a co-authored commit you must have their agreement.'
    $consent = Read-YesNo "Has $($collab.Login) agreed to be co-author on the commit(s) you are about to make?" $false
    if (-not $consent) {
        Write-Info 'Stop here until they agree. Use the trailer only with consent.'
        return
    }
    Write-UI ''
    Write-UI '  When you commit with this trailer, your commit message should look like:' -Color 'White'
    Write-UI '' -Color 'Gray'
    Write-UI "      feat(lab): add batch tutorial`n`n      Co-authored-by: $($collab.Login) <$($collab.NoreplyEmail)>" -Color 'Gray'
    Write-UI ''
    Add-ActivityEntry -Action 'Collaborator verified' -Category 'PairExtraordinaire' -Result 'SUCCESS' -Detail "$($collab.Login) co-author consent confirmed"

    $scan = Read-YesNo 'Scan your recent merged PRs for co-authored commits now?' $true
    if ($scan) { Show-PairExtraordinaireStatus -User $Context.User -CoAuthorNeedle $collab.NoreplyEmail }
}

function Show-PairExtraordinaireStatus {
    param(
        [Parameter(Mandatory = $true)]$User,
        [string]$CoAuthorNeedle = ''
    )
    Write-Banner 'PAIR EXTRAORDINAIRE TRACKER'
    Write-Info 'Community-reported thresholds: 1, 10, 24, 48 merged co-authored PRs.'

    if ([string]::IsNullOrWhiteSpace($CoAuthorNeedle)) {
        $CoAuthorNeedle = Read-Host '  Co-author identity to search for (noreply email or full name; empty = skip scan)'
        if ([string]::IsNullOrWhiteSpace($CoAuthorNeedle)) {
            Write-Info 'No identity given; skipping commit scan.'
            $log = @(Get-ActivityLog) | Where-Object { $_.category -eq 'PairExtraordinaire' }
            Write-Info "Toolkit-recorded Pair Extraordinaire events: $($log.Count)"
            return
        }
    }

    $maxScan = 60
    try { $maxScan = [int](Get-ToolkitSettings).pairExtraordinaire.maxMergedPrsToScan } catch { }
    Write-Step "Scanning up to $maxScan of your most recent merged PRs for the trailer..."
    $scanResult = Get-CoAuthoredMergedPulls -Username $User.Login -CoAuthorNeedle $CoAuthorNeedle -MaxScan $maxScan
    if ($null -eq $scanResult -or -not $scanResult.Ok) { Write-Fail 'Search API unavailable right now.'; return }
    $hits = @($scanResult.Hits)
    Write-Info "Merged PRs containing '$CoAuthorNeedle': $($hits.Count)"
    foreach ($h in $hits) { Write-UI ("    [{0}] {1}  {2}" -f $h.Repo, $h.Url, $h.Title) -Color 'Gray' }

    $tier = Get-PairExtraordinaireTier -CoAuthoredMerged $hits.Count
    if ($tier.CurrentTier -eq 'None') { Write-Warn 'No tier yet (need 1 merged co-authored PR).' }
    else { Write-Success "Tier: $($tier.CurrentTier)" }
    if (-not $tier.MaxedOut) {
        Write-Info "Next: $($tier.NextTier) at $($tier.NextThreshold) (remaining $($tier.Remaining))"
        Write-ProgressBar -Current $tier.Count -Target ([int]$tier.NextThreshold) -Label $tier.NextTier
    }
    Write-Warn 'Scan depth is capped for API rate limits; increase pairExtraordinaire.maxMergedPrsToScan in settings.json for a deeper history.'
}

# ---------------------------------------------------------------------------
# Galaxy Brain
# ---------------------------------------------------------------------------
function Get-MyReposWithDiscussions {
    param([Parameter(Mandatory = $true)]$User)
    $repos = Get-MyRepositories
    if ($null -eq $repos) { return [pscustomobject]@{ Ok = $false; Hits = @() } }
    $repos = @($repos)
    $result = @()
    foreach ($r in $repos) {
        if ($r.isPrivate) { continue }
        $apiPath = "repos/$($User.Login)/$($r.name)"
        $data = Invoke-GhJson -Arguments @('api', $apiPath)
        if ($null -ne $data -and [bool]$data.has_discussions) {
            $result += [pscustomobject]@{ Name = $r.name; Url = $r.html_url }
        }
    }
    return [pscustomobject]@{ Ok = $true; Hits = @($result) }
}

function Search-UnansweredDiscussions {
    param([int]$Limit = 10)
    $query = 'query($q:String!,$n:Int!){ search(query:$q, type: DISCUSSION, first:$n){ discussionCount nodes { ... on Discussion { number title url repository { nameWithOwner } updatedAt } } } }'
    $search = 'is:unanswered'
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('api', 'graphql', '-f', "query=$query", '-f', "q=$search", '-F', "n=$Limit")
    if (-not $res.Success) {
        Write-Warn 'Discussion search failed. You can also browse https://github.com/discussions and pick repos you know.'
        return @()
    }
    try {
        $json = ($res.Output -join "`n") | ConvertFrom-Json
        return @($json.data.search.nodes)
    } catch {
        return @()
    }
}

function New-DiscussionAnswerDraft {
    param(
        [Parameter(Mandatory = $true)][string]$Question,
        [Parameter(Mandatory = $true)][string]$YourKnowledge
    )
    $draft = @"
## Short answer

$YourKnowledge

## Why it works this way

<explain the mechanism behind the answer you gave above - 3-6 sentences
based on what you actually know, with a small example if relevant>

## How to verify

<how the asker can check the answer themselves - commands, docs, links>

---
Draft for question:
$Question
"@
    return $draft
}

function Test-AcceptedDiscussionAnswer {
    <#
    .SYNOPSIS
        Verifies via GraphQL that a discussion has an accepted answer AND that
        the accepted answer's author is the given login. Returns $true/$false,
        or $null when unverifiable.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$ExpectedAuthor
    )
    $query = 'query($o:String!,$r:String!,$n:Int!){ repository(owner:$o,name:$r){ discussion(number:$n){ title answer { author { login } body } } } }'
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('api', 'graphql', '-f', "query=$query", '-f', "o=$Owner", '-f', "r=$Repo", '-F', "n=$Number")
    if (-not $res.Success) { return $null }
    try {
        $json = ($res.Output -join "`n") | ConvertFrom-Json
        $discussion = $json.data.repository.discussion
        if ($null -eq $discussion) { return $false }
        if ($null -eq $discussion.answer) { return $false } # not answered yet
        $author = [string]$discussion.answer.author.login
        return ($author -ieq $ExpectedAuthor)
    } catch {
        return $null
    }
}

function Invoke-GalaxyBrainLab {
    param($Context)
    Write-Banner 'GALAXY BRAIN LAB - genuinely helpful answers'
    Write-Info 'Galaxy Brain (community-reported): your answer in a GitHub Discussion is'
    Write-Info 'marked as the accepted answer. Reported tiers: 2, 8, 16, 32 accepted answers.'
    Write-UI ''
    Write-Warn 'You may never mark your own answer as accepted, and never ask friends to.'
    Write-Warn 'This lab helps you find real questions and draft answers YOU stand behind.'
    Write-UI ''

    Write-Step 'Your public repositories with Discussions enabled:'
    $discResult = Get-MyReposWithDiscussions -User $Context.User
    if ($null -eq $discResult -or -not $discResult.Ok) { Write-Warn 'Could not list repositories right now.' }
    else {
        $withDisc = @($discResult.Hits)
        if ($withDisc.Count -eq 0) {
        Write-Info 'None of your public repos has Discussions enabled.'
        Write-Info 'Enable it on a suitable repo: gh repo edit <repo> --enable-discussions  (or Settings > Features).'
    } else {
        foreach ($d in @($withDisc)) { Write-UI "    $($d.Name)  $($d.Url)" -Color 'Gray' }
        }
    }
    Write-UI ''
    Write-Step 'Unanswered discussions you might be able to answer (search API):'
    $unanswered = @(Search-UnansweredDiscussions -Limit 5)
    foreach ($n in $unanswered) {
        $repo = ''
        if ($n.repository) { $repo = [string]$n.repository.nameWithOwner }
        Write-UI ("    [{0}] #{1} {2}" -f $repo, $n.number, $n.title) -Color 'Gray'
        Write-UI ("         {0}" -f $n.url) -Color 'DarkGray'
    }
    if ($unanswered.Count -eq 0) { Write-Info 'Search returned nothing right now - browse https://github.com/discussions for topics you know.' }
    Write-UI ''

    if (Read-YesNo 'Draft an answer from your own knowledge now?' $false) {
        $q = Read-Host '  The question (paste it)'
        $k = Read-Host '  Your answer in one or two sentences'
        if ([string]::IsNullOrWhiteSpace($q) -or [string]::IsNullOrWhiteSpace($k)) {
            Write-Warn 'Draft cancelled - question and answer are required.'
        } else {
            $draft = New-DiscussionAnswerDraft -Question $q -YourKnowledge $k
            Write-Banner 'DRAFT (review and edit before posting)'
            Write-UI $draft -Color 'White'
            $save = Read-YesNo 'Save this draft into the toolkit data folder?' $true
            if ($save) {
                $file = Join-Path (Get-ToolkitRoot) ('data\draft-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.md')
                Write-FileSafe -Path $file -Content $draft | Out-Null
                Write-Success "Draft saved to $file"
            }
            Write-Info 'Post it manually on GitHub. Only the community/maintainer marks answers accepted.'
        }
    }
    Write-UI ''
    if (Read-YesNo 'Verify a discussion whose answer was accepted as YOURS?' $false) {
        $owner = Read-Host '  Repository owner'
        $repo  = Read-Host '  Repository name'
        $num   = Read-Host '  Discussion number'
        $numInt = 0
        if (-not [int]::TryParse($num, [ref]$numInt)) { Write-Warn 'Not a number; cancelled.'; return }
        $ok = Test-AcceptedDiscussionAnswer -Owner $owner -Repo $repo -Number $numInt -ExpectedAuthor $Context.User.Login
        if ($null -eq $ok) { Write-Warn 'Could not verify (API error or discussion not found).' }
        elseif ($ok) {
            Write-Success 'VERIFIED: the accepted answer author is YOU.'
            Add-ActivityEntry -Action 'Accepted answer verified' -Category 'GalaxyBrain' -Repository "$owner/$repo" -Result 'SUCCESS' -Detail "discussion #$numInt"
        } else {
            Write-Warn 'Either the discussion has no accepted answer yet, or the accepted answer is not yours. Not counting it.'
        }
    }
    Show-GalaxyBrainStatus -User $Context.User
}

function Show-GalaxyBrainStatus {
    param([Parameter(Mandatory = $true)]$User)
    Write-Banner 'GALAXY BRAIN TRACKER'
    Write-Info 'Community-reported thresholds: 2, 8, 16, 32 accepted answers.'
    $log = @(Get-ActivityLog) | Where-Object { $_.category -eq 'GalaxyBrain' -and $_.action -eq 'Accepted answer verified' }
    $count = $log.Count
    Write-Info "Accepted answers verified by this toolkit: $count"
    $tier = Get-GalaxyBrainTier -AcceptedAnswers $count
    if ($tier.CurrentTier -eq 'None') { Write-Warn 'No tier yet. Your first verified accepted answer is the start.' }
    else { Write-Success "Tier: $($tier.CurrentTier)" }
    if (-not $tier.MaxedOut) {
        Write-Info "Next: $($tier.NextTier) at $($tier.NextThreshold) (remaining $($tier.Remaining))"
        Write-ProgressBar -Current $tier.Count -Target ([int]$tier.NextThreshold) -Label $tier.NextTier
    }
    Write-Warn 'Local log only - GitHub does not expose a public "accepted answers by user" counter.'
    Write-Info 'Register each accepted answer via this lab so the tracker stays honest.'
}

# ---------------------------------------------------------------------------
# Achievement reference (eligibility honesty table)
# ---------------------------------------------------------------------------
function Show-AchievementReference {
    Write-Banner 'ACHIEVEMENT ELIGIBILITY REFERENCE'
    Write-UI '  STATUS KEY: UNLOCKED (GitHub shows it)  PROGRESS  WAITING  NOT ELIGIBLE  UNAVAILABLE' -Color 'DarkCyan'
    Write-UI ''
    Write-UI '  CONFIRMED OBTAINABLE (thresholds community-reported)' -Color 'White'
    $rows = @(
        @{ N = 'Pull Shark';           T = '2 / 16 / 128 / 1,024 merged PRs';         S = 'Available' },
        @{ N = 'Quickdraw';            T = 'Close an issue within 5 minutes';        S = 'Available' },
        @{ N = 'Pair Extraordinaire';  T = '1 / 10 / 24 / 48 merged co-authored PRs';S = 'Available - needs a real co-author' },
        @{ N = 'Galaxy Brain';         T = '2 / 8 / 16 / 32 accepted Discussion answers'; S = 'Available - needs community answers' },
        @{ N = 'Starstruck';           T = '16 / 128 / 512 / 4,096 stars';          S = 'Available - organic growth only' },
        @{ N = 'YOLO';                 T = 'Merge a PR without review (reported)';   S = 'Available - you already hold it' },
        @{ N = 'Public Sponsor';       T = 'Sponsor a developer via GitHub Sponsors';S = 'Available - external action, your choice' }
    )
    foreach ($r in $rows) { Write-UI ("    {0,-20} {1,-46} {2}" -f $r.N, $r.T, $r.S) -Color 'Gray' }

    Write-UI ''
    Write-UI '  RETIRED - CANNOT BE EARNED ANYMORE' -Color 'White'
    Write-UI '    Arctic Code Vault Contributor   (active 2020 archive event only)' -Color 'DarkGray'
    Write-UI '    Mars 2020 Helicopter Contributor (2020 event only)' -Color 'DarkGray'

    Write-UI ''
    Write-UI '  EXPERIMENTAL / UNRELIABLE' -Color 'White'
    Write-UI '    Heart On Your Sleeve  - experimental, rolled out unevenly, criteria unclear' -Color 'DarkGray'
    Write-UI '    Open Sourcerer        - DEV-community event awards, not a stable badge' -Color 'DarkGray'

    Write-UI ''
    Write-UI '  NOT REAL / SCAM WARNINGS' -Color 'White'
    Write-UI '    Any site or service selling achievements, stars or followers.' -Color 'Red'
    Write-UI '    Fake-star exchanges, alt-account merge farms, bot-accepted answers.' -Color 'Red'

    Write-UI ''
    Write-Warn 'GitHub publishes almost nothing official; counts above are community reports and may change.'
    Write-Info 'The toolkit tracks real API events and never reports a tier GitHub did not make possible.'
}

# ---------------------------------------------------------------------------
# Combined dashboard
# ---------------------------------------------------------------------------
function Show-AchievementDashboard {
    param($Context)
    Clear-Host
    Write-Banner "ACHIEVEMENT DASHBOARD - $($Context.User.Login)"
    Write-UI '  User-reported: YOLO + Pull Shark already on your profile.' -Color 'DarkCyan'
    Write-UI ''

    $count = Get-MergedPullRequestCount -Username $Context.User.Login
    if ($null -eq $count) { Write-Fail 'Pull Shark: merged-PR count unavailable (offline?).' }
    else {
        $tier = Get-PullSharkTier -MergedCount $count
        $line = "  Pull Shark        {0,4} merged PRs   tier: {1}" -f $count, $tier.CurrentTier
        if (-not $tier.MaxedOut) { $line += "   next: {0} @ {1} ({2} to go)" -f $tier.NextTier, $tier.NextThreshold, $tier.Remaining }
        elseif ($tier.CurrentTier -ne 'None') { $line += '   MAX TIER' }
        Write-UI $line -Color 'White'
    }

    $stars = Get-StarstruckStatus -User $Context.User
    if ($stars) {
        $top = ($stars.Rows | Select-Object -First 1)
        if ($top) { Write-UI ("  Starstruck        best repo '{0}': {1} stars   total across repos: {2}" -f $top.Name, $top.Stars, $stars.Total) -Color 'White' }
    }

    $qd = $null
    try { $qd = Get-QuickdrawEligibleEvents -Username $Context.User.Login -WindowMinutes 5 -Limit 20 } catch { }
    if ($null -ne $qd -and $qd.Ok) { Write-UI ("  Quickdraw         {0} fast-closed issue(s) found via search API" -f @($qd.Hits).Count) -Color 'White' }

    $pe = @(Get-ActivityLog) | Where-Object { $_.category -eq 'PairExtraordinaire' }
    Write-UI ("  Pair Extraordinaire  {0} toolkit-recorded verification event(s); run [8] guide for the scan" -f $pe.Count) -Color 'White'

    $gb = @(Get-ActivityLog) | Where-Object { $_.category -eq 'GalaxyBrain' -and $_.action -eq 'Accepted answer verified' }
    Write-UI ("  Galaxy Brain      {0} accepted answer(s) verified (local log)" -f $gb.Count) -Color 'White'

    Write-UI ''
    Write-Info 'YOLO: on your profile (user-reported).  Public Sponsor: needs GitHub Sponsors - menu [6] explains.'
    Write-Info "Achievement page: https://github.com/$($Context.User.Login)?tab=achievements"
    Write-UI ''
    Write-UI '  [1] Pull Shark details      [4] Pair Extraordinaire lab' -Color 'Gray'
    Write-UI '  [2] Quickdraw lab           [5] Galaxy Brain lab' -Color 'Gray'
    Write-UI '  [3] Starstruck details      [6] Achievement reference' -Color 'Gray'
    Write-UI '  [0] Back' -Color 'Gray'
    $choice = Read-MenuChoice -Prompt 'Choice' -ValidChoices 0, 1, 2, 3, 4, 5, 6
    switch ($choice) {
        1 { Show-PullSharkStatus -User $Context.User }
        2 { Invoke-QuickdrawLab -Context $Context }
        3 { Show-StarstruckStatus -User $Context.User }
        4 { Invoke-PairExtraordinaireLab -Context $Context }
        5 { Invoke-GalaxyBrainLab -Context $Context }
        6 { Show-AchievementReference }
        0 { }
    }
    if ($choice -ne 0) { Read-Host '  Press Enter to continue' }
}
