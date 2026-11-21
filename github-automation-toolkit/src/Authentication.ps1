#Requires -Version 5.1
<#
.SYNOPSIS
    Authentication.ps1 - environment checks and GitHub sign-in.
.DESCRIPTION
    Verifies Windows, PowerShell, Git, GitHub CLI and winget. Signs the user
    in with `gh auth login` (browser device flow) when needed, reads the
    authenticated account and compares it with the expected username from
    config\settings.json. Never stores passwords or tokens.
#>

function Get-GitVersionText {
    $res = Invoke-ExternalCaptured -FilePath 'git' -Arguments @('--version')
    if ($res.Success -and $res.Output.Count -gt 0) { return $res.Output[0] }
    return $null
}

function Get-GhVersionText {
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('--version')
    if ($res.Success -and $res.Output.Count -gt 0) { return $res.Output[0] }
    return $null
}

function Get-WingetVersionText {
    $res = Invoke-ExternalCaptured -FilePath 'winget' -Arguments @('--version')
    if ($res.Success -and $res.Output.Count -gt 0) { return $res.Output[0] }
    return $null
}

function Test-WingetAvailable { return Test-CommandExists 'winget' }
function Test-GitInstalled    { return Test-CommandExists 'git' }
function Test-GhInstalled     { return Test-CommandExists 'gh' }

function Show-EnvironmentStatus {
    Write-Banner 'ENVIRONMENT CHECK'
    $win = "Unknown"
    if ($env:OS -eq 'Windows_NT') { $win = 'Windows' }
    Write-Info "OS:           $win ($([System.Runtime.InteropServices.RuntimeInformation]::OSDescription))"
    Write-Info "PowerShell:   $($PSVersionTable.PSVersion)"
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Fail 'PowerShell 5.1 or later is required.'
        return $false
    }
    $git = Get-GitVersionText
    if ($git) { Write-Success "Git:          $git" } else { Write-Fail 'Git:          NOT FOUND' }
    $gh = Get-GhVersionText
    if ($gh)  { Write-Success "GitHub CLI:   $gh" } else { Write-Fail 'GitHub CLI:   NOT FOUND' }
    $winget = Get-WingetVersionText
    if ($winget) { Write-Info "winget:       $winget" } else { Write-Warn 'winget:       not available (manual install guide will be shown if needed)' }
    return [bool]($git -and $gh)
}

function Install-ToolWithWinget {
    <#
    .SYNOPSIS
        Offers to install a missing tool. Returns $true on success (or when
        the tool becomes available after install). Honors dry-run.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$WingetId,
        [Parameter(Mandatory = $true)][string]$FriendlyName,
        [Parameter(Mandatory = $true)][string]$CommandName
    )
    Write-Warn "$FriendlyName is not installed."
    if (-not (Test-WingetAvailable)) {
        Write-Fail 'winget is not available on this machine, so automatic install is not possible.'
        Write-Info 'Install it manually instead:'
        if ($CommandName -eq 'git') {
            Write-UI '        Git:        https://git-scm.com/download/win' -Color 'Gray'
        } else {
            Write-UI '        GitHub CLI: https://cli.github.com/  (or: winget install --id GitHub.cli)' -Color 'Gray'
        }
        return $false
    }
    if (-not (Read-YesNo "Install $FriendlyName now with winget?" $true)) {
        Write-Warn "Skipping install of $FriendlyName."
        return $false
    }
    if (Test-DryRun) {
        Write-Info "[DRY-RUN] Would run: winget install --id $WingetId --exact --accept-source-agreements --accept-package-agreements"
        return $false
    }
    $res = Invoke-ExternalCaptured -FilePath 'winget' -Arguments @(
        'install', '--id', $WingetId, '--exact',
        '--accept-source-agreements', '--accept-package-agreements'
    )
    foreach ($line in $res.Output) { Write-UI "        $line" -Color 'DarkGray' }
    if (-not $res.Success) {
        Write-Fail "winget install of $FriendlyName failed (exit $($res.ExitCode)). See INSTALLATION.md."
        return $false
    }
    Write-Success "$FriendlyName installed. You may need to open a NEW window for PATH changes to apply."
    # PATH of the current process does not refresh automatically; probe common locations too.
    if (Test-CommandExists $CommandName) { return $true }
    $freshPath = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:PATH  = $freshPath
    return (Test-CommandExists $CommandName)
}

function Test-GhAuthentication {
    <#
    .SYNOPSIS
        Returns $true when `gh auth status` exits 0 (signed in), else $false.
    #>
    $res = Invoke-ExternalCaptured -FilePath 'gh' -Arguments @('auth', 'status')
    if ($res.Success) {
        foreach ($line in $res.Output) { Write-UI "        $line" -Color 'DarkGray' }
        return $true
    }
    return $false
}

function Connect-GitHubAccount {
    Write-Banner 'GITHUB SIGN-IN'
    Write-Info 'Your browser will open and GitHub will show a device code (https://github.com/login/device).'
    Write-Info 'The toolkit never sees your password or any token. gh stores its own credentials securely.'
    if (Test-DryRun) {
        Write-Info '[DRY-RUN] Would run: gh auth login --web -h github.com -p https'
        return $false
    }
    & gh auth login --web -h github.com -p https 2>&1 | ForEach-Object { Write-UI "        $_" -Color 'DarkGray' }
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Fail "gh auth login did not complete (exit $code)."
        return $false
    }
    Add-ActivityEntry -Action 'gh auth login' -Category 'Auth' -Result 'SUCCESS' -Detail 'Browser-based sign-in completed'
    return $true
}

