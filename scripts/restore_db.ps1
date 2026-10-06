# ==============================================================================
# Global Agencies - Godown Management System
# Database Restore Script (PostgreSQL 17)
# Safely restores a backup SQL dump into the PostgreSQL database
# ==============================================================================

param (
    [Parameter(Mandatory=$true)]
    [string]$BackupFile,
    [string]$DbName = "godown_db",
    [string]$DbUser = "godown_user",
    [string]$DbHost = "localhost",
    [string]$DbPort = "5432"
)

# Resolve path
if (-not (Test-Path $BackupFile)) {
    Write-Error "Backup file '$BackupFile' does not exist!"
    Exit 1
}

$fileItem = Get-Item $BackupFile
if ($fileItem.Length -eq 0) {
    Write-Error "Backup file is empty (0 bytes)!"
    Exit 1
}

# Locate psql
$psqlCmd = Get-Command psql.exe -ErrorAction SilentlyContinue
$psql = if ($psqlCmd) { $psqlCmd.Source } else { $null }
if (-not $psql) {
    $candidates = @(
        "C:\Program Files\PostgreSQL\17\bin\psql.exe",
        "C:\Program Files\PostgreSQL\16\bin\psql.exe",
        "C:\Program Files\PostgreSQL\15\bin\psql.exe"
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) {
            $psql = $cand
            break
        }
    }
}

if (-not $psql) {
    Write-Error "psql.exe not found! Please check PostgreSQL installation."
    Exit 1
}

Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host " Global Agencies Godown Management - Database Restore" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "Backup File : $($fileItem.FullName)"
Write-Host "File Size   : $([math]::Round($fileItem.Length / 1KB, 2)) KB"
Write-Host "Target DB   : $DbName on $DbHost:$DbPort"
Write-Host ""
Write-Host "WARNING: Restoring will overwrite existing data in '$DbName'!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Type 'RESTORE' to proceed"
if ($confirm -ne "RESTORE") {
    Write-Host "Restore cancelled by user." -ForegroundColor Gray
    Exit 0
}

Write-Host "Executing restore..." -ForegroundColor Cyan
$env:PGPASSWORD = "anzal"

try {
    & $psql -h $DbHost -p $DbPort -U $DbUser -d $DbName -f "$($fileItem.FullName)" 2>&1 | Out-Null
    Write-Host "[✓] Database '$DbName' restored successfully from '$($fileItem.Name)'!" -ForegroundColor Green
} catch {
    Write-Error "Restore FAILED: $($_.Exception.Message)"
} finally {
    $env:PGPASSWORD = $null
}
