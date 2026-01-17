# Capture Context Snapshot
# Creates a snapshot of the current working context

param(
    [ValidateSet('checkpoint', 'start', 'end')]
    [string]$Type = 'checkpoint',
    [int]$SessionId,
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
    if (-not $SessionId) {
        if (Test-Path $sessionFile) {
            $json = Get-Content $sessionFile -Raw | ConvertFrom-Json
            $targetSessionId = $json.SessionId
        }
    }

    if (-not $targetSessionId) {
        $result.success = $false
        $result.message = "No active session. Specify -SessionId or start an active session."
        if ($AsJson) { $result | ConvertTo-Json; exit 1 }
        Write-Error $result.message
        exit 1
    }

    $now = Get-Date
    $nowStr = $now.ToString("yyyy-MM-dd HH:mm:ss")
    $workingDir = (Get-Location).Path

    # Gather git context
    $gitBranch = $null
    $gitStatus = $null
    $recentCommits = @()

    try {
        $gitBranch = (git rev-parse --abbrev-ref HEAD 2>$null)

        # Get git status
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

        # Get recent commits (last 5)
        $commitLog = git log --oneline -5 2>$null
        if ($commitLog) {
            foreach ($line in $commitLog) {
                if ($line -match '^([a-f0-9]+)\s+(.+)$') {
                    $recentCommits += @{
                        hash = $matches[1]
                        message = $matches[2]
                    }
                }
            }
        }
    } catch {
        # Git not available
    }

    # Save context snapshot
    $snapshotId = Add-ContextSnapshot -SessionId $targetSessionId -Timestamp $nowStr -SnapshotType $Type -GitBranch $gitBranch -GitStatus $gitStatus -WorkingDirectory $workingDir

    $result.data = @{
        snapshotId = $snapshotId
        sessionId = $targetSessionId
        type = $Type
        timestamp = $nowStr
        gitBranch = $gitBranch
        gitStatus = if ($gitStatus) { $gitStatus | ConvertFrom-Json } else { $null }
        recentCommits = $recentCommits
        workingDirectory = $workingDir
    }
    $result.message = "Context snapshot captured"

} catch {
    $result.success = $false
    $result.message = "Failed to capture context: $($_.Exception.Message)"
    if ($AsJson) { $result | ConvertTo-Json; exit 1 }
    Write-Error $result.message
    exit 1
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host " Context snapshot captured [$Type]" -ForegroundColor Green
    if ($gitBranch) {
        Write-Host "   Branch: $gitBranch" -ForegroundColor Gray
    }
    if ($result.data.gitStatus) {
        $status = $result.data.gitStatus
        if ($status.staged.Count -gt 0) {
            Write-Host "   Staged: $($status.staged.Count) files" -ForegroundColor Gray
        }
        if ($status.modified.Count -gt 0) {
            Write-Host "   Modified: $($status.modified.Count) files" -ForegroundColor Gray
        }
        if ($status.untracked.Count -gt 0) {
            Write-Host "   Untracked: $($status.untracked.Count) files" -ForegroundColor Gray
        }
    }
}
