param(
    [Parameter(Mandatory=$true)]
    [string]$TrelloId,
    [Parameter(Mandatory=$false)]
    [string]$Description = "",
    [switch]$AsJson
)

$result = @{ success = $true; data = $null; message = "" }

$sessionFile = Join-Path $PSScriptRoot "..\data\active_session.json"
$activityLog = Join-Path $PSScriptRoot "..\data\session_activity.log"
$trelloApi = Join-Path $PSScriptRoot "trello-api.ps1"
$dbScript = Join-Path $PSScriptRoot "db.ps1"

# Import database functions
if (Test-Path $dbScript) {
    . $dbScript
    # Ensure database is initialized
    $initResult = Initialize-Database
    if (-not $initResult.success) {
        Write-Warning "Could not initialize database: $($initResult.message)"
    }
}

# Import Trello API if available
if (Test-Path $trelloApi) {
    . $trelloApi
}

# Check for existing active session
if (Test-Path $sessionFile) {
    $existingSession = Get-Content $sessionFile | ConvertFrom-Json
    $result.success = $false
    $result.message = "An active session already exists for $($existingSession.TrelloId). Stop it first with stop-clock.ps1"
    if ($AsJson) { $result | ConvertTo-Json; exit 1 }
    Write-Error $result.message
    exit 1
}

# Normalize TrelloId
$TrelloId = $TrelloId.ToUpper()

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
$startCommit = $null
try {
    $startCommit = (git rev-parse HEAD 2>$null)
} catch {
    # Git not available or not in repo
}

# Get git context for snapshot
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

# Create SQLite session
$sessionId = $null
if (Get-Command Add-Session -ErrorAction SilentlyContinue) {
    try {
        $sessionId = Add-Session -TrelloId $TrelloId -CardTitle $cardTitle -StartTime $now -StartCommit $startCommit -Description $Description

        # Create initial checkpoint
        if ($sessionId) {
            Add-ProgressPoint -SessionId $sessionId -Timestamp $now -PointType 'checkpoint' -Summary "Session started" -GitCommitHash $startCommit | Out-Null

            # Create start context snapshot
            Add-ContextSnapshot -SessionId $sessionId -Timestamp $now -SnapshotType 'start' -GitBranch $gitBranch -GitStatus $gitStatus -WorkingDirectory $workingDir | Out-Null
        }
    } catch {
        Write-Warning "Could not create SQLite session: $($_.Exception.Message)"
    }
}

# Create session file (for backward compatibility and heartbeat)
$sessionData = @{
    TrelloId = $TrelloId
    CardTitle = $cardTitle
    StartTime = $now
    LastUpdate = $now
    StartCommit = $startCommit
    SessionId = $sessionId
    Description = $Description
} | ConvertTo-Json
$sessionData | Out-File -FilePath $sessionFile -Encoding utf8

# Initialize empty activity log
"" | Out-File -FilePath $activityLog -Encoding utf8

$result.message = "Session started for $cardTitle"
$result.data = @{
    trelloId = $TrelloId
    cardTitle = $cardTitle
    startTime = $now
    sessionId = $sessionId
    startCommit = $startCommit
}

if ($AsJson) {
    $result | ConvertTo-Json
} else {
    Write-Host " Session started for $cardTitle" -ForegroundColor Green
    if ($sessionId) {
        Write-Host " SQLite session ID: $sessionId" -ForegroundColor Gray
    }
}
