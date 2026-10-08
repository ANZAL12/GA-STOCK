@echo off
title Global Agencies - Update Server & Build
cd /d "%~dp0"

echo ==========================================================
echo  Global Agencies - Updating Project from Git
echo ==========================================================
echo.

echo [1/3] Pulling latest code changes from Git...
git pull
if errorlevel 1 (
    echo [ERROR] Git pull failed. Please check your internet connection or git status.
    pause
    exit /b 1
)

echo.
echo [2/3] Building Web Dashboard (React / Vite)...
cd frontend
call npm run build
if errorlevel 1 (
    echo [ERROR] Frontend build failed.
    pause
    exit /b 1
)
cd ..

echo.
echo [3/3] Verifying Backend Python dependencies...
if exist "backend\.venv\Scripts\pip.exe" (
    if exist "backend\requirements.txt" (
        backend\.venv\Scripts\pip.exe install -r backend\requirements.txt --quiet
    )
)

echo.
echo ==========================================================
echo  SUCCESS: Code updated and Web UI successfully rebuilt!
echo  (Restart START_SERVER.bat to apply backend changes)
echo ==========================================================
echo.
pause
