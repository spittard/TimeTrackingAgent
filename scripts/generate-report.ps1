# Generate Report
# Multi-format report generator for time tracking data

param(
    [ValidateSet('daily', 'weekly', 'session', 'project', 'timeline')]
    [string]$Type = 'daily',
    [DateTime]$Date = (Get-Date),
    [string]$TrelloId,
    [int]$SessionId,
    [int]$Days = 7,
    [string]$OutputPath,
    [switch]$AsJson
)

$result = @{ success = $true; data = $null; message = "" }

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

function Format-Duration {
    param([double]$Minutes)
    $hours = [math]::Floor($Minutes / 60)
    $mins = [math]::Round($Minutes % 60)
    if ($hours -gt 0) { return "${hours}h ${mins}m" }
    return "${mins}m"
}

function Get-DailyReport {
    param([DateTime]$ReportDate)

    $dateStr = $ReportDate.ToString("yyyy-MM-dd")
    $sessions = Get-SessionsByDateRange -StartDate $ReportDate.Date -EndDate $ReportDate.Date.AddDays(1).AddSeconds(-1)

    if (-not $sessions -or $sessions.Count -eq 0) {
        return @{
            date = $dateStr
            totalMinutes = 0
            sessionCount = 0
            taskCount = 0
            tasks = @()
            timeline = @()
        }
    }

    $totalMinutes = ($sessions | Measure-Object -Property duration_minutes -Sum).Sum
    $taskGroups = $sessions | Group-Object -Property trello_id

    $tasks = @()
    $timeline = @()

    foreach ($group in $taskGroups) {
        $taskMinutes = ($group.Group | Measure-Object -Property duration_minutes -Sum).Sum
        $taskSessions = @()

        foreach ($session in $group.Group) {
            $sessionId = [int]$session.id
            $progressPoints = Get-ProgressPoints -SessionId $sessionId

            $taskSessions += @{
                id = $sessionId
                start = $session.start_time
                end = $session.end_time
                duration = $session.duration_minutes
                description = $session.description
                progressPoints = $progressPoints
            }

            # Add to timeline
            $timeline += @{
                time = $session.start_time
                task = $session.trello_id
                activity = "Session started"
                type = "start"
            }

            foreach ($point in $progressPoints) {
                if ($point.point_type -ne 'checkpoint' -or $point.summary -notmatch 'started|ended') {
                    $timeline += @{
                        time = $point.timestamp
                        task = $session.trello_id
                        activity = $point.summary
                        type = $point.point_type
                    }
                }
            }

            if ($session.end_time) {
                $timeline += @{
                    time = $session.end_time
                    task = $session.trello_id
                    activity = "Session ended"
                    type = "end"
                }
            }
        }

        $tasks += @{
            trelloId = $group.Name
            cardTitle = $group.Group[0].card_title
            totalMinutes = $taskMinutes
            sessionCount = $group.Count
            sessions = $taskSessions
        }
    }

    # Sort timeline by time
    $timeline = $timeline | Sort-Object { $_.time }

    return @{
        date = $dateStr
        totalMinutes = $totalMinutes
        sessionCount = $sessions.Count
        taskCount = $taskGroups.Count
        tasks = $tasks
        timeline = $timeline
    }
}

