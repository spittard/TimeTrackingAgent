# Get Context
# Retrieve structured context for AI agents

param(
    [ValidateSet('current', 'resume', 'handoff', 'full')]
    [string]$Type = 'current',
    [ValidateSet('json', 'markdown')]
    [string]$Format = 'markdown',
    [int]$SessionId,
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

function Get-CurrentGitContext {
    $context = @{
        branch = $null
        commit = $null
        status = @{ staged = @(); modified = @(); untracked = @() }
        recentCommits = @()
    }

    try {
        $context.branch = (git rev-parse --abbrev-ref HEAD 2>$null)
        $context.commit = (git rev-parse HEAD 2>$null)

        $statusOutput = git status --porcelain 2>$null
        if ($statusOutput) {
            foreach ($line in $statusOutput) {
                if ($line -match '^([MADRCU])[ M] (.+)$') {
                    $context.status.staged += $matches[2]
                } elseif ($line -match '^[ MADRCU]([MADRCU]) (.+)$') {
                    $context.status.modified += $matches[2]
                } elseif ($line -match '^\?\? (.+)$') {
                    $context.status.untracked += $matches[1]
                }
            }
        }

        $commitLog = git log --oneline -5 2>$null
        if ($commitLog) {
            foreach ($line in $commitLog) {
                if ($line -match '^([a-f0-9]+)\s+(.+)$') {
                    $context.recentCommits += @{
                        hash = $matches[1]
                        message = $matches[2]
                    }
                }
            }
        }
    } catch {}

    return $context
}

function Get-SessionContext {
    param($Session, $ProgressPoints, $ActivityLogs)

    $now = Get-Date
    $startTime = [DateTime]::ParseExact($Session.start_time, "yyyy-MM-dd HH:mm:ss", $null)
    $elapsed = $now - $startTime

    return @{
        id = $Session.id
        trelloId = $Session.trello_id
        cardTitle = $Session.card_title
        startTime = $Session.start_time
        endTime = $Session.end_time
        elapsed = Format-Duration $elapsed.TotalMinutes
        elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 1)
        description = $Session.description
        startCommit = $Session.start_commit
        endCommit = $Session.end_commit
        progressPoints = $ProgressPoints
        activityCount = if ($ActivityLogs) { $ActivityLogs.Count } else { 0 }
    }
}

