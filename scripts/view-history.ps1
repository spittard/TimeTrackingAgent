$historyFile = Join-Path $PSScriptRoot "..\data\history.jsonl"
if (-not (Test-Path $historyFile)) {
    Write-Host "No history found."
    exit
}

$history = Get-Content $historyFile | ForEach-Object { $_ | ConvertFrom-Json }

Write-Host "
### Work History Report
"
Write-Host "| Trello ID / Title | Description | Duration |"
Write-Host "| :--- | :--- | :--- |"

$totalDuration = 0
$history | Group-Object TrelloId | ForEach-Object {
    $group = $_
    $summary = ($group.Group.Description | Select-Object -Unique) -join "; "
    
    # Use CardTitle from the first entry in the group if available
    $displayId = $group.Name
    if ($group.Group[0].CardTitle) {
        $displayId = $group.Group[0].CardTitle
    }

    $min = ($group.Group | Measure-Object -Property DurationMinutes -Sum).Sum
    $hrs = [Math]::Round($min / 60, 2)

    $idLabel = "`" + $displayId + "`"
    $timeLabel = "**`" + $hrs + " hrs`**"
    
    Write-Host "| $idLabel | **$summary** | $timeLabel |"
    $totalDuration += $min
}

$totalHours = [Math]::Round($totalDuration / 60, 2)
$grandTotalTime = "**`" + $totalHours + " hrs`** (" + $totalDuration + " mins)"
Write-Host "| | | |"
Write-Host "| **GRAND TOTAL** | | $grandTotalTime |"
