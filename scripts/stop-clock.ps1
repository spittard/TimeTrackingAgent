param(
    [Parameter(Mandatory=$false)]
    [string]$TrelloId,
    [Parameter(Mandatory=$false)]
    [DateTime]$EndTimeOverride
)

$sessionFile = Join-Path $PSScriptRoot "..\data\active_session.json"
$activityLog = Join-Path $PSScriptRoot "..\data\session_activity.log"
$historyFile = Join-Path $PSScriptRoot "..\data\history.jsonl"
$trelloApi = Join-Path $PSScriptRoot "trello-api.ps1"

if (-not (Test-Path $sessionFile)) {
    Write-Error "No active session found."
    exit 1
}

# Import Trello API if available
if (Test-Path $trelloApi) {
    . $trelloApi
}

$sessionData = Get-Content $sessionFile | ConvertFrom-Json
$activeId = if ([string]::IsNullOrWhiteSpace($TrelloId)) { $sessionData.TrelloId } else { $TrelloId }

# Aggregate Activity
$activitySummary = "General work"
if (Test-Path $activityLog) {
    $lines = Get-Content $activityLog | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    if ($lines) {
        $activitySummary = ($lines | Select-Object -Unique) -join "; "
    }
}

$endTime = if ($PSBoundParameters.ContainsKey('EndTimeOverride')) { $EndTimeOverride } else { Get-Date }
$duration = $endTime - [DateTime]$sessionData.StartTime
$durationMinutes = [Math]::Round($duration.TotalMinutes, 2)

$historyEntry = @{
    TrelloId = $activeId
    CardTitle = $sessionData.CardTitle
    Start = $sessionData.StartTime
    End = $endTime.ToString("yyyy-MM-dd HH:mm:ss")
    DurationMinutes = $durationMinutes
    Description = $activitySummary
} | ConvertTo-Json -Compress

# Log to local history
$historyEntry | Out-File -FilePath $historyFile -Append -Encoding utf8

# Post to Trello if configured
try {
    if ((Get-Command Add-TrelloComment -ErrorAction SilentlyContinue) -and (Get-TrelloConfig)) {
        $comment = "[TimeLog] $($durationMinutes)m: $activitySummary"
        Add-TrelloComment -CardId $activeId -Text $comment | Out-Null
        Write-Host " Comment posted to Trello card $activeId" -ForegroundColor Cyan
    }
} catch {
    Write-Warning "Failed to post comment to Trello: $($_.Exception.Message)"
}

Remove-Item $sessionFile, $activityLog -ErrorAction SilentlyContinue
Write-Host " Clock stopped for $activeId. Duration: $($durationMinutes)m. Activity recorded: $activitySummary" -ForegroundColor Green
