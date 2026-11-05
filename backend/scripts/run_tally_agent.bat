@echo off
title GA STOCK - Tally Connector Agent
echo ========================================================
echo Starting GA STOCK Tally Connector Agent
echo ========================================================
echo.

:: Replace with your Server PC's Tailscale IP or Tailscale name (e.g. http://100.x.y.z:8000)
set SERVER_URL=http://100.x.y.z:8000
set AGENT_TOKEN=ga-tally-secret-2026
set SYNC_INTERVAL=10

echo Target Server: %SERVER_URL%
echo Syncing local Tally (port 9000) every %SYNC_INTERVAL%s...
echo Press Ctrl+C to stop.
echo.

python "%~dp0tally_agent.py" --backend-url "%SERVER_URL%" --agent-token "%AGENT_TOKEN%" --loop --interval %SYNC_INTERVAL%

pause

