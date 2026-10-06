# ==============================================================================
# Global Agencies - Godown Management System
# Windows Service Installer Script
# Configures FastAPI backend & React frontend as a persistent Windows Service
# ==============================================================================

param (
    [string]$ServiceName = "GlobalAgenciesGodownService",
    [string]$DisplayName = "Global Agencies Godown Management Server",
    [string]$Port = "8000"
)

# Ensure running with Administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this PowerShell script as Administrator!"
    Exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$BackendDir = Join-Path $ProjectRoot "backend"
$VenvPython = Join-Path $BackendDir ".venv\Scripts\python.exe"
$UvicornExe = Join-Path $BackendDir ".venv\Scripts\uvicorn.exe"
$LogDir = Join-Path $BackendDir "logs"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$StdoutLog = Join-Path $LogDir "service_stdout.log"
$StderrLog = Join-Path $LogDir "service_stderr.log"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Global Agencies Godown Management - Windows Service Setup" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Project Root : $ProjectRoot"
Write-Host "Backend Dir  : $BackendDir"
Write-Host "Python Path  : $VenvPython"
Write-Host "Service Name : $ServiceName"
Write-Host ""

# Check for NSSM (Non-Sucking Service Manager) in PATH or Tools folder
$nssmCmd = Get-Command nssm.exe -ErrorAction SilentlyContinue
$nssmPath = if ($nssmCmd) { $nssmCmd.Source } else { $null }

if (-not $nssmPath) {
    $toolsDir = Join-Path $ProjectRoot "tools"
    $nssmCandidate = Join-Path $toolsDir "nssm.exe"
    if (Test-Path $nssmCandidate) {
        $nssmPath = $nssmCandidate
    }
}

if ($nssmPath) {
    Write-Host "[+] Using NSSM at: $nssmPath" -ForegroundColor Green

    # Stop and remove existing service if present
    & $nssmPath stop $ServiceName 2>$null
    & $nssmPath remove $ServiceName confirm 2>$null

    # Install service
    & $nssmPath install $ServiceName "$UvicornExe" "app.main:app --host 0.0.0.0 --port $Port"
    & $nssmPath set $ServiceName AppDirectory "$BackendDir"
    & $nssmPath set $ServiceName DisplayName "$DisplayName"
    & $nssmPath set $ServiceName Description "Global Agencies Godown Management Web Dashboard and Mobile Scanning API"
    & $nssmPath set $ServiceName Start SERVICE_AUTO_START
    & $nssmPath set $ServiceName AppStdout "$StdoutLog"
    & $nssmPath set $ServiceName AppStderr "$StderrLog"
    & $nssmPath set $ServiceName DependOnService "postgresql-x64-17"

    # Start service
    & $nssmPath start $ServiceName
    Write-Host "[✓] Windows Service '$ServiceName' installed and started successfully via NSSM!" -ForegroundColor Green
} else {
    Write-Host "[!] NSSM not found in PATH. Creating PowerShell background service launcher." -ForegroundColor Yellow

    # Fallback to Task Scheduler auto-start on Windows boot
    $TaskName = "GlobalAgenciesGodownServer"
    $ActionScript = Join-Path $ScriptDir "run_server_background.vbs"

    $vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "$BackendDir"
WshShell.Run """$UvicornExe"" app.main:app --host 0.0.0.0 --port $Port", 0, False
"@
    Set-Content -Path $ActionScript -Value $vbsContent

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    $Action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$ActionScript`""
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings | Out-Null
    Start-ScheduledTask -TaskName $TaskName

    Write-Host "[✓] Task '$TaskName' registered for automatic startup at Windows boot!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Server is accessible on:" -ForegroundColor Cyan
Write-Host "  Local Desktop : http://127.0.0.1:$Port" -ForegroundColor White
Write-Host "  Godown LAN    : http://<LAN-IP>:$Port" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan
