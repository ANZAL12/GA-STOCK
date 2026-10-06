# ==============================================================================
# Global Agencies - Godown Management System
# Health Watchdog Script
# Automatically monitors the /health endpoint and restarts server if unresponsive
# ==============================================================================

param (
    [string]$HealthUrl = "http://127.0.0.1:8000/health",
    [string]$ServiceName = "GlobalAgenciesGodownService",
    [int]$TimeoutSeconds = 5
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$LogFile = Join-Path $ProjectRoot "backend\logs\watchdog.log"

$logDir = Split-Path -Parent $LogFile
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-WatchdogLog([string]$message, [string]$level = "INFO") {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$level] $message"
    Write-Output $logLine
    Add-Content -Path $LogFile -Value $logLine
}

try {
    $response = Invoke-RestMethod -Uri $HealthUrl -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
    if ($response.status -eq "ok") {
        Write-WatchdogLog "Health check passed. Server operational (PostgreSQL connected)." "INFO"
        Exit 0
    } else {
        throw "Unexpected status: $($response.status)"
    }
} catch {
    $err = $_.Exception.Message
    Write-WatchdogLog "Health check FAILED: $err. Attempting server recovery..." "ERROR"

    # 1. Try Windows Service restart if NSSM service exists
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-WatchdogLog "Restarting Windows Service '$ServiceName'..." "WARN"
        Restart-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 4
        try {
            $checkAgain = Invoke-RestMethod -Uri $HealthUrl -Method Get -TimeoutSec $TimeoutSeconds
            if ($checkAgain.status -eq "ok") {
                Write-WatchdogLog "Recovery successful via Service restart." "INFO"
                Exit 0
            }
        } catch {}
    }

    # 2. Try Scheduled Task or direct start
    $TaskName = "GlobalAgenciesGodownServer"
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-WatchdogLog "Restarting Scheduled Task '$TaskName'..." "WARN"
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-ScheduledTask -TaskName $TaskName
        Write-WatchdogLog "Scheduled Task restarted." "INFO"
    } else {
        Write-WatchdogLog "Manual intervention required. No service or task found." "CRITICAL"
    }
}
