# Detailed Timesheet Report
# Shows totals per Trello ID, activity logs, and grand total.

$historyFile = Join-Path $PSScriptRoot "..\data\history.jsonl"
if (-not (Test-Path $historyFile)) {
    Write-Host "No time tracking history found." -ForegroundColor Yellow
    exit
}

$sessions = Get-Content $historyFile | ForEach-Object { 
    try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null } 
} | Where-Object { $_ -ne $null }
$grouped = $sessions | Group-Object TrelloId | Sort-Object Name

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "                DETAILED TIMESHEET REPORT" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

$grandTotalMinutes = 0

foreach ($group in $grouped) {
    $idTotalMinutes = ($group.Group | Measure-Object -Property DurationMinutes -Sum).Sum
    $hrs = [Math]::Floor($idTotalMinutes / 60)
    $mins = [Math]::Round($idTotalMinutes % 60, 1)
    
    Write-Host "[$($group.Name)]" -ForegroundColor Yellow -NoNewline
    Write-Host " - TOTAL: $hrs h $mins m" -ForegroundColor White
    
    foreach ($session in $group.Group) {
        $sHrs = [Math]::Floor($session.DurationMinutes / 60)
        $sMins = [Math]::Round($session.DurationMinutes % 60, 1)
        $desc = if ($session.Description) { $session.Description } else { "(no description)" }
        
        Write-Host "  > $($session.Start): " -ForegroundColor Gray -NoNewline
        Write-Host "($sHrs h $sMins m) " -ForegroundColor Green -NoNewline
        Write-Host "$desc" -ForegroundColor White
    }
    Write-Host ""
    $grandTotalMinutes += $idTotalMinutes
}

$gHrs = [Math]::Floor($grandTotalMinutes / 60)
$gMins = [Math]::Round($grandTotalMinutes % 60, 1)

Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "GRAND TOTAL: " -NoNewline -ForegroundColor Cyan
Write-Host "$gHrs hours $gMins minutes" -ForegroundColor White
Write-Host "============================================================`n" -ForegroundColor Cyan
