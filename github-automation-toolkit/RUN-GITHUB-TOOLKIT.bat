@echo off
setlocal EnableExtensions EnableDelayedExpansion
title GitHub Automation ^& Learning Lab

REM ============================================================
REM  RUN-GITHUB-TOOLKIT.bat
REM  Double-click launcher for the GitHub Automation ^& Learning Lab
REM
REM  - Never changes the system execution policy permanently.
REM  - Prefers PowerShell 7 (pwsh) when installed, otherwise uses
REM    the Windows PowerShell 5.1 shipped with Windows 11.
REM  - Passes -ExecutionPolicy Bypass for THIS process only.
REM ============================================================

set "ROOT=%~dp0"
set "MAIN_PS1=%ROOT%src\Main.ps1"

echo.
echo  ============================================================
echo        GITHUB AUTOMATION ^& LEARNING LAB
echo  ============================================================
echo.

REM --- Sanity check: are we on Windows? -----------------------
if not "%OS%"=="Windows_NT" (
    echo  [X] This launcher is designed for Windows 10/11.
    echo      See INSTALLATION.md for details.
    pause
    exit /b 1
)

REM --- Sanity check: Main.ps1 present? ------------------------
if not exist "%MAIN_PS1%" (
    echo  [X] Could not find src\Main.ps1 next to this launcher.
    echo      Make sure the whole folder was extracted from the ZIP,
    echo      not just this .bat file.
    pause
    exit /b 1
)

REM --- Pick the best available PowerShell ----------------------
set "PS_EXE="
where pwsh.exe >nul 2>&1
if not errorlevel 1 (
    set "PS_EXE=pwsh.exe"
) else (
    where powershell.exe >nul 2>&1
    if not errorlevel 1 (
        set "PS_EXE=powershell.exe"
    )
)

if not defined PS_EXE (
    echo  [X] No PowerShell was found on this machine.
    echo      Windows 11 normally ships Windows PowerShell 5.1.
    echo      Install PowerShell 7 from https://aka.ms/powershell or the
    echo      Microsoft Store, then double-click this file again.
    pause
    exit /b 1
)

echo  [i] Using PowerShell host: %PS_EXE%
"%PS_EXE%" -NoLogo -Command "Write-Host ('    Version: ' + $PSVersionTable.PSVersion.ToString())"
echo.

REM --- Launch the toolkit (bypass applies to this process only) -
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%MAIN_PS1%"
set "TOOLKIT_EXIT=%ERRORLEVEL%"

echo.
if not "%TOOLKIT_EXIT%"=="0" (
    echo  ============================================================
    echo   [!] The toolkit exited with code %TOOLKIT_EXIT%.
    echo       Common causes: GitHub sign-in cancelled, missing tools,
    echo       or no network connection. See SAFETY.md troubleshooting.
    echo  ============================================================
    echo.
    pause
)

endlocal & exit /b %TOOLKIT_EXIT%