try {
    $contextData = @{
        type = $Type
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        workingDirectory = (Get-Location).Path
    }

    # Get current or last session
    $session = $null
    $isActive = $false

    if ($SessionId) {
        $sessions = Get-Sessions -SessionId $SessionId
        if ($sessions -and $sessions.Count -gt 0) {
            $session = $sessions[0]
            $isActive = [string]::IsNullOrEmpty($session.end_time)
        }
    } elseif (Test-Path $sessionFile) {
        $json = Get-Content $sessionFile -Raw | ConvertFrom-Json
        if ($json.SessionId) {
            $sessions = Get-Sessions -SessionId ([int]$json.SessionId)
            if ($sessions -and $sessions.Count -gt 0) {
                $session = $sessions[0]
                $isActive = $true
            }
        }
    }

    if (-not $session -and $Type -ne 'resume') {
        # Get most recent session
        $sessions = Get-Sessions -Limit 1
        if ($sessions -and $sessions.Count -gt 0) {
            $session = $sessions[0]
        }
    }

    # Get git context
    $gitContext = Get-CurrentGitContext

    switch ($Type) {
        'current' {
            if (-not $session) {
                $contextData.message = "No active session"
                $contextData.git = $gitContext
            } else {
                $progressPoints = Get-ProgressPoints -SessionId ([int]$session.id) -Limit 20
                $activityLogs = Get-ActivityLogs -SessionId ([int]$session.id) -Limit 50

                $contextData.session = Get-SessionContext -Session $session -ProgressPoints $progressPoints -ActivityLogs $activityLogs
                $contextData.isActive = $isActive
                $contextData.git = $gitContext
            }
        }

        'resume' {
            # Get the most recent completed session
            $sessions = Get-Sessions -Limit 5
            $lastSession = $sessions | Where-Object { $_.end_time } | Select-Object -First 1

            if (-not $lastSession) {
                $contextData.message = "No completed sessions found"
            } else {
                $progressPoints = Get-ProgressPoints -SessionId ([int]$lastSession.id)

                # Find milestones and key points
                $keyPoints = $progressPoints | Where-Object { $_.point_type -in @('milestone', 'git_commit') }

                $contextData.lastSession = Get-SessionContext -Session $lastSession -ProgressPoints $progressPoints -ActivityLogs $null
                $contextData.lastSession.keyProgress = $keyPoints
                $contextData.git = $gitContext

                # Suggest next steps based on last session
                $contextData.suggestedNextSteps = @(
                    "Review the progress made in the last session"
                    "Continue working on $($lastSession.trello_id)"
                    "Check git status for any uncommitted changes"
                )
            }
        }

        'handoff' {
            if (-not $session) {
                $contextData.message = "No session found for handoff"
            } else {
                $progressPoints = Get-ProgressPoints -SessionId ([int]$session.id)
                $activityLogs = Get-ActivityLogs -SessionId ([int]$session.id)
                $contextSnapshots = Get-ContextSnapshots -SessionId ([int]$session.id)

                $contextData.session = Get-SessionContext -Session $session -ProgressPoints $progressPoints -ActivityLogs $activityLogs
                $contextData.isActive = $isActive
                $contextData.git = $gitContext
                $contextData.contextSnapshots = $contextSnapshots

                # Build handoff instructions
                $contextData.handoffInstructions = @{
                    task = $session.trello_id
                    description = $session.card_title
                    currentState = if ($isActive) { "Session is active" } else { "Session completed" }
                    recentProgress = ($progressPoints | Where-Object { $_.point_type -eq 'milestone' } | Select-Object -Last 3)
                    gitState = @{
                        branch = $gitContext.branch
                        hasUncommittedChanges = ($gitContext.status.modified.Count + $gitContext.status.staged.Count) -gt 0
                    }
                }
            }
        }

        'full' {
            if (-not $session) {
                $contextData.message = "No session found"
            } else {
                $progressPoints = Get-ProgressPoints -SessionId ([int]$session.id) -Limit 500
                $activityLogs = Get-ActivityLogs -SessionId ([int]$session.id) -Limit 500
                $contextSnapshots = Get-ContextSnapshots -SessionId ([int]$session.id) -Limit 100

                $contextData.session = Get-SessionContext -Session $session -ProgressPoints $progressPoints -ActivityLogs $activityLogs
                $contextData.isActive = $isActive
                $contextData.git = $gitContext
                $contextData.progressPoints = $progressPoints
                $contextData.activityLogs = $activityLogs
                $contextData.contextSnapshots = $contextSnapshots
            }
        }
    }

    $result.data = $contextData
    $result.message = "Context retrieved successfully"

} catch {
    $result.success = $false
    $result.message = "Failed to get context: $($_.Exception.Message)"
    if ($AsJson -or $Format -eq 'json') { $result | ConvertTo-Json -Depth 10; exit 1 }
    Write-Error $result.message
    exit 1
}

