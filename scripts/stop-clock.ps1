param(
    [Parameter(Mandatory=$false)]
    [string]$TrelloId,
    [Parameter(Mandatory=$false)]
    [DateTime]$EndTimeOverride,
    [switch]$AutoStopped,
    [switch]$AsJson
)

$result = @{ success = $true; data = $null; message = "" }

$sessionFile = Join-Path $PSScriptRoot "..\data\active_session.json"
$activityLog = Join-Path $PSScriptRoot "..\data\session_activity.log"
$historyFile = Join-Path $PSScriptRoot "..\data\history.jsonl"
$trelloApi = Join-Path $PSScriptRoot "trello-api.ps1"
$dbScript = Join-Path $PSScriptRoot "db.ps1"

# Import database functions
if (Test-Path $dbScript) {
    . $dbScript
}

if (-not (Test-Path $sessionFile)) {
    $result.success = $false
    $result.message = "No active session found."
    if ($AsJson) { $result | ConvertTo-Json; exit 1 }
    Write-Error $result.message
    exit 1
}

# Import Trello API if available
if (Test-Path $trelloApi) {
    . $trelloApi
}

$sessionData = Get-Content $sessionFile | ConvertFrom-Json
$activeId = if ([string]::IsNullOrWhiteSpace($TrelloId)) { $sessionData.TrelloId } else { $TrelloId.ToUpper() }
$sessionId = $sessionData.SessionId

# Aggregate Activity
$activitySummary = "General work"
if (Test-Path $activityLog) {
    $lines = Get-Content $activityLog | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    if ($lines) {
        $activitySummary = ($lines | Select-Object -Unique) -join "; "
    }
}

$endTime = if ($PSBoundParameters.ContainsKey('EndTimeOverride')) { $EndTimeOverride } else { Get-Date }
$endTimeStr = $endTime.ToString("yyyy-MM-dd HH:mm:ss")
$duration = $endTime - [DateTime]$sessionData.StartTime
$durationMinutes = [Math]::Round($duration.TotalMinutes, 2)

# Get end commit
$endCommit = $null
try {
    $endCommit = (git rev-parse HEAD 2>$null)
} catch {
    # Git not available
}

# Get git context for end snapshot
$gitBranch = $null
$gitStatus = $null
$workingDir = (Get-Location).Path
try {
    $gitBranch = (git rev-parse --abbrev-ref HEAD 2>$null)
    $statusOutput = git status --porcelain 2>$null
    if ($statusOutput) {
        $staged = @()
        $modified = @()
        $untracked = @()
        foreach ($line in $statusOutput) {
            if ($line -match '^([MADRCU])[ M] (.+)$') {
                $staged += $matches[2]
            } elseif ($line -match '^[ MADRCU]([MADRCU]) (.+)$') {
                $modified += $matches[2]
            } elseif ($line -match '^\?\? (.+)$') {
                $untracked += $matches[1]
            }
        }
        $gitStatus = @{ staged = $staged; modified = $modified; untracked = $untracked } | ConvertTo-Json -Compress
    }
} catch {
    # Git not available
}

# Update SQLite session
if ($sessionId -and (Get-Command Update-Session -ErrorAction SilentlyContinue)) {
    try {
        $autoStoppedInt = if ($AutoStopped) { 1 } else { 0 }
        Update-Session -SessionId $sessionId -EndTime $endTimeStr -DurationMinutes $durationMinutes -Description $activitySummary -AutoStopped $autoStoppedInt -EndCommit $endCommit

        # Create end checkpoint
        $checkpointSummary = if ($AutoStopped) { "Session auto-stopped (inactive)" } else { "Session ended" }
        Add-ProgressPoint -SessionId $sessionId -Timestamp $endTimeStr -PointType 'checkpoint' -Summary $checkpointSummary -GitCommitHash $endCommit | Out-Null

        # Create end context snapshot
        Add-ContextSnapshot -SessionId $sessionId -Timestamp $endTimeStr -SnapshotType 'end' -GitBranch $gitBranch -GitStatus $gitStatus -WorkingDirectory $workingDir | Out-Null
    } catch {
        Write-Warning "Could not update SQLite session: $($_.Exception.Message)"
    }
}

# Create JSONL history entry (for backward compatibility)
$historyEntry = @{
    TrelloId = $activeId
    CardTitle = $sessionData.CardTitle
    Start = $sessionData.StartTime
    End = $endTimeStr
    DurationMinutes = $durationMinutes
    Description = $activitySummary
    AutoStopped = $AutoStopped.IsPresent
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

$result.message = "Clock stopped for $activeId. Duration: $($durationMinutes)m. Activity recorded: $activitySummary"
$result.data = @{
    trelloId = $activeId
    cardTitle = $sessionData.CardTitle
    startTime = $sessionData.StartTime
    endTime = $endTimeStr
    durationMinutes = $durationMinutes
    description = $activitySummary
    sessionId = $sessionId
    autoStopped = $AutoStopped.IsPresent
}

if ($AsJson) {
    $result | ConvertTo-Json
} else {
    $statusText = if ($AutoStopped) { " (auto-stopped)" } else { "" }
    Write-Host " Clock stopped for $activeId$statusText. Duration: $($durationMinutes)m. Activity recorded: $activitySummary" -ForegroundColor Green
}
