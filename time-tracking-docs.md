# Time Tracking System Documentation

## Overview
TimeTrackingAgent is a comprehensive time-tracking system designed for AI agent integration. It provides:
- **SQLite persistence** for data integrity and rich querying
- **Progress points** with auto-capture of git commits and periodic checkpoints
- **Markdown reports** for comprehensive, portable documentation
- **Context engineering** features for AI agent handoff and resume

## System Architecture

### Directory Structure
```
TimeTrackingAgent/
  scripts/
    # Core
    init.ps1              # Initialization and aliases
    start-clock.ps1       # Start a time tracking session
    stop-clock.ps1        # Stop the active session
    heartbeat.ps1         # Backward-compatible heartbeat

    # Database
    db.ps1                # SQLite abstraction layer
    migrate-history.ps1   # JSONL to SQLite migration
    backup-db.ps1         # Database backup utility

    # Progress Points
    add-progress.ps1      # Manual progress capture
    auto-checkpoint.ps1   # Enhanced heartbeat with git detection
    get-progress.ps1      # Query progress points

    # Reporting
    generate-report.ps1   # Multi-type markdown reports
    time-report.ps1       # Legacy time report
    timesheet.ps1         # Quick timesheet view
    detailed-timesheet.ps1

    # Context Engineering
    get-context.ps1       # AI context retrieval
    capture-context.ps1   # Context snapshots
    summarize-session.ps1 # Session summaries

    # Utilities
    view-history.ps1
    clean-history.ps1
    trello-api.ps1
    setup-trello.ps1

  data/
    timetracking.db       # SQLite database
    active_session.json   # Active session (runtime)
    session_activity.log  # Activity log (runtime)
    history.jsonl         # Legacy backup
    backups/              # Database backups

  templates/
    report-daily.md
    report-weekly.md
    report-session.md
    report-project.md
    context-current.md
    context-resume.md
    context-handoff.md
```

## Quick Start

### Initialize the System
```powershell
# Source the init script to enable aliases
. .\scripts\init.ps1

# Migrate existing history (if upgrading)
.\scripts\migrate-history.ps1
```

### Basic Workflow
```powershell
# Start tracking time
start-time T123 "Working on feature X"

# Add progress points as you work
progress -Type milestone -Summary "Completed authentication module"

# Periodic checkpoints happen automatically (every 30 min)
# Git commits are auto-captured

# Stop when done
stop-time
```

## Commands Reference

### Core Commands

#### start-clock.ps1
Start a new time tracking session.
```powershell
.\start-clock.ps1 -TrelloId "T123" [-Description "Task description"] [-AsJson]
```
- Creates session in SQLite database
- Captures initial git state
- Creates start checkpoint and context snapshot

#### stop-clock.ps1
Stop the active session.
```powershell
.\stop-clock.ps1 [-TrelloId "T123"] [-EndTimeOverride <DateTime>] [-AutoStopped] [-AsJson]
```
- Updates session with end time and duration
- Creates end checkpoint and context snapshot
- Posts summary to Trello (if configured)

#### heartbeat.ps1 / auto-checkpoint.ps1
Maintain session activity and create checkpoints.
```powershell
.\auto-checkpoint.ps1 [-StaleMinutes 15] [-CheckpointIntervalMinutes 30] [-AsJson]
```
- Updates LastUpdate timestamp
- Detects and records new git commits
- Creates periodic checkpoints (every 30 min)
- Auto-stops stale sessions (>15 min inactive)

### Progress Tracking

#### add-progress.ps1
Add manual progress points.
```powershell
.\add-progress.ps1 -Type <milestone|note> -Summary "Description" [-Details "Extra info"] [-AsJson]
```

#### get-progress.ps1
Query progress points.
```powershell
.\get-progress.ps1 [-SessionId <id>] [-Type <all|milestone|checkpoint|git_commit|note>] [-Active] [-AsJson]
```

### Reporting

#### generate-report.ps1
Generate comprehensive reports.
```powershell
# Daily report
.\generate-report.ps1 -Type daily [-Date <DateTime>] [-OutputPath "report.md"]

# Weekly report
.\generate-report.ps1 -Type weekly [-Date <DateTime>]

# Session report
.\generate-report.ps1 -Type session -SessionId <id>

# Project report
.\generate-report.ps1 -Type project -TrelloId "T123"

# Timeline report
.\generate-report.ps1 -Type timeline [-Days 7]
```

### Context Engineering