# Output
if ($AsJson -or $Format -eq 'json') {
    $result | ConvertTo-Json -Depth 10
} else {
    # Markdown output
    $ctx = $result.data

    Write-Host ""
    switch ($Type) {
        'current' {
            Write-Host "# Current Session Context" -ForegroundColor Cyan
            Write-Host ""

            if ($ctx.session) {
                Write-Host "## Task" -ForegroundColor Yellow
                Write-Host "- **Trello ID**: $($ctx.session.trelloId)"
                Write-Host "- **Card Title**: $($ctx.session.cardTitle)"
                Write-Host "- **Started**: $($ctx.session.startTime)"
                Write-Host "- **Elapsed**: $($ctx.session.elapsed)"
                Write-Host ""

                Write-Host "## Git State" -ForegroundColor Yellow
                Write-Host "- **Branch**: $($ctx.git.branch)"
                if ($ctx.git.status.modified.Count -gt 0) {
                    Write-Host "- **Modified**: $($ctx.git.status.modified -join ', ')"
                }
                if ($ctx.git.status.staged.Count -gt 0) {
                    Write-Host "- **Staged**: $($ctx.git.status.staged -join ', ')"
                }
                Write-Host ""

                if ($ctx.session.progressPoints -and $ctx.session.progressPoints.Count -gt 0) {
                    Write-Host "## Progress So Far" -ForegroundColor Yellow
                    $milestones = $ctx.session.progressPoints | Where-Object { $_.point_type -in @('milestone', 'git_commit') }
                    $i = 1
                    foreach ($p in $milestones) {
                        $time = if ($p.timestamp -match '\d{4}-\d{2}-\d{2} (\d{2}:\d{2})') { $matches[1] } else { "" }
                        Write-Host "$i. [$time] $($p.summary)"
                        $i++
                    }
                }
            } else {
                Write-Host "No active session." -ForegroundColor Gray
                Write-Host ""
                Write-Host "## Git State" -ForegroundColor Yellow
                Write-Host "- **Branch**: $($ctx.git.branch)"
            }
        }

        'resume' {
            Write-Host "# Resume Context" -ForegroundColor Cyan
            Write-Host ""

            if ($ctx.lastSession) {
                Write-Host "## Last Session" -ForegroundColor Yellow
                Write-Host "- **Task**: $($ctx.lastSession.trelloId) - $($ctx.lastSession.cardTitle)"
                Write-Host "- **Ended**: $($ctx.lastSession.endTime)"
                Write-Host "- **Duration**: $(Format-Duration $ctx.lastSession.elapsedMinutes)"
                Write-Host ""

                if ($ctx.lastSession.keyProgress -and $ctx.lastSession.keyProgress.Count -gt 0) {
                    Write-Host "## Key Progress" -ForegroundColor Yellow
                    foreach ($p in $ctx.lastSession.keyProgress) {
                        Write-Host "- [$($p.point_type)] $($p.summary)"
                    }
                    Write-Host ""
                }

                Write-Host "## Suggested Next Steps" -ForegroundColor Yellow
                foreach ($step in $ctx.suggestedNextSteps) {
                    Write-Host "- $step"
                }
            } else {
                Write-Host "No previous sessions found." -ForegroundColor Gray
            }
        }

        'handoff' {
            Write-Host "# Handoff Context" -ForegroundColor Cyan
            Write-Host ""

            if ($ctx.handoffInstructions) {
                $hi = $ctx.handoffInstructions
                Write-Host "## Task Information" -ForegroundColor Yellow
                Write-Host "- **Task**: $($hi.task)"
                Write-Host "- **Description**: $($hi.description)"
                Write-Host "- **Status**: $($hi.currentState)"
                Write-Host ""

                Write-Host "## Git State" -ForegroundColor Yellow
                Write-Host "- **Branch**: $($hi.gitState.branch)"
                Write-Host "- **Uncommitted Changes**: $($hi.gitState.hasUncommittedChanges)"
                Write-Host ""

                if ($hi.recentProgress -and $hi.recentProgress.Count -gt 0) {
                    Write-Host "## Recent Milestones" -ForegroundColor Yellow
                    foreach ($p in $hi.recentProgress) {
                        Write-Host "- $($p.summary)"
                    }
                }
            }
        }

        'full' {
            Write-Host "# Full Session Context" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "(Use -AsJson for complete data)" -ForegroundColor Gray

            if ($ctx.session) {
                Write-Host ""
                Write-Host "Session: $($ctx.session.trelloId) - $($ctx.session.cardTitle)"
                Write-Host "Progress Points: $($ctx.progressPoints.Count)"
                Write-Host "Activity Logs: $($ctx.activityLogs.Count)"
                Write-Host "Context Snapshots: $($ctx.contextSnapshots.Count)"
            }
        }
    }
    Write-Host ""
}
