# Database Backup Utility
# Creates timestamped backups and manages backup retention

param(
    [switch]$Restore,
    [string]$BackupFile,
    [int]$KeepDays = 7,
    [switch]$List,
    [switch]$AsJson
)

$result = @{ success = $true; data = $null; message = "" }

$dbPath = Join-Path $PSScriptRoot "..\data\timetracking.db"
$backupDir = Join-Path $PSScriptRoot "..\data\backups"

# Ensure backup directory exists
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

function Get-Backups {
    $backups = @()
    if (Test-Path $backupDir) {
        $files = Get-ChildItem -Path $backupDir -Filter "timetracking_*.db" | Sort-Object LastWriteTime -Descending
        foreach ($file in $files) {
            $backups += @{
                name = $file.Name
                path = $file.FullName
                size = $file.Length
                created = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
    return $backups
}

try {
    if ($List) {
        # List existing backups
        $backups = Get-Backups

        $result.data = @{
            backupDirectory = $backupDir
            backups = $backups
            count = $backups.Count
        }
        $result.message = "Found $($backups.Count) backups"

        if (-not $AsJson) {
            Write-Host "`n--- Database Backups ---" -ForegroundColor Cyan
            Write-Host "Directory: $backupDir" -ForegroundColor Gray
            Write-Host ""

            if ($backups.Count -eq 0) {
                Write-Host "No backups found." -ForegroundColor Yellow
            } else {
                foreach ($backup in $backups) {
                    $sizeKB = [math]::Round($backup.size / 1024, 1)
                    Write-Host "  $($backup.name) - ${sizeKB}KB - $($backup.created)" -ForegroundColor White
                }
            }
            Write-Host ""
        }

    } elseif ($Restore) {
        # Restore from backup
        if (-not $BackupFile) {
            # Use most recent backup
            $backups = Get-Backups
            if ($backups.Count -eq 0) {
                throw "No backups available to restore"
            }
            $BackupFile = $backups[0].path
        }

        if (-not (Test-Path $BackupFile)) {
            # Try looking in backup directory
            $fullPath = Join-Path $backupDir $BackupFile
            if (Test-Path $fullPath) {
                $BackupFile = $fullPath
            } else {
                throw "Backup file not found: $BackupFile"
            }
        }

        # Create backup of current database before restore
        if (Test-Path $dbPath) {
            $preRestoreBackup = Join-Path $backupDir "timetracking_pre-restore_$(Get-Date -Format 'yyyyMMdd_HHmmss').db"
            Copy-Item $dbPath $preRestoreBackup -Force
            Write-Host " Pre-restore backup created: $preRestoreBackup" -ForegroundColor Gray
        }

        # Restore
        Copy-Item $BackupFile $dbPath -Force

        $result.data = @{
            restoredFrom = $BackupFile
            restoredTo = $dbPath
        }
        $result.message = "Database restored from: $BackupFile"

        if (-not $AsJson) {
            Write-Host " Database restored from: $BackupFile" -ForegroundColor Green
        }

    } else {
        # Create backup
        if (-not (Test-Path $dbPath)) {
            throw "Database not found: $dbPath"
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupName = "timetracking_$timestamp.db"
        $backupPath = Join-Path $backupDir $backupName

        Copy-Item $dbPath $backupPath -Force

        $backupSize = (Get-Item $backupPath).Length

        # Clean up old backups
        $cutoffDate = (Get-Date).AddDays(-$KeepDays)
        $oldBackups = Get-ChildItem -Path $backupDir -Filter "timetracking_*.db" |
            Where-Object { $_.LastWriteTime -lt $cutoffDate }

        $deletedCount = 0
        foreach ($old in $oldBackups) {
            Remove-Item $old.FullName -Force
            $deletedCount++
        }

        $result.data = @{
            backupPath = $backupPath
            backupName = $backupName
            size = $backupSize
            oldBackupsDeleted = $deletedCount
        }
        $result.message = "Backup created: $backupName"

        if (-not $AsJson) {
            $sizeKB = [math]::Round($backupSize / 1024, 1)
            Write-Host " Backup created: $backupName (${sizeKB}KB)" -ForegroundColor Green
            if ($deletedCount -gt 0) {
                Write-Host " Cleaned up $deletedCount old backup(s)" -ForegroundColor Gray
            }
        }
    }

} catch {
    $result.success = $false
    $result.message = "Backup operation failed: $($_.Exception.Message)"
    if ($AsJson) { $result | ConvertTo-Json; exit 1 }
    Write-Error $result.message
    exit 1
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
}
