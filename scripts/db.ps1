# SQLite Database Abstraction Layer for TimeTrackingAgent
# Uses sqlite3 CLI for portability

$script:DbPath = Join-Path $PSScriptRoot "..\data\timetracking.db"

function Get-Sqlite3Path {
    # Check common locations for sqlite3
    $paths = @(
        "sqlite3",
        "C:\ProgramData\chocolatey\bin\sqlite3.exe",
        "$env:LOCALAPPDATA\Programs\sqlite\sqlite3.exe",
        "$PSScriptRoot\..\lib\sqlite3.exe"
    )

    foreach ($path in $paths) {
        if (Get-Command $path -ErrorAction SilentlyContinue) {
            return $path
        }
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Invoke-SqliteQuery {
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [hashtable]$Parameters = @{},
        [string]$DbPath = $script:DbPath,
        [switch]$Scalar
    )

    $sqlite3 = Get-Sqlite3Path
    if (-not $sqlite3) {
        throw "sqlite3 not found. Please install SQLite (choco install sqlite) or place sqlite3.exe in the lib folder."
    }

    # Ensure data directory exists
    $dataDir = Split-Path $DbPath -Parent
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }

    # Substitute parameters
    $execQuery = $Query
    foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]
        if ($null -eq $value) {
            $execQuery = $execQuery -replace "@$key", "NULL"
        } elseif ($value -is [int] -or $value -is [double] -or $value -is [long]) {
            $execQuery = $execQuery -replace "@$key", "$value"
        } else {
            $escaped = $value.ToString().Replace("'", "''")
            $execQuery = $execQuery -replace "@$key", "'$escaped'"
        }
    }

    # Execute query
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        $execQuery | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline

        if ($Query -match '^\s*(SELECT|PRAGMA)') {
            $output = & $sqlite3 -header -separator "`t" $DbPath ".read `"$tempFile`"" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "SQLite error: $output"
            }

            # Parse output into objects
            $lines = $output -split "`n" | Where-Object { $_ -match '\S' }
            if ($lines.Count -eq 0) {
                return @()
            }

            $headers = $lines[0] -split "`t"
            $results = @()

            for ($i = 1; $i -lt $lines.Count; $i++) {
                $values = $lines[$i] -split "`t"
                $obj = [ordered]@{}
                for ($j = 0; $j -lt $headers.Count; $j++) {
                    $obj[$headers[$j]] = if ($j -lt $values.Count) { $values[$j] } else { $null }
                }
                $results += [PSCustomObject]$obj
            }

            if ($Scalar -and $results.Count -gt 0) {
                $firstProp = ($results[0].PSObject.Properties | Select-Object -First 1).Name
                return $results[0].$firstProp
            }

            return $results
        } else {
            # For INSERT, we need to get last_insert_rowid in the same session
            if ($Query -match 'INSERT') {
                # Append SELECT last_insert_rowid() to the query
                $fullQuery = $execQuery.TrimEnd(';', ' ', "`n", "`r") + "; SELECT last_insert_rowid();"
                $fullQuery | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline

                $output = & $sqlite3 $DbPath ".read `"$tempFile`"" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "SQLite error: $output"
                }
                # The output should contain the last inserted ID
                $lastId = ($output | Select-Object -Last 1).Trim()
                if ($lastId -match '^\d+$') {
                    return [int]$lastId
                }
                return 0
            } else {
                $output = & $sqlite3 $DbPath ".read `"$tempFile`"" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "SQLite error: $output"
                }
            }
        }
    } finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

