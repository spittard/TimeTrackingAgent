param(
    [Parameter(Mandatory=$true)]
    [string]$TrelloId,
    [Parameter(Mandatory=$false)]
    [string]$Description = ""
)
$sessionFile = Join-Path $PSScriptRoot "..\data\active_session.json"
$activityLog = Join-Path $PSScriptRoot "..\data\session_activity.log"
$trelloApi = Join-Path $PSScriptRoot "trello-api.ps1"

# Import Trello API if available
if (Test-Path $trelloApi) {
    . $trelloApi
}

$cardTitle = $TrelloId
try {
    if ((Get-Command Get-TrelloCard -ErrorAction SilentlyContinue) -and (Get-TrelloConfig)) {
        $card = Get-TrelloCard -CardId $TrelloId
        if ($card -and $card.name) {
            $cardTitle = "$($card.name) ($TrelloId)"
            Write-Host " Trello Card Found: $($card.name)" -ForegroundColor Cyan
        }
    }
} catch {
    # Trello fail shouldn't stop the clock
    Write-Warning "Could not fetch Trello card details: $($_.Exception.Message)"
}

$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$sessionData = @{
    TrelloId = $TrelloId
    CardTitle = $cardTitle
    StartTime = $now
    LastUpdate = $now
    StartCommit = (git rev-parse HEAD)
} | ConvertTo-Json
$sessionData | Out-File -FilePath $sessionFile -Encoding utf8

# Initialize empty activity log
"" | Out-File -FilePath $activityLog -Encoding utf8
Write-Host " Session started for $cardTitle" -ForegroundColor Green
