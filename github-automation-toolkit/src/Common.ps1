#Requires -Version 5.1
<#
.SYNOPSIS
    Common.ps1 - shared helpers for the GitHub Automation & Learning Lab.
.DESCRIPTION
    Dot-sourced by Main.ps1. Provides: paths, console UI helpers, external
    process invocation with $LASTEXITCODE checks, settings load/save,
    activity logging, secret scanning, safe file backup and HTML encoding.

    PowerShell 5.1 compatible. ASCII only. No credentials are ever stored.
#>

$script:ToolkitRoot   = Split-Path -Parent $PSScriptRoot
$script:ConfigPath    = Join-Path $script:ToolkitRoot 'config\settings.json'
$script:DataPath      = Join-Path $script:ToolkitRoot 'data'
$script:LogPath       = Join-Path $script:DataPath 'activity-log.json'
$script:ReportsPath   = Join-Path $script:ToolkitRoot 'reports'
$script:SettingsCache = $null

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
function Get-ToolkitRoot { return $script:ToolkitRoot }
function Get-ReportsPath { return $script:ReportsPath }

# ---------------------------------------------------------------------------
# Console UI helpers
# ---------------------------------------------------------------------------
function Write-UI {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Color = 'Gray'
    )
    Write-Host $Text -ForegroundColor $Color
}

function Write-Info    { param([string]$Text) Write-UI -Text "  [i] $Text" -Color 'Cyan' }
function Write-Success { param([string]$Text) Write-UI -Text "  [+] $Text" -Color 'Green' }
function Write-Warn    { param([string]$Text) Write-UI -Text "  [!] $Text" -Color 'Yellow' }
function Write-Fail    { param([string]$Text) Write-UI -Text "  [X] $Text" -Color 'Red' }
function Write-Step    { param([string]$Text) Write-UI -Text "  --> $Text" -Color 'White' }

function Write-Divider {
    param([string]$Char = '=', [int]$Width = 46)
    Write-UI ($Char * $Width) -Color 'DarkCyan'
}

function Write-Banner {
    param([string]$Title)
    Write-Divider
    Write-UI ("  " + $Title) -Color 'White'
    Write-Divider
}

function Write-ProgressBar {
    param(
        [int]$Current,
        [int]$Target,
        [string]$Label = ''
    )
    $pct = 0
    if ($Target -gt 0) { $pct = [math]::Min(100, [math]::Floor(($Current / $Target) * 100)) }
    $width  = 30
    $filled = [math]::Floor($width * $pct / 100)
    $bar    = ('#' * $filled) + ('-' * ($width - $filled))
    Write-UI ("  [{0}] {1,3}%  {2}/{3}  {4}" -f $bar, $pct, $Current, $Target, $Label) -Color 'Green'
}

# ---------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------
function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )
    $suffix = '[y/N]'
    if ($Default) { $suffix = '[Y/n]' }
    while ($true) {
        $answer = Read-Host "  $Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        switch -Regex ($answer.Trim().ToLowerInvariant()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Warn 'Please answer y or n.' }
        }
    }
}

function Read-MenuChoice {
    param(
        [string]$Prompt = 'Choose an option',
        [int[]]$ValidChoices
    )
    while ($true) {
        $raw = Read-Host "  $Prompt"
        if ([string]::IsNullOrWhiteSpace($raw)) { Write-Warn 'Enter a number.'; continue }
        $num = 0
        if ([int]::TryParse($raw.Trim(), [ref]$num)) {
            if ($null -eq $ValidChoices -or $ValidChoices -contains $num) { return $num }
            Write-Warn ("Valid choices: {0}" -f ($ValidChoices -join ', '))
        } else {
            Write-Warn 'Enter a number from the menu.'
        }
    }
}

# ---------------------------------------------------------------------------
# External process handling (with $LASTEXITCODE checks)
# ---------------------------------------------------------------------------
function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-ExternalCaptured {
    <#
    .SYNOPSIS
        Runs an external command, captures stdout+stderr as strings and
        checks $LASTEXITCODE. Never throws on non-zero exit; caller checks.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ''
    )
    $result = [pscustomobject]@{
        ExitCode = -1
        Output   = @()
        Success  = $false
    }
    try {
        $prev = $PWD
        if ($WorkingDirectory) { Push-Location $WorkingDirectory }
        $raw = & $FilePath @Arguments 2>&1
        $result.ExitCode = $LASTEXITCODE
        $result.Output   = @($raw | ForEach-Object { $_.ToString() })
        $result.Success  = ($result.ExitCode -eq 0)
        if ($WorkingDirectory) { Pop-Location }
        return $result
    } catch {
        try { if ($WorkingDirectory) { Pop-Location } } catch { }
        $result.Output   = @("EXCEPTION: $($_.Exception.Message)")
        $result.ExitCode = -1
        $result.Success  = $false
        return $result
    }
}