function Get-WeeklyReport {
    param([DateTime]$WeekDate)

    # Get start of week (Monday)
    $dayOfWeek = [int]$WeekDate.DayOfWeek
    if ($dayOfWeek -eq 0) { $dayOfWeek = 7 }
    $weekStart = $WeekDate.Date.AddDays(-($dayOfWeek - 1))
    $weekEnd = $weekStart.AddDays(7).AddSeconds(-1)

    $sessions = Get-SessionsByDateRange -StartDate $weekStart -EndDate $weekEnd

    $dailyBreakdown = @()
    for ($i = 0; $i -lt 7; $i++) {
        $day = $weekStart.AddDays($i)
        $daySessions = $sessions | Where-Object {
            $sessionDate = [DateTime]::ParseExact($_.start_time.Substring(0,10), "yyyy-MM-dd", $null)
            $sessionDate.Date -eq $day.Date
        }
        $dayMinutes = if ($daySessions) { ($daySessions | Measure-Object -Property duration_minutes -Sum).Sum } else { 0 }
        $dailyBreakdown += @{
            date = $day.ToString("yyyy-MM-dd")
            dayName = $day.ToString("dddd")
            minutes = $dayMinutes
        }
    }

    $taskGroups = $sessions | Group-Object -Property trello_id
    $tasks = @()

    foreach ($group in $taskGroups) {
        $taskMinutes = ($group.Group | Measure-Object -Property duration_minutes -Sum).Sum
        $tasks += @{
            trelloId = $group.Name
            cardTitle = $group.Group[0].card_title
            totalMinutes = $taskMinutes
            sessionCount = $group.Count
        }
    }

    return @{
        weekStart = $weekStart.ToString("yyyy-MM-dd")
        weekEnd = $weekEnd.ToString("yyyy-MM-dd")
        totalMinutes = if ($sessions) { ($sessions | Measure-Object -Property duration_minutes -Sum).Sum } else { 0 }
        sessionCount = if ($sessions) { $sessions.Count } else { 0 }
        taskCount = $taskGroups.Count
        dailyBreakdown = $dailyBreakdown
        tasks = $tasks
    }
}

function Get-SessionReport {
    param([int]$Id)

    $session = Get-Sessions -SessionId $Id
    if (-not $session -or $session.Count -eq 0) {
        return $null
    }

    $s = $session[0]
    $progressPoints = Get-ProgressPoints -SessionId $Id
    $contextSnapshots = Get-ContextSnapshots -SessionId $Id

    return @{
        id = $s.id
        trelloId = $s.trello_id
        cardTitle = $s.card_title
        startTime = $s.start_time
        endTime = $s.end_time
        durationMinutes = $s.duration_minutes
        description = $s.description
        autoStopped = $s.auto_stopped -eq 1
        startCommit = $s.start_commit
        endCommit = $s.end_commit
        progressPoints = $progressPoints
        contextSnapshots = $contextSnapshots
    }
}

function Get-ProjectReport {
    param([string]$Id)

    $sessions = Get-Sessions -TrelloId $Id -Limit 500
    if (-not $sessions -or $sessions.Count -eq 0) {
        return $null
    }

    $totalMinutes = ($sessions | Measure-Object -Property duration_minutes -Sum).Sum
    $allProgressPoints = @()

    foreach ($s in $sessions) {
        $points = Get-ProgressPoints -SessionId ([int]$s.id)
        if ($points) {
            $allProgressPoints += $points
        }
    }

    return @{
        trelloId = $Id
        cardTitle = $sessions[0].card_title
        totalMinutes = $totalMinutes
        sessionCount = $sessions.Count
        firstSession = $sessions[-1].start_time
        lastSession = $sessions[0].start_time
        sessions = $sessions
        progressPoints = $allProgressPoints | Sort-Object { $_.timestamp }
    }
}

function Get-TimelineReport {
    param([int]$NumDays)

    $endDate = Get-Date
    $startDate = $endDate.AddDays(-$NumDays)

    $sessions = Get-SessionsByDateRange -StartDate $startDate -EndDate $endDate

    $timeline = @()
    foreach ($s in $sessions) {
        $timeline += @{
            time = $s.start_time
            task = $s.trello_id
            cardTitle = $s.card_title
            activity = "Session started"
            sessionId = $s.id
        }

        $points = Get-ProgressPoints -SessionId ([int]$s.id)
        foreach ($point in $points) {
            $timeline += @{
                time = $point.timestamp
                task = $s.trello_id
                cardTitle = $s.card_title
                activity = "[$($point.point_type)] $($point.summary)"
                sessionId = $s.id
            }
        }

        if ($s.end_time) {
            $timeline += @{
                time = $s.end_time
                task = $s.trello_id
                cardTitle = $s.card_title
                activity = "Session ended ($($s.duration_minutes)m)"
                sessionId = $s.id
            }
        }
    }

    return @{
        startDate = $startDate.ToString("yyyy-MM-dd")
        endDate = $endDate.ToString("yyyy-MM-dd")
        days = $NumDays
        timeline = $timeline | Sort-Object { $_.time }
    }
}

