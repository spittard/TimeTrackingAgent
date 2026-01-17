---
description: How to use the local time-tracking system
---

# Time Tracking Workflow

This guide explains how to track your work time using the TimeTrackingAgent system.

## Quick Start

### Initialize (First Time)
```powershell
# Source the init script
. .\scripts\init.ps1

# Migrate existing history (if upgrading from JSONL)
.\scripts\migrate-history.ps1
```

## Basic Workflow

### 1. Start Tracking
When you begin a task, start the clock:
```powershell
.\scripts\start-clock.ps1 -TrelloId "T123" -Description "Working on feature X"
# Or with alias: start-time T123 "Working on feature X"
```

### 2. Log Progress
Record milestones as you work:
```powershell
.\scripts\add-progress.ps1 -Type milestone -Summary "Completed database schema"
# Or with alias: progress -Type milestone -Summary "Completed database schema"
```

Add notes for important context:
```powershell
.\scripts\add-progress.ps1 -Type note -Summary "Found issue with legacy code"
```

### 3. Maintain Session (Heartbeat)
The system auto-captures checkpoints every 30 minutes and detects git commits.
Run the heartbeat periodically to prevent auto-stop:
```powershell
.\scripts\auto-checkpoint.ps1
# Or with alias: checkpoint
```

Sessions auto-stop after 15 minutes of inactivity.

### 4. Stop Tracking
When you finish or take a break:
```powershell
.\scripts\stop-clock.ps1
# Or with alias: stop-time
```

## Reports

### View Timesheet
```powershell
.\scripts\timesheet.ps1
# Or: .\scripts\timesheet.ps1 -Detailed
```

### Generate Reports
```powershell
# Daily report
.\scripts\generate-report.ps1 -Type daily

# Weekly report
.\scripts\generate-report.ps1 -Type weekly

# Project report
.\scripts\generate-report.ps1 -Type project -TrelloId "T123"
```

## AI Agent Features

### Get Context for Resume
```powershell
.\scripts\get-context.ps1 -Type resume
```

### Get Current Session Context
```powershell
.\scripts\get-context.ps1 -Type current
```

### Handoff to Another Agent
```powershell
.\scripts\get-context.ps1 -Type handoff -AsJson
```

### Summarize Session
```powershell
.\scripts\summarize-session.ps1 -Active
.\scripts\summarize-session.ps1 -ForTrello
```

## Database Management

### Backup
```powershell
.\scripts\backup-db.ps1
.\scripts\backup-db.ps1 -List
```

### Restore
```powershell
.\scripts\backup-db.ps1 -Restore
```

---
*For complete documentation, see [time-tracking-docs.md](../time-tracking-docs.md)*