function Invoke-GhJson {
    <#
    .SYNOPSIS
        Calls gh and parses stdout as JSON. Returns $null and writes a warning
        on failure. Uses the ambient gh authentication; no tokens are read.
    #>
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments $Arguments
    if (-not $res.Success) {
        Write-Fail ("gh {0} failed (exit {1})" -f ($Arguments -join ' '), $res.ExitCode)
        foreach ($line in $res.Output) { Write-UI "        $line" -Color 'DarkRed' }
        return $null
    }
    $text = ($res.Output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        return $text | ConvertFrom-Json
    } catch {
        Write-Fail "gh returned output that was not valid JSON."
        return $null
    }
}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
function Get-ToolkitSettings {
    param([string]$Path = $script:ConfigPath)
    if ($script:SettingsCache -and $Path -eq $script:ConfigPath) { return $script:SettingsCache }
    if (-not (Test-Path $Path)) {
        throw "Settings file not found: $Path. Re-extract the toolkit ZIP or restore config\settings.json."
    }
    $raw = Get-Content -Raw -Path $Path -ErrorAction Stop
    try {
        $settings = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "config\settings.json is not valid JSON: $($_.Exception.Message)"
    }
    if ($Path -eq $script:ConfigPath) { $script:SettingsCache = $settings }
    return $settings
}

function Save-ToolkitSettings {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [string]$Path = $script:ConfigPath
    )
    if (Test-Path $Path) { Backup-FileSafe -Path $Path | Out-Null }
    $Settings | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
    $script:SettingsCache = $null
}

function Test-DryRun {
    try {
        $s = Get-ToolkitSettings
        return [bool]$s.dryRun
    } catch {
        return $true # fail safe: if settings are unreadable, behave as dry-run
    }
}

# ---------------------------------------------------------------------------
# Activity log (JSON array on disk)
# ---------------------------------------------------------------------------
function Get-ActivityLog {
    param([string]$Path = $script:LogPath)
    if (-not (Test-Path $Path)) { return @() }
    try {
        $raw = Get-Content -Raw -Path $Path -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($data -is [System.Array]) { return @($data) }
        if ($null -ne $data) { return @($data) }
        return @()
    } catch {
        Write-Warn "Activity log was unreadable ($($_.Exception.Message)). A backup copy will be kept."
        try { Backup-FileSafe -Path $Path | Out-Null } catch { }
        return @()
    }
}

function Add-ActivityEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$Category = 'General',
        [string]$Repository = '',
        [string]$Result = 'SUCCESS',
        [string]$Detail = '',
        [string]$Url = '',
        [string]$Path = $script:LogPath
    )
    $entries = @(Get-ActivityLog -Path $Path)
    $max = 1000
    try { $max = [int](Get-ToolkitSettings).logging.maxLogEntries } catch { }

    $entry = [ordered]@{
        timestamp  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        action     = $Action
        category   = $Category
        repository = $Repository
        result     = $Result
        detail     = $Detail
        url        = $Url
    }
    $entries += , $entry
    if ($entries.Count -gt $max) {
        $entries = $entries[($entries.Count - $max)..($entries.Count - 1)]
    }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $entries | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8
    return $entry
}

function Get-LastActivityDate {
    param([string]$Path = $script:LogPath)
    $entries = Get-ActivityLog -Path $Path
    if (@($entries).Count -eq 0) { return $null }
    $last = @($entries | Sort-Object { $_.timestamp } | Select-Object -Last 1)[0]
    return $last.timestamp
}

