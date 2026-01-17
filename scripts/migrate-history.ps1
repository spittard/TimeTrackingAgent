# Migrate history.jsonl to SQLite database
# This script imports existing JSONL history entries into the new SQLite database

param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$AsJson
)

$result = @{ success = $true; data = $null; message = ""; imported = 0; skipped = 0; errors = @() }

# Import database functions
. "$PSScriptRoot\db.ps1"

$historyFile = Join-Path $PSScriptRoot "..\data\history.jsonl"
$backupFile = Join-Path $PSScriptRoot "..\data\history.jsonl.bak"

try {
    # Check if history file exists
    if (-not (Test-Path $historyFile)) {
        $result.message = "No history.jsonl file found at $historyFile"
        if ($AsJson) { $result | ConvertTo-Json -Depth 5; exit 0 }
        Write-Host $result.message -ForegroundColor Yellow
        exit 0
    }

    # Initialize database
    $initResult = Initialize-Database
    if (-not $initResult.success) {
        throw $initResult.message
    }

    if (-not $DryRun) {
        Write-Host "Database initialized at: $($initResult.data.path)" -ForegroundColor Cyan
    }

    # Check for existing data unless Force is specified
    if (-not $Force) {
        $existingSessions = Get-AllSessions -Limit 1 -IncludeZeroDuration
        if ($existingSessions -and $existingSessions.Count -gt 0) {
            $result.message = "Database already contains sessions. Use -Force to migrate anyway (will skip duplicates)."
            if ($AsJson) { $result | ConvertTo-Json -Depth 5; exit 0 }
            Write-Host $result.message -ForegroundColor Yellow
            exit 0
        }
    }

    # Read JSONL file
    $lines = Get-Content $historyFile -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }
    $totalLines = $lines.Count

    if ($DryRun) {
        Write-Host "`nDry Run - No changes will be made" -ForegroundColor Yellow
        Write-Host "Found $totalLines entries in history.jsonl" -ForegroundColor Cyan
        Write-Host ""
    }

    foreach ($line in $lines) {
        try {
            # Skip empty lines
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            # Remove BOM if present
            $cleanLine = $line -replace '^\xEF\xBB\xBF', ''
            $entry = $cleanLine | ConvertFrom-Json

            # Validate entry
            if (-not $entry.TrelloId) {
                $result.skipped++
                $result.errors += "Missing TrelloId: $cleanLine"
                continue
            }

            if (-not $entry.Start) {
                $result.skipped++
                $result.errors += "Missing Start time: $cleanLine"
                continue
            }

            # Skip negative durations
            $duration = if ($entry.DurationMinutes) { [double]$entry.DurationMinutes } else { 0 }
            if ($duration -lt 0) {
                $result.skipped++
                $result.errors += "Negative duration ($duration): $($entry.TrelloId) - $($entry.Start)"
                if (-not $DryRun) {
                    Write-Host "  Skipped (negative duration): $($entry.TrelloId) - $duration min" -ForegroundColor Yellow
                }
                continue
            }

            # Normalize TrelloId case
            $trelloId = $entry.TrelloId.ToUpper()
            $cardTitle = if ($entry.CardTitle) { $entry.CardTitle } else { $trelloId }
            $description = if ($entry.Description) { $entry.Description } else { "General work" }
            $autoStopped = if ($entry.AutoStopped) { 1 } else { 0 }

            # Parse dates
            $startTime = $entry.Start
            $endTime = if ($entry.End) { $entry.End } else { $startTime }

            if ($DryRun) {
                $hours = [math]::Floor($duration / 60)
                $mins = [math]::Round($duration % 60, 1)
                Write-Host "  Would import: $trelloId | $startTime | ${hours}h ${mins}m | $description" -ForegroundColor Gray
                $result.imported++
            } else {
                # Check for duplicate (same trello_id and start_time)
                $existing = Invoke-SqliteQuery -Query @"
SELECT id FROM sessions WHERE UPPER(trello_id) = UPPER(@trello_id) AND start_time = @start_time LIMIT 1;
"@ -Parameters @{ trello_id = $trelloId; start_time = $startTime }

                if ($existing -and $existing.Count -gt 0) {
                    $result.skipped++
                    Write-Host "  Skipped (duplicate): $trelloId - $startTime" -ForegroundColor Yellow
                    continue
                }

                # Insert session
                $sessionId = Add-Session -TrelloId $trelloId -CardTitle $cardTitle -StartTime $startTime -Description $description

                # Update with end time and duration
                Update-Session -SessionId $sessionId -EndTime $endTime -DurationMinutes $duration -AutoStopped $autoStopped

                $result.imported++
                Write-Host "  Imported: $trelloId | $startTime | $duration min" -ForegroundColor Green
            }
        } catch {
            $result.skipped++
            $result.errors += "Parse error: $($_.Exception.Message) - Line: $line"
            Write-Host "  Error parsing line: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Create backup of JSONL file
    if (-not $DryRun -and $result.imported -gt 0) {
        Copy-Item $historyFile $backupFile -Force
        Write-Host "`nBackup created: $backupFile" -ForegroundColor Cyan
    }

    # Summary
    $result.message = "Migration complete. Imported: $($result.imported), Skipped: $($result.skipped)"
    $result.data = @{
        total = $totalLines
        imported = $result.imported
        skipped = $result.skipped
        errors = $result.errors
    }

    if ($DryRun) {
        Write-Host "`n--- DRY RUN SUMMARY ---" -ForegroundColor Yellow
    } else {
        Write-Host "`n--- MIGRATION SUMMARY ---" -ForegroundColor Cyan
    }
    Write-Host "Total entries: $totalLines" -ForegroundColor White
    Write-Host "Imported: $($result.imported)" -ForegroundColor Green
    Write-Host "Skipped: $($result.skipped)" -ForegroundColor Yellow

    if ($result.errors.Count -gt 0) {
        Write-Host "`nErrors/Warnings:" -ForegroundColor Yellow
        foreach ($err in $result.errors | Select-Object -First 10) {
            Write-Host "  - $err" -ForegroundColor Gray
        }
        if ($result.errors.Count -gt 10) {
            Write-Host "  ... and $($result.errors.Count - 10) more" -ForegroundColor Gray
        }
    }

} catch {
    $result.success = $false
    $result.message = "Migration failed: $($_.Exception.Message)"
    if ($AsJson) { $result | ConvertTo-Json -Depth 5; exit 1 }
    Write-Error $result.message
    exit 1
}

if ($AsJson) { $result | ConvertTo-Json -Depth 5 }
