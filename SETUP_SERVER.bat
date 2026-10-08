@echo off
title Global Agencies - Initial Server Setup
cd /d "%~dp0"

echo ==========================================================
echo  Global Agencies - Initial Server Setup
echo ==========================================================
echo.

:: 1. Check Python
where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH.
    echo Please install Python 3.11+ from https://www.python.org/ (Check 'Add Python to PATH')
    pause
    exit /b 1
)

:: 2. Check Node
where npm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Node.js / npm is not installed or not in PATH.
    echo Please install Node.js (LTS) from https://nodejs.org/
    pause
    exit /b 1
)

:: 3. Setup Python Virtual Environment
echo [1/4] Setting up Python virtual environment (backend\.venv)...
if not exist "backend\.venv\Scripts\python.exe" (
    python -m venv backend\.venv
)
echo Installing backend dependencies from requirements.txt...
backend\.venv\Scripts\pip.exe install -r backend\requirements.txt --quiet
if errorlevel 1 (
    echo [ERROR] Failed to install Python dependencies.
    pause
    exit /b 1
)

:: 4. Setup Frontend
echo.
echo [2/4] Installing frontend dependencies and compiling Web UI...
cd frontend
call npm install
call npm run build
if errorlevel 1 (
    echo [ERROR] Failed to build frontend.
    pause
    exit /b 1
)
cd ..

:: 5. Check .env file
echo.
echo [3/4] Checking backend configuration (.env)...
if not exist "backend\.env" (
    if exist "backend\.env.example" (
        copy "backend\.env.example" "backend\.env" >nul
        echo [!] Created backend\.env from template.
        echo [!] Remember to verify your PostgreSQL credentials in backend\.env!
    )
)

:: 6. Run Database Migrations
echo.
echo [4/4] Setting up database schema (Alembic migrations)...
if exist "backend\.venv\Scripts\alembic.exe" (
    cd backend
    .venv\Scripts\alembic.exe upgrade head
    cd ..
)

echo.
echo ==========================================================
echo  SETUP COMPLETE!
echo  Start the server anytime by double-clicking: START_SERVER.bat
echo ==========================================================
echo.
pause
