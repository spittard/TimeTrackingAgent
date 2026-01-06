---
description: How to use the local time-tracking system
---

# Time Tracking Workflow

This guide explains how to track your work time using the local PowerShell scripts.

## Steps

### 1. Start Tracking
When you begin a task (usually associated with a Trello ID), start the clock:
// turbo
```powershell
powershell -File .agent/scripts/start-clock.ps1 -TrelloId "YOUR_TRELLO_ID" -Description "Initial task description"
```

### 2. Log Activity
As you work, log significant milestones or completed sub-tasks by appending to the activity log:
// turbo
```powershell
"Describe what you just finished" | Out-File -FilePath .agent/time_tracking/session_activity.log -Append -Encoding utf8
```

### 3. Maintain Session (Heartbeat)
The timer will auto-stop if no heartbeat is detected for 15 minutes. Run this periodically:
// turbo
```powershell
powershell -File .agent/scripts/heartbeat.ps1
```

### 4. Stop Tracking
When you finish or take a break, stop the clock:
// turbo
```powershell
powershell -File .agent/scripts/stop-clock.ps1
```

## Summary/Report
To see your total time:
// turbo
```powershell
powershell -File .agent/scripts/timesheet.ps1
```

---
*Note: For more details, see [.agent/time-tracking-docs.md](../time-tracking-docs.md)*
