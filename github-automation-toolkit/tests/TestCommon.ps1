#Requires -Version 5.1
<#
.SYNOPSIS
    TestCommon.ps1 - tiny dependency-free test framework (no Pester needed).
    Works on Windows PowerShell 5.1 and PowerShell 7.
#>

$script:TC = [ordered]@{
    Passed  = 0
    Failed  = 0
    Skipped = 0
    Failures = @()
    CurrentSuite = ''
}

function Write-TestSuite {
    param([string]$Name)
    $script:TC.CurrentSuite = $Name
    Write-Host ""
    Write-Host "  SUITE: $Name" -ForegroundColor Cyan
}

function Assert-True {
    param([bool]$Condition, [string]$Because = '')
    if (-not $Condition) { throw ("Expected condition to be true. $Because") }
}

function Assert-False {
    param([bool]$Condition, [string]$Because = '')
    if ($Condition) { throw ("Expected condition to be false. $Because") }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Because = '')
    if ("$Expected" -ne "$Actual") { throw ("Expected '$Expected' but got '$Actual'. $Because") }
}

function Assert-NotNull {
    param($Value, [string]$Because = '')
    if ($null -eq $Value) { throw ("Expected a value but got `$null. $Because") }
}

function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Because = '')
    if ($Haystack -notlike "*$Needle*") { throw ("Expected output to contain '$Needle'. $Because") }
}

function Assert-GreaterThan {
    param([double]$Actual, [double]$Threshold, [string]$Because = '')
    if (-not ($Actual -gt $Threshold)) { throw ("Expected $Actual > $Threshold. $Because") }
}

function It {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )
    try {
        & $Body
        $script:TC.Passed++
        Write-Host "    PASS  $Name" -ForegroundColor Green
    } catch {
        $script:TC.Failed++
        $script:TC.Failures += ("[{0}] {1} :: {2}" -f $script:TC.CurrentSuite, $Name, $_.Exception.Message)
        Write-Host "    FAIL  $Name" -ForegroundColor Red
        Write-Host ("          {0}" -f $_.Exception.Message) -ForegroundColor DarkRed
    }
}

function Skip-It {
    param([string]$Name, [string]$Reason)
    $script:TC.Skipped++
    Write-Host "    SKIP  $Name - $Reason" -ForegroundColor Yellow
}

function Complete-TestRun {
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor DarkCyan
    Write-Host ("  RESULT: {0} passed, {1} failed, {2} skipped" -f $script:TC.Passed, $script:TC.Failed, $script:TC.Skipped) -ForegroundColor $(if ($script:TC.Failed -eq 0) { 'Green' } else { 'Red' })
    if ($script:TC.Failures.Count -gt 0) {
        Write-Host ""
        Write-Host "  Failures:" -ForegroundColor Red
        foreach ($f in $script:TC.Failures) { Write-Host "    - $f" -ForegroundColor Red }
    }
    Write-Host "==============================================" -ForegroundColor DarkCyan
    return ($script:TC.Failed -eq 0)
}
