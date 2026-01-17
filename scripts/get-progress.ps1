# Get Progress Points
# Query progress points for a session or the active session

param(
    [int]$SessionId,
    [ValidateSet('all', 'milestone', 'checkpoint', 'git_commit', 'note')]
    [string]$Type = 'all',
    [int]$Limit = 50,
    [switch]$Active,
    [switch]$AsJson
)

$result = @{ success = $true; data = $null; message = "" }

$sessionFile = Join-Path $PSScriptRoot "..\data\active_session.json"
$dbScript = Join-Path $PSScriptRoot "db.ps1"

# Import database functions
if (Test-Path $dbScript) {
    . $dbScript
} else {
    $result.success = $false
    $result.message = "Database module not found"
    if ($AsJson) { $result | ConvertTo-Json; exit 1 }
    Write-Error $result.message
    exit 1
}

try {
    # Determine session ID
    $targetSessionId = $SessionId
    if ($Active -or (-not $SessionId)) {
        if (Test-Path $sessionFile) {
            $json = Get-Content $sessionFile -Raw | ConvertFrom-Json
            $targetSessionId = $json.SessionId
        } else {
            # Get most recent session from database
            $sessions = Get-Sessions -Limit 1
            if ($sessions -and $sessions.Count -gt 0) {
                $targetSessionId = [int]$sessions[0].id
            }
        }
    }

    if (-not $targetSessionId) {
        $result.success = $false
        $result.message = "No session found. Specify -SessionId or start an active session."
        if ($AsJson) { $result | ConvertTo-Json; exit 1 }
        Write-Error $result.message
        exit 1
    }

    # Get progress points
    $pointType = if ($Type -eq 'all') { $null } else { $Type }
    $points = Get-ProgressPoints -SessionId $targetSessionId -PointType $pointType -Limit $Limit

    # Get session info
    $session = Get-Sessions -SessionId $targetSessionId
    $sessionInfo = $null
    if ($session -and $session.Count -gt 0) {
        $sessionInfo = @{
            id = $session[0].id
            trelloId = $session[0].trello_id
            cardTitle = $session[0].card_title
            startTime = $session[0].start_time
            endTime = $session[0].end_time
            durationMinutes = $session[0].duration_minutes
        }
    }

    $result.data = @{
        session = $sessionInfo
        progressPoints = $points
        count = if ($points) { $points.Count } else { 0 }
    }
    $result.message = "Found $($result.data.count) progress points"

} catch {
    $result.success = $false
    $result.message = "Failed to get progress points: $($_.Exception.Message)"
    if ($AsJson) { $result | ConvertTo-Json; exit 1 }
    Write-Error $result.message
    exit 1
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host "`n--- Progress Points ---" -ForegroundColor Cyan
    if ($sessionInfo) {
        Write-Host "Session: $($sessionInfo.trelloId) - $($sessionInfo.cardTitle)" -ForegroundColor White
        Write-Host "Started: $($sessionInfo.startTime)" -ForegroundColor Gray
        if ($sessionInfo.endTime) {
            Write-Host "Ended: $($sessionInfo.endTime) ($($sessionInfo.durationMinutes)m)" -ForegroundColor Gray
        }
        Write-Host ""
    }

    if ($points -and $points.Count -gt 0) {
        foreach ($point in $points) {
            $time = if ($point.timestamp -match '\d{4}-\d{2}-\d{2} (\d{2}:\d{2})') { $matches[1] } else { $point.timestamp }
            $typeColor = switch ($point.point_type) {
                'milestone' { 'Yellow' }
                'git_commit' { 'Magenta' }
                'checkpoint' { 'Cyan' }
                'note' { 'Gray' }
                default { 'White' }
            }
            $commitInfo = if ($point.git_commit_hash) { " ($($point.git_commit_hash.Substring(0,7)))" } else { "" }
            Write-Host "  [$time] " -NoNewline -ForegroundColor White
            Write-Host "[$($point.point_type)]" -NoNewline -ForegroundColor $typeColor
            Write-Host " $($point.summary)$commitInfo" -ForegroundColor White
        }
    } else {
        Write-Host "  No progress points found." -ForegroundColor Gray
    }
    Write-Host ""
}
