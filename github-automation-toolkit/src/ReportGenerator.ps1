#Requires -Version 5.1
<#
.SYNOPSIS
    ReportGenerator.ps1 - generates a self-contained HTML progress report.
.DESCRIPTION
    Reads live GitHub data where possible (merged PR count, stars) and the
    local activity log otherwise, and writes reports/achievement-report-*.html.
    No external resources; safe to open offline. Pass -UseCachedDataOnly to
    skip every network call (used by the automated tests).
#>

$script:StatusMeta = @{
    'UNLOCKED'    = @{ Color = '#1a7f37'; Background = '#dafbe1'; Label = 'UNLOCKED' }
    'PROGRESS'    = @{ Color = '#9a6700'; Background = '#fff8c5'; Label = 'PROGRESS' }
    'WAITING'     = @{ Color = '#8250df'; Background = '#fbefff'; Label = 'WAITING' }
    'NOT ELIGIBLE'= @{ Color = '#cf222e'; Background = '#ffebe9'; Label = 'NOT ELIGIBLE' }
    'UNAVAILABLE' = @{ Color = '#57606a'; Background = '#f6f8fa'; Label = 'UNAVAILABLE' }
}

function New-StatusChip {
    param([Parameter(Mandatory = $true)][string]$Status)
    $meta = $script:StatusMeta[$Status]
    if ($null -eq $meta) { $meta = $script:StatusMeta['UNAVAILABLE'] }
    return ('<span class="chip" style="color:{0};background:{1}">{2}</span>' -f $meta.Color, $meta.Background, $meta.Label)
}

