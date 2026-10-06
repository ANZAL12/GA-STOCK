@echo off
title Global Agencies - Godown Management System
cd /d "%~dp0\.."

echo ==========================================================
echo  Global Agencies - Godown Management System
echo  Starting FastAPI Server and Web Dashboard on port 8000...
echo ==========================================================
echo.

if not exist "backend\.venv\Scripts\uvicorn.exe" (
    echo [ERROR] Python virtual environment not found in backend\.venv
    pause
    exit /b 1
)

echo Starting server at http://127.0.0.1:8000 ...
start "" "http://127.0.0.1:8000"

cd backend
.venv\Scripts\uvicorn.exe app.main:app --host 0.0.0.0 --port 8000 --reload
pause