function Initialize-Database {
    [CmdletBinding()]
    param([switch]$Force)

    $result = @{ success = $true; data = $null; message = "" }

    try {
        $sqlite3 = Get-Sqlite3Path
        if (-not $sqlite3) {
            throw "sqlite3 not found. Please install SQLite."
        }

        # Create sessions table
        Invoke-SqliteQuery -Query @"
CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trello_id TEXT NOT NULL,
    card_title TEXT,
    start_time TEXT NOT NULL,
    end_time TEXT,
    duration_minutes REAL,
    description TEXT,
    auto_stopped INTEGER DEFAULT 0,
    start_commit TEXT,
    end_commit TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);
"@

        # Create progress_points table
        Invoke-SqliteQuery -Query @"
CREATE TABLE IF NOT EXISTS progress_points (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    timestamp TEXT NOT NULL,
    point_type TEXT NOT NULL,
    summary TEXT NOT NULL,
    details TEXT,
    git_commit_hash TEXT,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
"@

        # Create activity_logs table
        Invoke-SqliteQuery -Query @"
CREATE TABLE IF NOT EXISTS activity_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    timestamp TEXT NOT NULL,
    activity TEXT NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
"@

        # Create context_snapshots table
        Invoke-SqliteQuery -Query @"
CREATE TABLE IF NOT EXISTS context_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    timestamp TEXT NOT NULL,
    snapshot_type TEXT NOT NULL,
    git_branch TEXT,
    git_status TEXT,
    working_directory TEXT,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);
"@

        # Create indexes
        Invoke-SqliteQuery -Query "CREATE INDEX IF NOT EXISTS idx_sessions_trello ON sessions(trello_id);"
        Invoke-SqliteQuery -Query "CREATE INDEX IF NOT EXISTS idx_sessions_time ON sessions(start_time);"
        Invoke-SqliteQuery -Query "CREATE INDEX IF NOT EXISTS idx_progress_session ON progress_points(session_id);"
        Invoke-SqliteQuery -Query "CREATE INDEX IF NOT EXISTS idx_activity_session ON activity_logs(session_id);"
        Invoke-SqliteQuery -Query "CREATE INDEX IF NOT EXISTS idx_context_session ON context_snapshots(session_id);"

        # Create views (drop first to allow updates)
        Invoke-SqliteQuery -Query "DROP VIEW IF EXISTS daily_summary;"
        Invoke-SqliteQuery -Query @"
CREATE VIEW daily_summary AS
SELECT date(start_time) as work_date, trello_id, card_title,
       SUM(duration_minutes) as total_minutes, COUNT(*) as sessions
FROM sessions WHERE duration_minutes > 0
GROUP BY date(start_time), trello_id;
"@

        Invoke-SqliteQuery -Query "DROP VIEW IF EXISTS weekly_summary;"
        Invoke-SqliteQuery -Query @"
CREATE VIEW weekly_summary AS
SELECT strftime('%Y-W%W', start_time) as work_week, trello_id,
       SUM(duration_minutes) as total_minutes, COUNT(*) as sessions
FROM sessions WHERE duration_minutes > 0
GROUP BY strftime('%Y-W%W', start_time), trello_id;
"@

        $result.message = "Database initialized successfully at $script:DbPath"
        $result.data = @{ path = $script:DbPath }
    } catch {
        $result.success = $false
        $result.message = "Failed to initialize database: $($_.Exception.Message)"
    }

    return $result
}

# ============== SESSION FUNCTIONS ==============

function Add-Session {
    param(
        [Parameter(Mandatory)]
        [string]$TrelloId,
        [string]$CardTitle,
        [Parameter(Mandatory)]
        [string]$StartTime,
        [string]$StartCommit,
        [string]$Description
    )

    $params = @{
        trello_id = $TrelloId
        card_title = $CardTitle
        start_time = $StartTime
        start_commit = $StartCommit
        description = $Description
    }

    $id = Invoke-SqliteQuery -Query @"
INSERT INTO sessions (trello_id, card_title, start_time, start_commit, description)
VALUES (@trello_id, @card_title, @start_time, @start_commit, @description);
"@ -Parameters $params

    return $id
}

function Update-Session {
    param(
        [Parameter(Mandatory)]
        [int]$SessionId,
        [string]$EndTime,
        [double]$DurationMinutes,
        [string]$Description,
        [int]$AutoStopped,
        [string]$EndCommit
    )

    $setClauses = @()
    $params = @{ id = $SessionId }

    if ($PSBoundParameters.ContainsKey('EndTime')) {
        $setClauses += "end_time = @end_time"
        $params['end_time'] = $EndTime
    }
    if ($PSBoundParameters.ContainsKey('DurationMinutes')) {
        $setClauses += "duration_minutes = @duration"
        $params['duration'] = $DurationMinutes
    }
    if ($PSBoundParameters.ContainsKey('Description')) {
        $setClauses += "description = @description"
        $params['description'] = $Description
    }
    if ($PSBoundParameters.ContainsKey('AutoStopped')) {
        $setClauses += "auto_stopped = @auto_stopped"
        $params['auto_stopped'] = $AutoStopped
    }
    if ($PSBoundParameters.ContainsKey('EndCommit')) {
        $setClauses += "end_commit = @end_commit"
        $params['end_commit'] = $EndCommit
    }

    if ($setClauses.Count -gt 0) {
        $query = "UPDATE sessions SET $($setClauses -join ', ') WHERE id = @id;"
        Invoke-SqliteQuery -Query $query -Parameters $params
    }
}

