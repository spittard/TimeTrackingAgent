# Auto-Checkpoint Script
# Enhanced heartbeat that:
# 1. Updates session LastUpdate (staleness check)
# 2. Detects new git commits since last checkpoint
# 3. Creates periodic checkpoints (every 30 min)
# 4. Auto-stops stale sessions (>15 min inactive)

param(
    [int]$StaleMinutes = 15,
    [int]$CheckpointIntervalMinutes = 30,
    [switch]$AsJson
)

$result = @{ success = $true; data = $null; message = ""; actions = @() }

$sessionFile = Join-Path $PSScriptRoot "..\data\active_session.json"
$dbScript = Join-Path $PSScriptRoot "db.ps1"

# Import database functions
if (Test-Path $dbScript) {
    . $dbScript
}

if (-not (Test-Path $sessionFile)) {
    $result.message = "No active session"
    if ($AsJson) { $result | ConvertTo-Json; exit 0 }
    exit 0
}

try {
    $json = Get-Content $sessionFile -Raw | ConvertFrom-Json
    $sessionId = $json.SessionId
    $timeStr = if ($json.LastUpdate) { $json.LastUpdate } else { $json.StartTime }

    # Robust parsing for yyyy-MM-dd HH:mm:ss
    if ($timeStr -match '(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})') {
        $lastUpdate = Get-Date -Year $matches[1] -Month $matches[2] -Day $matches[3] -Hour $matches[4] -Minute $matches[5] -Second $matches[6]
        $now = Get-Date
        $nowStr = $now.ToString("yyyy-MM-dd HH:mm:ss")
        $diffMin = ($now - $lastUpdate).TotalMinutes

        # Check if session is stale
        if ($diffMin -gt $StaleMinutes) {
            $autoEndTime = $lastUpdate.AddMinutes($StaleMinutes)
            & "$PSScriptRoot\stop-clock.ps1" -TrelloId $json.TrelloId -EndTimeOverride $autoEndTime -AutoStopped
            $result.actions += "auto_stopped"
            $result.message = "Session auto-stopped for $($json.TrelloId)"
            Write-Host "AUTO_STOPPED:$($json.TrelloId)"
            if ($AsJson) { $result | ConvertTo-Json }
            exit 0
        }

        # Session is active - update LastUpdate
        $json.LastUpdate = $nowStr
        $json | ConvertTo-Json | Out-File -FilePath $sessionFile -Encoding utf8
        $result.actions += "heartbeat_updated"

        # Check for new git commits
        if ($sessionId -and (Get-Command Get-LastCheckpointCommit -ErrorAction SilentlyContinue)) {
            $lastCommit = Get-LastCheckpointCommit -SessionId $sessionId

            if ($lastCommit) {
                try {
                    $newCommits = git log --oneline "$lastCommit..HEAD" 2>$null
                    if ($newCommits) {
                        foreach ($commitLine in $newCommits) {
                            if ($commitLine -match '^([a-f0-9]+)\s+(.+)$') {
                                $commitHash = $matches[1]
                                $commitMsg = $matches[2]

                                # Get commit details
                                $details = $null
                                try {
                                    $stats = git show --stat --format="" $commitHash 2>$null
                                    if ($stats) {
                                        $filesChanged = ($stats | Select-Object -Last 1) -replace '\s+', ' '
                                        $details = @{ stats = $filesChanged } | ConvertTo-Json -Compress
                                    }
                                } catch {}

                                # Add git_commit progress point
                                Add-ProgressPoint -SessionId $sessionId -Timestamp $nowStr -PointType 'git_commit' -Summary $commitMsg -Details $details -GitCommitHash $commitHash | Out-Null
                                $result.actions += "git_commit:$commitHash"
                            }
                        }
                    }
                } catch {
                    # Git log failed - might be a force push or other issue
                }
            }
        }

        # Check if checkpoint is due (every 30 min)
        if ($sessionId -and (Get-Command Get-LastCheckpointTime -ErrorAction SilentlyContinue)) {
            $lastCheckpointTime = Get-LastCheckpointTime -SessionId $sessionId

            $createCheckpoint = $false
            if (-not $lastCheckpointTime) {
                $createCheckpoint = $true
            } else {
                if ($lastCheckpointTime -match '(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})') {
                    $lastCp = Get-Date -Year $matches[1] -Month $matches[2] -Day $matches[3] -Hour $matches[4] -Minute $matches[5] -Second $matches[6]
                    $cpDiffMin = ($now - $lastCp).TotalMinutes
                    if ($cpDiffMin -ge $CheckpointIntervalMinutes) {
                        $createCheckpoint = $true
                    }
                }
            }

            if ($createCheckpoint) {
                # Get current git state
                $currentCommit = $null
                $gitBranch = $null
                $gitStatus = $null
                try {
                    $currentCommit = (git rev-parse HEAD 2>$null)
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
                } catch {}

                # Calculate elapsed time
                $startTime = Get-Date $json.StartTime
                $elapsed = $now - $startTime
                $elapsedHours = [math]::Floor($elapsed.TotalHours)
                $elapsedMins = [math]::Round($elapsed.TotalMinutes % 60)
                $elapsedStr = if ($elapsedHours -gt 0) { "${elapsedHours}h ${elapsedMins}m elapsed" } else { "${elapsedMins}m elapsed" }

                # Create checkpoint
                Add-ProgressPoint -SessionId $sessionId -Timestamp $nowStr -PointType 'checkpoint' -Summary $elapsedStr -GitCommitHash $currentCommit | Out-Null

                # Create context snapshot
                Add-ContextSnapshot -SessionId $sessionId -Timestamp $nowStr -SnapshotType 'checkpoint' -GitBranch $gitBranch -GitStatus $gitStatus -WorkingDirectory (Get-Location).Path | Out-Null

                $result.actions += "checkpoint_created"
            }
        }

        $result.message = "Heartbeat updated for $($json.TrelloId)"
        $result.data = @{
            trelloId = $json.TrelloId
            sessionId = $sessionId
            lastUpdate = $nowStr
            actions = $result.actions
        }
    }
} catch {
    $result.success = $false
    $result.message = "Checkpoint error: $($_.Exception.Message)"
    Write-Warning "Checkpoint error: $_"
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
}
