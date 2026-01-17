# Summarize Session
# Generates intelligent summaries from session data

param(
    [int]$SessionId,
    [switch]$ForTrello,
    [switch]$ForHandoff,
    [switch]$Active,
    [switch]$AsJson
)

$result = @{ success = $true; data = $null; message = "" }

$sessionFile = Join-Path $PSScriptRoot "..\data\active_session.json"
$dbScript = Join-Path $PSScriptRoot "db.ps1"

# Import database functions
if (Test-Path $dbScript) {
    . $dbScript
}

function Format-Duration {
    param([double]$Minutes)
    $hours = [math]::Floor($Minutes / 60)
    $mins = [math]::Round($Minutes % 60)
    if ($hours -gt 0) { return "${hours}h ${mins}m" }
    return "${mins}m"
}

try {
    # Determine session
    $targetSessionId = $SessionId
    if ($Active -or (-not $SessionId)) {
        if (Test-Path $sessionFile) {
            $json = Get-Content $sessionFile -Raw | ConvertFrom-Json
            $targetSessionId = $json.SessionId
        }
    }

    if (-not $targetSessionId) {
        # Get most recent session
        $sessions = Get-Sessions -Limit 1
        if ($sessions -and $sessions.Count -gt 0) {
            $targetSessionId = [int]$sessions[0].id
        }
    }

    if (-not $targetSessionId) {
        $result.success = $false
        $result.message = "No session found"
        if ($AsJson) { $result | ConvertTo-Json; exit 1 }
        Write-Error $result.message
        exit 1
    }

    # Get session data
    $sessions = Get-Sessions -SessionId $targetSessionId
    if (-not $sessions -or $sessions.Count -eq 0) {
        $result.success = $false
        $result.message = "Session not found: $targetSessionId"
        if ($AsJson) { $result | ConvertTo-Json; exit 1 }
        Write-Error $result.message
        exit 1
    }

    $session = $sessions[0]
    $progressPoints = Get-ProgressPoints -SessionId $targetSessionId
    $activityLogs = Get-ActivityLogs -SessionId $targetSessionId

    # Calculate duration
    $duration = 0
    if ($session.duration_minutes) {
        $duration = [double]$session.duration_minutes
    } elseif ($session.start_time) {
        $startTime = [DateTime]::ParseExact($session.start_time, "yyyy-MM-dd HH:mm:ss", $null)
        $duration = ((Get-Date) - $startTime).TotalMinutes
    }

    # Extract key information
    $milestones = @()
    $gitCommits = @()
    $notes = @()

    if ($progressPoints) {
        foreach ($point in $progressPoints) {
            switch ($point.point_type) {
                'milestone' { $milestones += $point.summary }
                'git_commit' {
                    $commitInfo = $point.summary
                    if ($point.git_commit_hash) {
                        $commitInfo = "$($point.git_commit_hash.Substring(0,7)): $($point.summary)"
                    }
                    $gitCommits += $commitInfo
                }
                'note' { $notes += $point.summary }
            }
        }
    }

    # Build summary
    $summary = @{
        sessionId = $targetSessionId
        trelloId = $session.trello_id
        cardTitle = $session.card_title
        startTime = $session.start_time
        endTime = $session.end_time
        duration = Format-Duration $duration
        durationMinutes = [math]::Round($duration, 1)
        isActive = [string]::IsNullOrEmpty($session.end_time)
        milestones = $milestones
        gitCommits = $gitCommits
        notes = $notes
        activityCount = if ($activityLogs) { $activityLogs.Count } else { 0 }
    }

    # Format output based on target
    if ($ForTrello) {
        # Trello comment format
        $trelloComment = "[TimeLog] $(Format-Duration $duration)`n"

        if ($milestones.Count -gt 0) {
            $trelloComment += "`nMilestones:`n"
            foreach ($m in $milestones) {
                $trelloComment += "- $m`n"
            }
        }

        if ($gitCommits.Count -gt 0) {
            $trelloComment += "`nCommits:`n"
            foreach ($c in ($gitCommits | Select-Object -First 5)) {
                $trelloComment += "- $c`n"
            }
            if ($gitCommits.Count -gt 5) {
                $trelloComment += "- ... and $($gitCommits.Count - 5) more`n"
            }
        }

        $summary.formattedOutput = $trelloComment.Trim()

    } elseif ($ForHandoff) {
        # Handoff format for another agent
        $handoff = @"
# Session Handoff: $($session.trello_id)

## Task
$($session.card_title)

## Status
$(if ($summary.isActive) { "Session is ACTIVE" } else { "Session COMPLETED" })

## Duration
$($summary.duration)

"@

        if ($milestones.Count -gt 0) {
            $handoff += "## Completed Milestones`n"
            foreach ($m in $milestones) {
                $handoff += "- $m`n"
            }
            $handoff += "`n"
        }

        if ($gitCommits.Count -gt 0) {
            $handoff += "## Git Commits`n"
            foreach ($c in $gitCommits) {
                $handoff += "- $c`n"
            }
            $handoff += "`n"
        }

        if ($notes.Count -gt 0) {
            $handoff += "## Notes`n"
            foreach ($n in $notes) {
                $handoff += "- $n`n"
            }
            $handoff += "`n"
        }

        $handoff += @"
## Next Steps
Continue working on $($session.trello_id). Review the milestones above for context.
"@

        $summary.formattedOutput = $handoff

    } else {
        # Default summary format
        $defaultSummary = @"
Session Summary: $($session.trello_id)
Card: $($session.card_title)
Duration: $($summary.duration)
Status: $(if ($summary.isActive) { "Active" } else { "Completed" })

"@

        if ($milestones.Count -gt 0) {
            $defaultSummary += "Milestones ($($milestones.Count)):`n"
            foreach ($m in $milestones) {
                $defaultSummary += "  - $m`n"
            }
        }

        if ($gitCommits.Count -gt 0) {
            $defaultSummary += "Commits ($($gitCommits.Count)):`n"
            foreach ($c in ($gitCommits | Select-Object -First 5)) {
                $defaultSummary += "  - $c`n"
            }
        }

        $summary.formattedOutput = $defaultSummary
    }

    $result.data = $summary
    $result.message = "Summary generated"

} catch {
    $result.success = $false
    $result.message = "Failed to summarize session: $($_.Exception.Message)"
    if ($AsJson) { $result | ConvertTo-Json -Depth 5; exit 1 }
    Write-Error $result.message
    exit 1
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
} else {
    Write-Host $summary.formattedOutput
}
