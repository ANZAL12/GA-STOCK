@echo off
title Remove Auto-Start for Global Agencies Server
cd /d "%~dp0"

echo ==========================================================
echo  Global Agencies - Remove Auto-Start Server
echo ==========================================================
echo.

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Elevating to Administrator...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo Stopping and removing auto-start task / service...

:: Try removing scheduled task
schtasks /delete /tn "GlobalAgenciesGodownServer" /f >nul 2>&1
if %errorLevel% equ 0 (
    echo [OK] Removed Task Scheduler auto-start task.
)

:: Try stopping and removing NSSM service if it was installed
powershell -Command "if (Get-Service -Name 'GlobalAgenciesGodownService' -ErrorAction SilentlyContinue) { Stop-Service -Name 'GlobalAgenciesGodownService' -Force; sc.exe delete 'GlobalAgenciesGodownService' }" >nul 2>&1

echo [OK] Auto-start has been removed.
echo.
pause