function Format-MarkdownReport {
    param($ReportData, [string]$ReportType)

    $md = ""

    switch ($ReportType) {
        'daily' {
            $md = "# Daily Time Report: $($ReportData.date)`n`n"
            $md += "## Summary`n"
            $md += "- **Total Time**: $(Format-Duration $ReportData.totalMinutes)`n"
            $md += "- **Sessions**: $($ReportData.sessionCount)`n"
            $md += "- **Tasks**: $($ReportData.taskCount)`n`n"

            if ($ReportData.tasks.Count -gt 0) {
                $md += "## By Task`n`n"
                foreach ($task in $ReportData.tasks) {
                    $md += "### $($task.trelloId) - $($task.cardTitle)`n"
                    $md += "- **Total**: $(Format-Duration $task.totalMinutes) ($($task.sessionCount) sessions)`n"

                    $allPoints = @()
                    foreach ($s in $task.sessions) {
                        if ($s.progressPoints) {
                            $allPoints += $s.progressPoints
                        }
                    }
                    if ($allPoints.Count -gt 0) {
                        $md += "- **Progress Points**:`n"
                        foreach ($point in ($allPoints | Sort-Object { $_.timestamp })) {
                            $time = if ($point.timestamp -match '\d{4}-\d{2}-\d{2} (\d{2}:\d{2})') { $matches[1] } else { "" }
                            $md += "  - $time - [$($point.point_type)] $($point.summary)`n"
                        }
                    }
                    $md += "`n"
                }
            }

            if ($ReportData.timeline.Count -gt 0) {
                $md += "## Timeline`n`n"
                $md += "| Time | Task | Activity |`n"
                $md += "|------|------|----------|`n"
                foreach ($entry in $ReportData.timeline) {
                    $time = if ($entry.time -match '\d{4}-\d{2}-\d{2} (\d{2}:\d{2})') { $matches[1] } else { $entry.time }
                    $md += "| $time | $($entry.task) | $($entry.activity) |`n"
                }
            }
        }

        'weekly' {
            $md = "# Weekly Time Report: $($ReportData.weekStart) to $($ReportData.weekEnd)`n`n"
            $md += "## Summary`n"
            $md += "- **Total Time**: $(Format-Duration $ReportData.totalMinutes)`n"
            $md += "- **Sessions**: $($ReportData.sessionCount)`n"
            $md += "- **Tasks**: $($ReportData.taskCount)`n`n"

            $md += "## Daily Breakdown`n`n"
            $md += "| Day | Date | Time |`n"
            $md += "|-----|------|------|`n"
            foreach ($day in $ReportData.dailyBreakdown) {
                $md += "| $($day.dayName) | $($day.date) | $(Format-Duration $day.minutes) |`n"
            }
            $md += "`n"

            if ($ReportData.tasks.Count -gt 0) {
                $md += "## By Task`n`n"
                $md += "| Task | Time | Sessions |`n"
                $md += "|------|------|----------|`n"
                foreach ($task in ($ReportData.tasks | Sort-Object { $_.totalMinutes } -Descending)) {
                    $md += "| $($task.trelloId) | $(Format-Duration $task.totalMinutes) | $($task.sessionCount) |`n"
                }
            }
        }

        'session' {
            $md = "# Session Report: $($ReportData.trelloId)`n`n"
            $md += "## Details`n"
            $md += "- **Card**: $($ReportData.cardTitle)`n"
            $md += "- **Start**: $($ReportData.startTime)`n"
            $md += "- **End**: $($ReportData.endTime)`n"
            $md += "- **Duration**: $(Format-Duration $ReportData.durationMinutes)`n"
            if ($ReportData.description) {
                $md += "- **Description**: $($ReportData.description)`n"
            }
            if ($ReportData.startCommit) {
                $md += "- **Start Commit**: $($ReportData.startCommit)`n"
            }
            if ($ReportData.endCommit) {
                $md += "- **End Commit**: $($ReportData.endCommit)`n"
            }
            $md += "`n"

            if ($ReportData.progressPoints -and $ReportData.progressPoints.Count -gt 0) {
                $md += "## Progress Points`n`n"
                foreach ($point in $ReportData.progressPoints) {
                    $time = if ($point.timestamp -match '\d{4}-\d{2}-\d{2} (\d{2}:\d{2})') { $matches[1] } else { "" }
                    $commitInfo = if ($point.git_commit_hash) { " ``$($point.git_commit_hash.Substring(0,7))``" } else { "" }
                    $md += "- **$time** [$($point.point_type)] $($point.summary)$commitInfo`n"
                }
            }
        }

        'project' {
            $md = "# Project Report: $($ReportData.trelloId)`n`n"
            $md += "## Summary`n"
            $md += "- **Card**: $($ReportData.cardTitle)`n"
            $md += "- **Total Time**: $(Format-Duration $ReportData.totalMinutes)`n"
            $md += "- **Sessions**: $($ReportData.sessionCount)`n"
            $md += "- **First Session**: $($ReportData.firstSession)`n"
            $md += "- **Last Session**: $($ReportData.lastSession)`n`n"

            $md += "## Sessions`n`n"
            $md += "| Date | Duration | Description |`n"
            $md += "|------|----------|-------------|`n"
            foreach ($s in $ReportData.sessions) {
                $date = $s.start_time.Substring(0, 10)
                $desc = if ($s.description.Length -gt 50) { $s.description.Substring(0, 47) + "..." } else { $s.description }
                $md += "| $date | $(Format-Duration $s.duration_minutes) | $desc |`n"
            }
        }

        'timeline' {
            $md = "# Timeline Report: Last $($ReportData.days) Days`n`n"
            $md += "Period: $($ReportData.startDate) to $($ReportData.endDate)`n`n"

            $md += "## Activity Timeline`n`n"
            $md += "| Time | Task | Activity |`n"
            $md += "|------|------|----------|`n"
            foreach ($entry in $ReportData.timeline) {
                $md += "| $($entry.time) | $($entry.task) | $($entry.activity) |`n"
            }
        }
    }

    return $md
}