function Get-Sessions {
    param(
        [int]$SessionId,
        [string]$TrelloId,
        [DateTime]$StartDate,
        [DateTime]$EndDate,
        [int]$Limit = 100,
        [switch]$ActiveOnly
    )

    $whereClauses = @()
    $params = @{}

    if ($SessionId) {
        $whereClauses += "id = @id"
        $params['id'] = $SessionId
    }
    if ($TrelloId) {
        $whereClauses += "UPPER(trello_id) = UPPER(@trello_id)"
        $params['trello_id'] = $TrelloId
    }
    if ($StartDate) {
        $whereClauses += "start_time >= @start_date"
        $params['start_date'] = $StartDate.ToString("yyyy-MM-dd")
    }
    if ($EndDate) {
        $whereClauses += "start_time <= @end_date"
        $params['end_date'] = $EndDate.ToString("yyyy-MM-dd 23:59:59")
    }
    if ($ActiveOnly) {
        $whereClauses += "end_time IS NULL"
    }

    $whereClause = if ($whereClauses.Count -gt 0) { "WHERE $($whereClauses -join ' AND ')" } else { "" }

    $query = "SELECT * FROM sessions $whereClause ORDER BY start_time DESC LIMIT $Limit;"
    return Invoke-SqliteQuery -Query $query -Parameters $params
}

function Get-ActiveSession {
    $result = Invoke-SqliteQuery -Query "SELECT * FROM sessions WHERE end_time IS NULL ORDER BY start_time DESC LIMIT 1;"
    if ($result -and $result.Count -gt 0) {
        return $result[0]
    }
    return $null
}

function Get-ActiveSessionFromDb {
    return Get-ActiveSession
}

# ============== PROGRESS POINT FUNCTIONS ==============

function Add-ProgressPoint {
    param(
        [Parameter(Mandatory)]
        [int]$SessionId,
        [Parameter(Mandatory)]
        [string]$Timestamp,
        [Parameter(Mandatory)]
        [ValidateSet('milestone', 'checkpoint', 'git_commit', 'note')]
        [string]$PointType,
        [Parameter(Mandatory)]
        [string]$Summary,
        [string]$Details,
        [string]$GitCommitHash
    )

    $params = @{
        session_id = $SessionId
        timestamp = $Timestamp
        point_type = $PointType
        summary = $Summary
        details = $Details
        git_commit_hash = $GitCommitHash
    }

    $id = Invoke-SqliteQuery -Query @"
INSERT INTO progress_points (session_id, timestamp, point_type, summary, details, git_commit_hash)
VALUES (@session_id, @timestamp, @point_type, @summary, @details, @git_commit_hash);
"@ -Parameters $params

    return $id
}

function Get-ProgressPoints {
    param(
        [int]$SessionId,
        [string]$PointType,
        [int]$Limit = 100
    )

    $whereClauses = @()
    $params = @{}

    if ($SessionId) {
        $whereClauses += "session_id = @session_id"
        $params['session_id'] = $SessionId
    }
    if ($PointType) {
        $whereClauses += "point_type = @point_type"
        $params['point_type'] = $PointType
    }

    $whereClause = if ($whereClauses.Count -gt 0) { "WHERE $($whereClauses -join ' AND ')" } else { "" }

    $query = "SELECT * FROM progress_points $whereClause ORDER BY timestamp ASC LIMIT $Limit;"
    return Invoke-SqliteQuery -Query $query -Parameters $params
}

# ============== ACTIVITY LOG FUNCTIONS ==============

function Add-ActivityLog {
    param(
        [Parameter(Mandatory)]
        [int]$SessionId,
        [Parameter(Mandatory)]
        [string]$Timestamp,
        [Parameter(Mandatory)]
        [string]$Activity
    )

    $params = @{
        session_id = $SessionId
        timestamp = $Timestamp
        activity = $Activity
    }

    $id = Invoke-SqliteQuery -Query @"
INSERT INTO activity_logs (session_id, timestamp, activity)
VALUES (@session_id, @timestamp, @activity);
"@ -Parameters $params

    return $id
}

function Get-ActivityLogs {
    param(
        [Parameter(Mandatory)]
        [int]$SessionId,
        [int]$Limit = 100
    )

    $query = "SELECT * FROM activity_logs WHERE session_id = @session_id ORDER BY timestamp ASC LIMIT $Limit;"
    return Invoke-SqliteQuery -Query $query -Parameters @{ session_id = $SessionId }
}

# ============== CONTEXT SNAPSHOT FUNCTIONS ==============

function Add-ContextSnapshot {
    param(
        [Parameter(Mandatory)]
        [int]$SessionId,
        [Parameter(Mandatory)]
        [string]$Timestamp,
        [Parameter(Mandatory)]
        [ValidateSet('start', 'checkpoint', 'end')]
        [string]$SnapshotType,
        [string]$GitBranch,
        [string]$GitStatus,
        [string]$WorkingDirectory
    )

    $params = @{
        session_id = $SessionId
        timestamp = $Timestamp
        snapshot_type = $SnapshotType
        git_branch = $GitBranch
        git_status = $GitStatus
        working_directory = $WorkingDirectory
    }

    $id = Invoke-SqliteQuery -Query @"
INSERT INTO context_snapshots (session_id, timestamp, snapshot_type, git_branch, git_status, working_directory)
VALUES (@session_id, @timestamp, @snapshot_type, @git_branch, @git_status, @working_directory);
"@ -Parameters $params

    return $id
}