# ---------------------------------------------------------------------------
# Safe file handling
# ---------------------------------------------------------------------------
function Backup-FileSafe {
    <#
    .SYNOPSIS
        Copies a file into a .backups folder next to it with a timestamp.
        Returns the backup path, or $null when the source does not exist.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $dir  = Split-Path -Parent $Path
    $name = Split-Path -Leaf $Path
    $backupRoot = Join-Path $dir '.backups'
    if (-not (Test-Path $backupRoot)) { New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null }
    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = Join-Path $backupRoot ("{0}.{1}.bak" -f $name, $stamp)
    Copy-Item -Path $Path -Destination $target -Force
    return $target
}

function Write-FileSafe {
    <#
    .SYNOPSIS
        Writes text to $Path. If the file exists it is backed up first
        (unless -Force without backup is explicitly requested via -NoBackup).
        Never silently overwrites existing content.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [switch]$NoBackup
    )
    if ((Test-Path $Path) -and -not $NoBackup) {
        $backup = Backup-FileSafe -Path $Path
        if ($backup) { Write-Info "Existing file backed up to $backup" }
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $Path -Value $Content -Encoding UTF8
    return $Path
}

# ---------------------------------------------------------------------------
# Secret scanning - used before every commit the toolkit makes
# ---------------------------------------------------------------------------
function Test-SecretScan {
    <#
    .SYNOPSIS
        Scans files for credential-looking content.
        Returns an array of findings (empty when clean).
    #>
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths
    )
    $findings   = @()
    $nameBlock  = @('.env', '.env.*', '*.pem', '*.key', '*.p12', '*.pfx', 'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519', 'credentials', 'credentials.*', '.npmrc', '.pypirc')
    $patterns   = @(
        ('ghp' + '_[A-Za-z0-9]{20,}'),
        ('github' + '_pat_[A-Za-z0-9_]{20,}'),
        ('gho' + '_[A-Za-z0-9]{20,}'),
        ('ghs' + '_[A-Za-z0-9]{20,}'),
        ('AKIA' + '[0-9A-Z]{16}'),
        ('xox[baprs]-' + '[A-Za-z0-9-]{10,}'),
        '-{5}BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-{5}',
        '(?i)(api[_-]?key|client[_-]?secret|access[_-]?token|secret[_-]?key)\s*[:=]\s*["'']?[A-Za-z0-9_\-\./+]{12,}'
    )

    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) { continue }
        $item = Get-Item $p -ErrorAction SilentlyContinue
        if ($null -eq $item -or $item.PSIsContainer) { continue }

        foreach ($block in $nameBlock) {
            if ($item.Name -like $block) {
                $findings += [pscustomobject]@{ File = $p; Reason = "File name matches blocked pattern '$block'" }
            }
        }
        if ($item.Length -gt 1MB) { continue } # too large to scan reliably
        try {
            $content = Get-Content -Raw -Path $p -ErrorAction Stop
        } catch {
            continue # binary or unreadable: skip content scan, name scan already applied
        }
        foreach ($pattern in $patterns) {
            if ($content -match $pattern) {
                $findings += [pscustomobject]@{ File = $p; Reason = "Content matches secret pattern: $pattern" }
            }
        }
    }
    return $findings
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
function ConvertTo-HtmlSafe {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text
    $t = $t.Replace('&', '&amp;')
    $t = $t.Replace('<', '&lt;')
    $t = $t.Replace('>', '&gt;')
    $t = $t.Replace('"', '&quot;')
    $t = $t.Replace("'", '&#39;')
    return $t
}

function Open-WebPage {
    param([string]$Url)
    try {
        if ($env:OS -eq 'Windows_NT') {
            Start-Process $Url
        } elseif (Test-CommandExists 'xdg-open') {
            & xdg-open $Url | Out-Null
        } elseif (Test-CommandExists 'open') {
            & open $Url | Out-Null
        }
        return $true
    } catch {
        Write-Warn "Could not open a browser. Visit manually: $Url"
        return $false
    }
}

function Format-IsoTimestamp {
    param([string]$Value)
    try { return ([datetime]$Value).ToString('yyyy-MM-dd HH:mm') } catch { return $Value }
}

function Initialize-ToolkitData {
    if (-not (Test-Path $script:DataPath)) { New-Item -ItemType Directory -Force -Path $script:DataPath | Out-Null }
    if (-not (Test-Path $script:ReportsPath)) { New-Item -ItemType Directory -Force -Path $script:ReportsPath | Out-Null }
    if (-not (Test-Path $script:LogPath)) { Set-Content -Path $script:LogPath -Value '[]' -Encoding UTF8 }
}