function Get-AuthenticatedGitHubUser {
    <#
    .SYNOPSIS
        Returns the signed-in account as a custom object, or $null on failure.
    #>
    $user = Invoke-GhJson -Arguments @('api', 'user')
    if ($null -eq $user) { return $null }
    return [pscustomobject]@{
        Login   = [string]$user.login
        Name    = [string]$user.name
        Profile = [string]$user.html_url
        Id      = [int64]$user.id
        Type    = [string]$user.type
    }
}

function Confirm-ExpectedAccount {
    <#
    .SYNOPSIS
        Compares the authenticated account with expectedGitHubUsername.
        Returns $true when the user wants to continue with the account.
    #>
    param([Parameter(Mandatory = $true)]$User)
    $expected = 'ArulAgnes'
    try { $expected = (Get-ToolkitSettings).expectedGitHubUsername } catch { }

    Write-Banner 'ACCOUNT VERIFICATION'
    Write-Info "Authenticated as: $($User.Login)"
    if ($User.Name) { Write-Info "Display name:     $($User.Name)" }
    Write-Info "Profile:          $($User.Profile)"

    $matches = ($User.Login -ieq $expected)
    if ($matches) {
        Write-Success "This matches the configured account ($expected)."
        Add-ActivityEntry -Action 'Account verified' -Category 'Auth' -Result 'SUCCESS' -Detail $User.Login
        return $true
    }
    Write-Warn "The configured account is '$expected' but you are signed in as '$($User.Login)'."
    Write-Warn 'Achievements and progress will be tracked for the SIGNED-IN account.'
    return (Read-YesNo "Continue as $($User.Login)?" $false)
}

function Invoke-StartupSequence {
    <#
    .SYNOPSIS
        The full automatic startup (steps 1-12 of the toolkit specification).
        Returns a context object on success, or $null when the user must abort.
    #>
    Write-Banner 'GITHUB AUTOMATION & LEARNING LAB - STARTUP'

    # Step 1: Windows + PowerShell
    Write-Step 'Step 1/9  Checking Windows and PowerShell...'
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Fail 'PowerShell 5.1 or newer is required.'
        return $null
    }
    Write-Success "PowerShell $($PSVersionTable.PSVersion) on $(if ($env:OS -eq 'Windows_NT') {'Windows'} else {'non-Windows (development host)'})."

    # Step 2 + 3: tools
    Write-Step 'Step 2/9  Checking Git installation...'
    $gitOk = Test-GitInstalled
    if ($gitOk) { Write-Success "Git found: $(Get-GitVersionText)" }

    Write-Step 'Step 3/9  Checking GitHub CLI installation...'
    $ghOk = Test-GhInstalled
    if ($ghOk) { Write-Success "GitHub CLI found: $(Get-GhVersionText)" }

    # Step 4: offer installs
    Write-Step 'Step 4/9  Verifying required tools (winget install offered if missing)...'
    if (-not $gitOk) { $gitOk = Install-ToolWithWinget -WingetId 'Git.Git' -FriendlyName 'Git for Windows' -CommandName 'git' }
    if (-not $ghOk)  { $ghOk  = Install-ToolWithWinget -WingetId 'GitHub.cli' -FriendlyName 'GitHub CLI' -CommandName 'gh' }
    if (-not $gitOk -or -not $ghOk) {
        Write-Fail 'Required tools are missing. Install them (see INSTALLATION.md) and start the toolkit again.'
        return $null
    }

    # Step 5 + 6: authentication
    Write-Step 'Step 5/9  Checking GitHub authentication...'
    $signedIn = Test-GhAuthentication
    if (-not $signedIn) {
        Write-Warn 'Not signed in to GitHub.'
        Write-Step 'Step 6/9  Starting browser-based GitHub sign-in...'
        if (-not (Connect-GitHubAccount)) { return $null }
        $signedIn = Test-GhAuthentication
        if (-not $signedIn) {
            Write-Fail 'Still not signed in. Run the toolkit again and finish the browser sign-in.'
            return $null
        }
    } else {
        Write-Success 'GitHub authentication: CONNECTED'
    }

    # Step 7 + 8: account
    Write-Step 'Step 7/9  Reading the authenticated GitHub account...'
    $user = Get-AuthenticatedGitHubUser
    if ($null -eq $user) {
        Write-Fail 'Could not read the account from the GitHub API (network or token problem).'
        return $null
    }
    Write-Step 'Step 8/9  Verifying the account...'
    if (-not (Confirm-ExpectedAccount -User $user)) {
        Write-Warn 'Startup cancelled by user.'
        return $null
    }

    # Step 9: repositories
    Write-Step 'Step 9/9  Reading your repositories...'
    $repos = Get-MyRepositories
    if ($null -eq $repos) {
        Write-Warn 'Could not list repositories right now (network?). The dashboard will show repositories as unavailable.'
        $repos = @()
    } else {
        $repos = @($repos)
        Write-Success "Repositories found: $($repos.Count)"
    }

    Initialize-ToolkitData
    $expected = 'ArulAgnes'
    try { $expected = (Get-ToolkitSettings).expectedGitHubUsername } catch { }

    return [pscustomobject]@{
        User     = $user
        Repos    = $repos
        Expected = $expected
        DryRun   = (Test-DryRun)
        Started  = Get-Date
    }
}
