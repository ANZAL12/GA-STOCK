@echo off
title Setup Auto-Start for Global Agencies Server
cd /d "%~dp0"

echo ==========================================================
echo  Global Agencies - Setup Persistent Auto-Start Server
echo ==========================================================
echo.
echo Requesting Administrator privileges...
echo.

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Elevating to Administrator...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo Running Auto-Start Service Configuration...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install_windows_service.ps1"

echo.
pause