# Main execution
try {
    $reportData = $null

    switch ($Type) {
        'daily' { $reportData = Get-DailyReport -ReportDate $Date }
        'weekly' { $reportData = Get-WeeklyReport -WeekDate $Date }
        'session' {
            if (-not $SessionId) {
                throw "Session report requires -SessionId parameter"
            }
            $reportData = Get-SessionReport -Id $SessionId
        }
        'project' {
            if (-not $TrelloId) {
                throw "Project report requires -TrelloId parameter"
            }
            $reportData = Get-ProjectReport -Id $TrelloId
        }
        'timeline' { $reportData = Get-TimelineReport -NumDays $Days }
    }

    if (-not $reportData) {
        $result.message = "No data found for the specified report"
        if ($AsJson) { $result | ConvertTo-Json -Depth 10 }
        else { Write-Host $result.message -ForegroundColor Yellow }
        exit 0
    }

    $result.data = $reportData
    $result.message = "Report generated successfully"

    if ($AsJson) {
        $result | ConvertTo-Json -Depth 10
    } else {
        $markdown = Format-MarkdownReport -ReportData $reportData -ReportType $Type

        if ($OutputPath) {
            $markdown | Out-File -FilePath $OutputPath -Encoding utf8
            Write-Host " Report saved to: $OutputPath" -ForegroundColor Green
        } else {
            Write-Host $markdown
        }
    }

} catch {
    $result.success = $false
    $result.message = "Failed to generate report: $($_.Exception.Message)"
    if ($AsJson) { $result | ConvertTo-Json; exit 1 }
    Write-Error $result.message
    exit 1
}