#### get-context.ps1
Retrieve context for AI agents.
```powershell
# Current session context
.\get-context.ps1 -Type current [-Format <json|markdown>]

# Resume context (last completed session)
.\get-context.ps1 -Type resume

# Handoff context (for agent transfer)
.\get-context.ps1 -Type handoff

# Full context (all data)
.\get-context.ps1 -Type full -AsJson
```

#### summarize-session.ps1
Generate session summaries.
```powershell
.\summarize-session.ps1 [-SessionId <id>] [-Active] [-ForTrello] [-ForHandoff] [-AsJson]
```

#### capture-context.ps1
Capture context snapshots.
```powershell
.\capture-context.ps1 [-Type <checkpoint|start|end>] [-SessionId <id>] [-AsJson]
```

### Database Operations

#### backup-db.ps1
Manage database backups.
```powershell
# Create backup
.\backup-db.ps1 [-KeepDays 7]

# List backups
.\backup-db.ps1 -List

# Restore from backup
.\backup-db.ps1 -Restore [-BackupFile "timetracking_20260117.db"]
```

#### migrate-history.ps1
Migrate JSONL history to SQLite.
```powershell
.\migrate-history.ps1 [-DryRun] [-Force] [-AsJson]
```

## Database Schema

### sessions
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| trello_id | TEXT | Trello card ID |
| card_title | TEXT | Card title |
| start_time | TEXT | Session start (ISO format) |
| end_time | TEXT | Session end |
| duration_minutes | REAL | Total duration |
| description | TEXT | Activity summary |
| auto_stopped | INTEGER | 1 if auto-stopped |
| start_commit | TEXT | Git commit at start |
| end_commit | TEXT | Git commit at end |

### progress_points
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| session_id | INTEGER | Foreign key to sessions |
| timestamp | TEXT | When recorded |
| point_type | TEXT | milestone/checkpoint/git_commit/note |
| summary | TEXT | Description |
| details | TEXT | JSON blob with extra data |
| git_commit_hash | TEXT | Associated commit |

### context_snapshots
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| session_id | INTEGER | Foreign key to sessions |
| timestamp | TEXT | When captured |
| snapshot_type | TEXT | start/checkpoint/end |
| git_branch | TEXT | Current branch |
| git_status | TEXT | JSON blob of git status |
| working_directory | TEXT | Working directory path |

## Progress Point Types

| Type | Trigger | Description |
|------|---------|-------------|
| checkpoint | Auto (every 30 min) | Periodic status capture |
| milestone | Manual | Significant accomplishments |
| git_commit | Auto (on new commits) | Git commit detection |
| note | Manual | Free-form annotations |

## AI Agent Integration

### For Claude Code / AI Assistants

#### Starting Work
```powershell
# Check for previous context
.\get-context.ps1 -Type resume

# Start new session
.\start-clock.ps1 -TrelloId "T123" -Description "Feature implementation"
```

#### During Work
```powershell
# Record milestones
.\add-progress.ps1 -Type milestone -Summary "Completed database schema"

# Heartbeat (run every 5-10 min)
.\auto-checkpoint.ps1
```

#### Stopping Work
```powershell
# Get summary
.\summarize-session.ps1 -Active

# Stop session
.\stop-clock.ps1
```

#### Handing Off to Another Agent
```powershell
# Get full handoff context
.\get-context.ps1 -Type handoff -AsJson > handoff.json
```

### Best Practices

1. **Record Milestones**: Call `add-progress.ps1` after completing significant steps
2. **Maintain Heartbeat**: Run `auto-checkpoint.ps1` every 5-10 minutes
3. **Use Context on Resume**: Always check `get-context.ps1 -Type resume` when starting
4. **Commit Often**: Git commits are auto-tracked as progress points

## Aliases

When `init.ps1` is sourced, these aliases are available:

| Alias | Command |
|-------|---------|
| start-time | start-clock.ps1 |
| stop-time | stop-clock.ps1 |
| checkpoint | auto-checkpoint.ps1 |
| progress | add-progress.ps1 |
| report | generate-report.ps1 |
| context | get-context.ps1 |
| timesheet | timesheet.ps1 |
| summarize | summarize-session.ps1 |
| backup-time | backup-db.ps1 |

## Dependencies

- **PowerShell 5.1+**
- **SQLite3** - Required for database operations
  - Install via Chocolatey: `choco install sqlite`
  - Or place `sqlite3.exe` in the `lib/` folder
- **Git** - For commit tracking (optional but recommended)
- **Trello API** - For card integration (optional)
