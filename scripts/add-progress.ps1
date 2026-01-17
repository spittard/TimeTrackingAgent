# Add Progress Point
# Manually add a milestone or note to the active session

param(
    [ValidateSet('milestone', 'note')]
    [string]$Type = 'milestone',
    [Parameter(Mandatory=$true)]
    [string]$Summary,
    [string]$Details,
    [switch]$AsJson
)

$result = @{ success = $true; data = $null; message = "" }

$sessionFile = Join-Path $PSScriptRoot "..\data\active_session.json"
$activityLog = Join-Path $PSScriptRoot "..\data\session_activity.log"
$dbScript = Join-Path $PSScriptRoot "db.ps1"

# Import database functions
if (Test-Path $dbScript) {
    . $dbScript
}

# Check for active session
if (-not (Test-Path $sessionFile)) {
    $result.success = $false
    $result.message = "No active session. Start a session first with start-clock.ps1"
    if ($AsJson) { $result | ConvertTo-Json; exit 1 }
    Write-Error $result.message
    exit 1
}

try {
    $json = Get-Content $sessionFile -Raw | ConvertFrom-Json
    $sessionId = $json.SessionId
    $now = Get-Date
    $nowStr = $now.ToString("yyyy-MM-dd HH:mm:ss")

    # Get current git commit if available
    $currentCommit = $null
    try {
        $currentCommit = (git rev-parse HEAD 2>$null)
    } catch {}

    # Add progress point to database
    if ($sessionId -and (Get-Command Add-ProgressPoint -ErrorAction SilentlyContinue)) {
        $detailsJson = $null
        if ($Details) {
            $detailsJson = @{ text = $Details } | ConvertTo-Json -Compress
        }

        $pointId = Add-ProgressPoint -SessionId $sessionId -Timestamp $nowStr -PointType $Type -Summary $Summary -Details $detailsJson -GitCommitHash $currentCommit

        $result.data = @{
            pointId = $pointId
            sessionId = $sessionId
            type = $Type
            summary = $Summary
            timestamp = $nowStr
        }
        $result.message = "Progress point added: [$Type] $Summary"
    } else {
        $result.success = $false
        $result.message = "Database not available or session ID not found"
        if ($AsJson) { $result | ConvertTo-Json; exit 1 }
        Write-Error $result.message
        exit 1
    }

    # Also add to activity log for backward compatibility
    if (Test-Path $activityLog) {
        $logEntry = "[$Type] $Summary"
        Add-Content -Path $activityLog -Value $logEntry -Encoding utf8
    }

    # Update LastUpdate timestamp
    $json.LastUpdate = $nowStr
    $json | ConvertTo-Json | Out-File -FilePath $sessionFile -Encoding utf8

} catch {
    $result.success = $false
    $result.message = "Failed to add progress point: $($_.Exception.Message)"
    if ($AsJson) { $result | ConvertTo-Json; exit 1 }
    Write-Error $result.message
    exit 1
}

if ($AsJson) {
    $result | ConvertTo-Json
} else {
    $timeStr = (Get-Date).ToString("HH:mm")
    Write-Host " [$timeStr] Progress added: [$Type] $Summary" -ForegroundColor Green
}