function Get-ContextSnapshots {
    param(
        [int]$SessionId,
        [string]$SnapshotType,
        [int]$Limit = 100
    )

    $whereClauses = @()
    $params = @{}

    if ($SessionId) {
        $whereClauses += "session_id = @session_id"
        $params['session_id'] = $SessionId
    }
    if ($SnapshotType) {
        $whereClauses += "snapshot_type = @snapshot_type"
        $params['snapshot_type'] = $SnapshotType
    }

    $whereClause = if ($whereClauses.Count -gt 0) { "WHERE $($whereClauses -join ' AND ')" } else { "" }

    $query = "SELECT * FROM context_snapshots $whereClause ORDER BY timestamp DESC LIMIT $Limit;"
    return Invoke-SqliteQuery -Query $query -Parameters $params
}

# ============== SUMMARY FUNCTIONS ==============

function Get-DailySummary {
    param(
        [DateTime]$Date = (Get-Date),
        [string]$TrelloId
    )

    $params = @{ work_date = $Date.ToString("yyyy-MM-dd") }
    $whereClause = "WHERE work_date = @work_date"

    if ($TrelloId) {
        $whereClause += " AND UPPER(trello_id) = UPPER(@trello_id)"
        $params['trello_id'] = $TrelloId
    }

    $query = "SELECT * FROM daily_summary $whereClause;"
    return Invoke-SqliteQuery -Query $query -Parameters $params
}

function Get-WeeklySummary {
    param(
        [DateTime]$WeekStart = (Get-Date),
        [string]$TrelloId
    )

    $workWeek = $WeekStart.ToString("yyyy") + "-W" + (Get-Date $WeekStart -UFormat "%V")
    $params = @{ work_week = $workWeek }
    $whereClause = "WHERE work_week = @work_week"

    if ($TrelloId) {
        $whereClause += " AND UPPER(trello_id) = UPPER(@trello_id)"
        $params['trello_id'] = $TrelloId
    }

    $query = "SELECT * FROM weekly_summary $whereClause;"
    return Invoke-SqliteQuery -Query $query -Parameters $params
}

function Get-LastCheckpointCommit {
    param([int]$SessionId)

    $result = Invoke-SqliteQuery -Query @"
SELECT git_commit_hash FROM progress_points
WHERE session_id = @session_id AND git_commit_hash IS NOT NULL AND git_commit_hash != ''
ORDER BY timestamp DESC LIMIT 1;
"@ -Parameters @{ session_id = $SessionId }

    if ($result) {
        # Handle both single object and array results
        if ($result -is [array]) {
            return $result[0].git_commit_hash
        } else {
            return $result.git_commit_hash
        }
    }

    # Fallback to session start commit
    $session = Get-Sessions -SessionId $SessionId
    if ($session) {
        if ($session -is [array]) {
            return $session[0].start_commit
        } else {
            return $session.start_commit
        }
    }

    return $null
}

function Get-LastCheckpointTime {
    param([int]$SessionId)

    $result = Invoke-SqliteQuery -Query @"
SELECT timestamp FROM progress_points
WHERE session_id = @session_id AND point_type = 'checkpoint'
ORDER BY timestamp DESC LIMIT 1;
"@ -Parameters @{ session_id = $SessionId }

    if ($result) {
        # Handle both single object and array results
        if ($result -is [array]) {
            return $result[0].timestamp
        } else {
            return $result.timestamp
        }
    }

    return $null
}

function Get-AllSessions {
    param(
        [int]$Limit = 1000,
        [switch]$IncludeZeroDuration
    )

    $whereClause = if (-not $IncludeZeroDuration) { "WHERE duration_minutes > 0" } else { "" }
    $query = "SELECT * FROM sessions $whereClause ORDER BY start_time DESC LIMIT $Limit;"
    return Invoke-SqliteQuery -Query $query
}

function Get-SessionsByDateRange {
    param(
        [Parameter(Mandatory)]
        [DateTime]$StartDate,
        [Parameter(Mandatory)]
        [DateTime]$EndDate
    )

    $params = @{
        start_date = $StartDate.ToString("yyyy-MM-dd")
        end_date = $EndDate.ToString("yyyy-MM-dd 23:59:59")
    }

    $query = "SELECT * FROM sessions WHERE start_time >= @start_date AND start_time <= @end_date ORDER BY start_time ASC;"
    return Invoke-SqliteQuery -Query $query -Parameters $params
}

# Make functions available when dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Running directly - export for testing
    Write-Host "TimeTrackingAgent Database Module loaded" -ForegroundColor Cyan
    Write-Host "Available functions: Initialize-Database, Add-Session, Update-Session, Get-Sessions, etc." -ForegroundColor Gray
}