function New-HtmlProgressReport {
    param(
        $Context,
        [string]$OutputFolder = '',
        [switch]$UseCachedDataOnly
    )
    if ([string]::IsNullOrWhiteSpace($OutputFolder)) { $OutputFolder = Get-ReportsPath }
    if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null }

    $settings = $null
    try { $settings = Get-ToolkitSettings } catch { }

    # --- Gather data (tolerant of network failure) -----------------------
    $login = 'ArulAgnes'
    if ($Context -and $Context.User) { $login = $Context.User.Login }

    $mergedCount = $null
    $starRows    = $null
    $totalStars  = $null
    $repos       = $null

    if (-not $UseCachedDataOnly) {
        $mergedCount = Get-MergedPullRequestCount -Username $login
        $starStatus  = Get-StarstruckStatus -User ([pscustomobject]@{ Login = $login })
        if ($starStatus) {
            $starRows   = @($starStatus.Rows)
            $totalStars = $starStatus.Total
            $repos      = $starRows
        }
    }

    $logEntries  = @(Get-ActivityLog)
    $lastActivity = Get-LastActivityDate

    # --- Pull Shark progress ---------------------------------------------
    $pullSharkHtml = '<p class="muted">Merged-PR count unavailable (offline or API error).</p>'
    if ($null -ne $mergedCount) {
        $tier = Get-PullSharkTier -MergedCount $mergedCount
        $next = 'MAX TIER'
        if (-not $tier.MaxedOut) { $next = ('{0} at {1} merged PRs ({2} to go)' -f $tier.NextTier, $tier.NextThreshold, $tier.Remaining) }
        $pullSharkHtml = @"
<table class="kv">
<tr><th>Qualifying merged PRs</th><td><strong>$mergedCount</strong></td></tr>
<tr><th>Current tier</th><td>$(ConvertTo-HtmlSafe $tier.CurrentTier)</td></tr>
<tr><th>Next tier</th><td>$(ConvertTo-HtmlSafe $next)</td></tr>
<tr><th>Progress</th><td><div class="bar"><div class="fill" style="width:$($tier.Percent)%"></div></div><span class="muted">$($tier.Percent)%</span></td></tr>
</table>
"@
    }

    # --- Quickdraw history ------------------------------------------------
    $qdLog = @($logEntries | Where-Object { $_.category -eq 'Quickdraw' })
    $quickdrawHtml = '<p class="muted">No Quickdraw-eligible events recorded yet by this toolkit.</p>'
    if ($qdLog.Count -gt 0) {
        $items = ($qdLog | ForEach-Object {
            '<li><code>{0}</code> {1} - {2}</li>' -f (ConvertTo-HtmlSafe (Format-IsoTimestamp $_.timestamp)), (ConvertTo-HtmlSafe $_.action), (ConvertTo-HtmlSafe $_.detail)
        }) -join "`n"
        $quickdrawHtml = "<ul>$items</ul>"
    }

    # --- Co-authored PR history -------------------------------------------
    $peLog = @($logEntries | Where-Object { $_.category -eq 'PairExtraordinaire' })
    $pairHtml = '<p class="muted">No collaborator verifications or co-authored merges recorded yet.</p>'
    if ($peLog.Count -gt 0) {
        $items = ($peLog | ForEach-Object {
            '<li><code>{0}</code> {1} - {2}</li>' -f (ConvertTo-HtmlSafe (Format-IsoTimestamp $_.timestamp)), (ConvertTo-HtmlSafe $_.action), (ConvertTo-HtmlSafe $_.detail)
        }) -join "`n"
        $pairHtml = "<ul>$items</ul>"
    }

    # --- Galaxy Brain -------------------------------------------------------
    $gbLog = @($logEntries | Where-Object { $_.category -eq 'GalaxyBrain' })
    $verifiedAnswers = @($gbLog | Where-Object { $_.action -eq 'Accepted answer verified' }).Count
    $galaxyHtml = '<p class="muted">No accepted answers verified yet.</p>'
    if ($gbLog.Count -gt 0) {
        $items = ($gbLog | ForEach-Object {
            '<li><code>{0}</code> {1} - {2}</li>' -f (ConvertTo-HtmlSafe (Format-IsoTimestamp $_.timestamp)), (ConvertTo-HtmlSafe $_.action), (ConvertTo-HtmlSafe $_.detail)
        }) -join "`n"
        $galaxyHtml = "<p><strong>$verifiedAnswers</strong> accepted answer(s) verified.</p><ul>$items</ul>"
    }

    # --- Repositories + stars ---------------------------------------------
    $repoHtml = '<p class="muted">Repository data unavailable.</p>'
    if ($null -ne $repos) {
        $rowsHtml = ($repos | ForEach-Object {
            $vis = if ($_.Private) { 'private' } else { 'public' }
            '<tr><td><a href="{0}">{1}</a></td><td>{2}</td><td>{3}</td></tr>' -f (ConvertTo-HtmlSafe $_.Url), (ConvertTo-HtmlSafe $_.Name), $vis, $_.Stars
        }) -join "`n"
        $repoHtml = "<table class=`"data`"><thead><tr><th>Repository</th><th>Visibility</th><th>Stars</th></tr></thead><tbody>$rowsHtml</tbody></table><p class=`"muted`">Total stars: <strong>$totalStars</strong></p>"
    }

    # --- Recent activity ---------------------------------------------------
    $recentActivity = @($logEntries | Sort-Object { $_.timestamp } -Descending | Select-Object -First 15)
    $activityHtml = '<p class="muted">No recorded activity yet. Run the labs and come back.</p>'
    if ($recentActivity.Count -gt 0) {
        $items = ($recentActivity | ForEach-Object {
            $badge = if ([string]$_.result -eq 'SUCCESS') { 'ok' } elseif ([string]$_.result -eq 'FAILED') { 'bad' } else { 'note' }
            '<li><span class="dot {0}"></span><code>{1}</code> <strong>{2}</strong> {3}{4}</li>' -f $badge, (ConvertTo-HtmlSafe (Format-IsoTimestamp $_.timestamp)), (ConvertTo-HtmlSafe $_.action), (ConvertTo-HtmlSafe $_.detail), $(if ($_.url) { ' <a href="' + (ConvertTo-HtmlSafe $_.url) + '">link</a>' } else { '' })
        }) -join "`n"
        $activityHtml = "<ul class=`"timeline`">$items</ul>"
    }

    # --- Eligibility table -------------------------------------------------
    $yolo = New-StatusChip 'UNLOCKED'
    $sponsor = New-StatusChip 'NOT ELIGIBLE'
    $arctic = New-StatusChip 'UNAVAILABLE'
    $mars   = New-StatusChip 'UNAVAILABLE'
    $heart  = New-StatusChip 'UNAVAILABLE'
    $psTier = Get-PullSharkTier -MergedCount $(if ($null -ne $mergedCount) { $mergedCount } else { 0 })
    $pullSharkState = New-StatusChip $(if ($null -eq $mergedCount) { 'UNAVAILABLE' } elseif ($psTier.CurrentTier -ne 'None') { 'PROGRESS' } else { 'PROGRESS' })
    $quickdrawState = New-StatusChip $(if ($qdLog.Count -gt 0) { 'PROGRESS' } else { 'NOT ELIGIBLE' })
    $pairState      = New-StatusChip $(if ($peLog.Count -gt 0) { 'PROGRESS' } else { 'NOT ELIGIBLE' })
    $galaxyState    = New-StatusChip $(if ($verifiedAnswers -gt 0) { 'PROGRESS' } else { 'NOT ELIGIBLE' })
    $starState      = New-StatusChip $(if ($null -eq $totalStars) { 'UNAVAILABLE' } elseif ($totalStars -ge 16) { 'PROGRESS' } else { 'NOT ELIGIBLE' })

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $fileStamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $reportPath = Join-Path $OutputFolder "achievement-report-$fileStamp.html"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GitHub Achievement Progress - $(ConvertTo-HtmlSafe $login)</title>
<style>
:root { --ink:#1f2328; --muted:#57606a; --line:#d0d7de; --accent:#0b7285; --bg:#ffffff; }
body { font-family: 'Segoe UI', system-ui, -apple-system, sans-serif; color: var(--ink); background: var(--bg); margin: 0; line-height: 1.5; }
header { background: #0d1117; color: #e6edf3; padding: 2.2rem 1.5rem; }
header h1 { margin: 0 0 .35rem; font-size: 1.6rem; letter-spacing: .2px; }
header p { margin: .15rem 0; color: #9da7b3; font-size: .95rem; }
header a { color: #58a6ff; text-decoration: none; }
main { max-width: 1060px; margin: 0 auto; padding: 1.5rem; }
h2 { font-size: 1.15rem; border-bottom: 2px solid var(--line); padding-bottom: .35rem; margin-top: 2rem; color: var(--accent); text-transform: uppercase; letter-spacing: 1px; }
.chip { display: inline-block; padding: .1rem .55rem; border-radius: 999px; font-size: .72rem; font-weight: 700; letter-spacing: .4px; }
.kv, .data { width: 100%; border-collapse: collapse; margin: .5rem 0 1rem; }
.kv th { text-align: left; width: 260px; color: var(--muted); font-weight: 600; padding: .3rem .5rem; }
.kv td { padding: .3rem .5rem; border-bottom: 1px solid var(--line); }
.data th { text-align: left; background: #f6f8fa; padding: .4rem .5rem; border-bottom: 2px solid var(--line); }
.data td { padding: .4rem .5rem; border-bottom: 1px solid var(--line); }
.bar { background: #eaeef2; border-radius: 999px; height: 14px; width: 320px; max-width: 100%; overflow: hidden; display: inline-block; vertical-align: middle; }
.fill { background: linear-gradient(90deg, #0b7285, #2da44e); height: 100%; }
.muted { color: var(--muted); }
.timeline { list-style: none; padding-left: 0; }
.timeline li { padding: .28rem 0; border-bottom: 1px dashed var(--line); }
.dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: .45rem; }
.dot.ok { background: #2da44e; } .dot.bad { background: #cf222e; } .dot.note { background: #8250df; }
.notice { background: #fff8c5; border: 1px solid #d4a72c; border-radius: 8px; padding: .6rem .8rem; font-size: .9rem; }
footer { color: var(--muted); font-size: .8rem; border-top: 1px solid var(--line); margin-top: 2rem; padding: 1rem 0 2rem; }
code { background: #f6f8fa; border-radius: 4px; padding: .05rem .3rem; }
a { color: #0969da; }
@media print { header { background: #fff; color: #000; border-bottom: 3px solid #000; } }
</style>
</head>
<body>
<header>
  <h1>GitHub Achievement Progress Report</h1>
  <p><strong>Account:</strong> $(ConvertTo-HtmlSafe $login) &middot; <a href="https://github.com/$(ConvertTo-HtmlSafe $login)">github.com/$(ConvertTo-HtmlSafe $login)</a> &middot; <a href="https://github.com/$(ConvertTo-HtmlSafe $login)?tab=achievements">achievements</a></p>
  <p><strong>Generated:</strong> $timestamp (local time) &middot; Toolkit: GitHub Automation &amp; Learning Lab v1.0.0</p>
</header>
<main>

<div class="notice"><strong>How to read this report.</strong> GitHub does not publish official achievement criteria; thresholds below are community-reported and may change. <strong>UNLOCKED</strong> = GitHub shows the badge. <strong>PROGRESS</strong> = genuine qualifying activity exists. <strong>WAITING</strong> = external action or GitHub processing required. <strong>NOT ELIGIBLE</strong> = requirements not met. <strong>UNAVAILABLE</strong> = cannot currently be earned.</div>

<h2>Account summary</h2>
<table class="kv">
<tr><th>GitHub account</th><td>$(ConvertTo-HtmlSafe $login)</td></tr>
<tr><th>Expected account</th><td>$(if ($settings) { ConvertTo-HtmlSafe $settings.expectedGitHubUsername } else { 'ArulAgnes' })</td></tr>
<tr><th>Last recorded toolkit activity</th><td>$(ConvertTo-HtmlSafe $(if ($lastActivity) { Format-IsoTimestamp $lastActivity } else { 'none yet' }))</td></tr>
<tr><th>Total toolkit log entries</th><td>$($logEntries.Count)</td></tr>
</table>

<h2>Pull Shark</h2>
$pullSharkHtml

<h2>Quickdraw history</h2>
$quickdrawHtml

<h2>Pair Extraordinaire (co-authored PRs)</h2>
$pairHtml

<h2>Galaxy Brain (accepted answers)</h2>
$galaxyHtml

<h2>Repositories &amp; stars</h2>
$repoHtml

<h2>Achievement eligibility</h2>
<table class="data">
<thead><tr><th>Achievement</th><th>Reported requirement</th><th>Status</th></tr></thead>
<tbody>
<tr><td>Pull Shark</td><td>2 / 16 / 128 / 1,024 merged PRs</td><td>$pullSharkState</td></tr>
<tr><td>Quickdraw</td><td>Close an issue within 5 minutes</td><td>$quickdrawState</td></tr>
<tr><td>Pair Extraordinaire</td><td>1 / 10 / 24 / 48 merged co-authored PRs</td><td>$pairState</td></tr>
<tr><td>Galaxy Brain</td><td>2 / 8 / 16 / 32 accepted answers</td><td>$galaxyState</td></tr>
<tr><td>Starstruck</td><td>16 / 128 / 512 / 4,096 stars</td><td>$starState</td></tr>
<tr><td>YOLO</td><td>Merge a PR without review (reported)</td><td>$yolo</td></tr>
<tr><td>Public Sponsor</td><td>Sponsor a developer via GitHub Sponsors</td><td>$sponsor</td></tr>
<tr><td>Arctic Code Vault Contributor</td><td>Retired 2020 event</td><td>$arctic</td></tr>
<tr><td>Mars 2020 Helicopter Contributor</td><td>Retired 2020 event</td><td>$mars</td></tr>
<tr><td>Heart On Your Sleeve</td><td>Experimental / unreliable rollout</td><td>$heart</td></tr>
</tbody>
</table>

<h2>Recent activity (latest 15)</h2>
$activityHtml

<footer>
Generated locally by the GitHub Automation &amp; Learning Lab. No tokens or credentials are embedded in this file.
Thresholds are community-reported. Verify achievements on your
<a href="https://github.com/$(ConvertTo-HtmlSafe $login)?tab=achievements">achievements tab</a>.
</footer>

</main>
</body>
</html>
"@

    $html | Set-Content -Path $reportPath -Encoding UTF8
    Add-ActivityEntry -Action 'HTML report generated' -Category 'Report' -Result 'SUCCESS' -Detail $reportPath
    return $reportPath
}

function Invoke-ReportGenerator {
    param($Context)
    Write-Banner 'GENERATE HTML PROGRESS REPORT'
    $path = New-HtmlProgressReport -Context $Context
    Write-Success "Report written to: $path"
    if (Read-YesNo 'Open the report in your browser now?' $true) { Open-WebPage $path | Out-Null }
}
