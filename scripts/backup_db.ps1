# ==============================================================================
# Global Agencies - Godown Management System
# Automated Database Backup Script (PostgreSQL 17)
# Creates consistent SQL dump with rotation (keeps 30 days)
# ==============================================================================

param (
    [string]$DbName = "godown_db",
    [string]$DbUser = "godown_user",
    [string]$DbHost = "localhost",
    [string]$DbPort = "5432",
    [int]$RetentionDays = 30
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$BackupDir = Join-Path $ProjectRoot "backups"
$LogFile = Join-Path $BackupDir "backup.log"

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

function Write-BackupLog([string]$message, [string]$level = "INFO") {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$level] $message"
    Write-Output $logLine
    try {
        $logLine | Out-File -FilePath $LogFile -Append -Encoding utf8
    } catch {}
}

# Locate pg_dump
$cmd = Get-Command pg_dump.exe -ErrorAction SilentlyContinue
$pgDump = if ($cmd) { $cmd.Source } else { $null }
if (-not $pgDump) {
    $candidates = @(
        "C:\Program Files\PostgreSQL\17\bin\pg_dump.exe",
        "C:\Program Files\PostgreSQL\16\bin\pg_dump.exe",
        "C:\Program Files\PostgreSQL\15\bin\pg_dump.exe"
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) {
            $pgDump = $cand
            break
        }
    }
}

if (-not $pgDump) {
    Write-BackupLog "ERROR: pg_dump.exe not found! Please check PostgreSQL installation." "ERROR"
    Exit 1
}

$dateStr = (Get-Date).ToString("yyyyMMdd_HHmmss")
$backupFilename = "godown_db_$dateStr.sql"
$backupFilePath = Join-Path $BackupDir $backupFilename

Write-BackupLog "Starting automated backup for database '$DbName'..." "INFO"

# Set PGPASSWORD environment variable securely for this session
$env:PGPASSWORD = "anzal"

try {
    # Run pg_dump
    & $pgDump -h $DbHost -p $DbPort -U $DbUser -F p -b -v -f "$backupFilePath" $DbName 2>&1 | Out-Null

    if ((Test-Path $backupFilePath) -and ((Get-Item $backupFilePath).Length -gt 0)) {
        $fileSizeKB = [math]::Round(((Get-Item $backupFilePath).Length / 1KB), 2)
        Write-BackupLog "Backup SUCCESS: '$backupFilename' created ($fileSizeKB KB)." "INFO"
    } else {
        throw "Backup file was empty or not generated."
    }

    # Backup rotation: remove backups older than $RetentionDays
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $oldBackups = Get-ChildItem -Path $BackupDir -Filter "godown_db_*.sql" | Where-Object { $_.LastWriteTime -lt $cutoffDate }

    foreach ($old in $oldBackups) {
        Remove-Item $old.FullName -Force
        Write-BackupLog "Rotated out old backup: $($old.Name)" "INFO"
    }

} catch {
    Write-BackupLog "Backup FAILED: $($_.Exception.Message)" "ERROR"
    Exit 1
} finally {
    $env:PGPASSWORD = $null
}

Write-BackupLog "Backup job completed." "INFO"
