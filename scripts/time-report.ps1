# Time Tracking Report Script
# Generates a detailed breakdown of time tracking sessions with totals

param(
    [switch]$Detailed,
    [string]$TrelloId
)

$historyFile = Join-Path $PSScriptRoot "..\time_tracking\history.jsonl"
$activeSessionFile = Join-Path $PSScriptRoot "..\time_tracking\active_session.json"

# Check if history file exists
if (-not (Test-Path $historyFile)) {
    Write-Host "`nNo time tracking history found.`n" -ForegroundColor Yellow
    exit
}

# Load sessions
$sessions = Get-Content $historyFile | ConvertFrom-Json

# Check for active session
$activeSession = $null
if (Test-Path $activeSessionFile) {
    $activeSession = Get-Content $activeSessionFile | ConvertFrom-Json
}

# Filter by TrelloId if specified
if ($TrelloId) {
    $sessions = $sessions | Where-Object { $_.TrelloId -eq $TrelloId }
    if ($sessions.Count -eq 0) {
        Write-Host "`nNo sessions found for $TrelloId`n" -ForegroundColor Yellow
        exit
    }
}

# Display header
Write-Host "`n═" -ForegroundColor Cyan
Write-Host "           TIME TRACKING REPORT                             " -ForegroundColor Cyan
Write-Host "`n" -ForegroundColor Cyan

# Group by TrelloId
$grouped = $sessions | Group-Object TrelloId | Sort-Object Name

$grandTotal = 0

foreach ($group in $grouped) {
    $total = ($group.Group | Measure-Object -Property DurationMinutes -Sum).Sum
    $hours = [math]::Floor($total / 60)
    $minutes = [math]::Round($total % 60, 1)
    
    Write-Host "  $($group.Name):" -NoNewline -ForegroundColor Yellow
    Write-Host " $hours hours $minutes minutes" -ForegroundColor White
    
    # Show detailed breakdown if requested
    if ($Detailed) {
        foreach ($session in $group.Group) {
            $sessionHours = [math]::Floor($session.DurationMinutes / 60)
            $sessionMinutes = [math]::Round($session.DurationMinutes % 60, 1)
            $desc = if ($session.Description) { " - $($session.Description)" } else { "" }
            Write-Host "     $($session.Start)  $($session.End): $sessionHours h $sessionMinutes m$desc" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    $grandTotal += $total
}

# Show active session if exists
if ($activeSession -and (-not $TrelloId -or $activeSession.TrelloId -eq $TrelloId)) {
    try {
        $now = Get-Date
        $start = Get-Date $activeSession.Start
        $elapsed = ($now - $start).TotalMinutes
        $elapsedHours = [math]::Floor($elapsed / 60)
        $elapsedMinutes = [math]::Round($elapsed % 60, 1)
        
        Write-Host "`n    ACTIVE SESSION:" -ForegroundColor Green
        Write-Host "  $($activeSession.TrelloId): $elapsedHours hours $elapsedMinutes minutes (running)" -ForegroundColor Green
        
        if ($Detailed) {
            Write-Host "     Started: $($activeSession.Start)" -ForegroundColor Gray
            if ($activeSession.Description) {
                Write-Host "     Description: $($activeSession.Description)" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "`n    ACTIVE SESSION: $($activeSession.TrelloId) (running)" -ForegroundColor Green
    }
}

# Display grand total
Write-Host "`n" + ("" * 60) -ForegroundColor Cyan
$grandHours = [math]::Floor($grandTotal / 60)
$grandMinutes = [math]::Round($grandTotal % 60, 1)
Write-Host "  GRAND TOTAL: " -NoNewline -ForegroundColor Cyan
Write-Host "$grandHours hours $grandMinutes minutes" -ForegroundColor White
Write-Host ("" * 60) -ForegroundColor Cyan
Write-Host ""
