# Time Tracking System Analysis

## Purpose
This document provides a comprehensive overview of the local time-tracking system to allow agents to interact with it immediately without re-analyzing the source scripts.

## Core System Components
- **Scripts Directory:** `.agent/TimeTrackingAgent/scripts/`
- **Data Directory:** `.agent/TimeTrackingAgent/data/`
- **History File:** `.agent/TimeTrackingAgent/data/history.jsonl` (JSON Lines format)
- **Active Session:** `.agent/TimeTrackingAgent/data/active_session.json` (JSON)
- **Activity Log:** `.agent/TimeTrackingAgent/data/session_activity.log` (Plain text, unique work entries)

## Operational Commands

### 1. Start a Timer
Use this when beginning a new task or resuming work.
- **Script:** `.agent/TimeTrackingAgent/scripts/start-clock.ps1`
- **Usage:** `powershell -File .agent/TimeTrackingAgent/scripts/start-clock.ps1 -TrelloId "T123" -Description "Initial work description"`
- **Effect:** Creates `active_session.json` and initializes `session_activity.log`.

### 2. Record Activity (CRITICAL)
Agents **must** log their progress by appending unique lines to the activity log. This log is aggregated when the clock stops.
- **Log File:** `.agent/TimeTrackingAgent/data/session_activity.log`
- **Action:** Append a concise description of the completed sub-task.

### 3. Maintain Heartbeat
Prevents the session from being automatically timed out.
- **Script:** `.agent/TimeTrackingAgent/scripts/heartbeat.ps1`
- **Frequency:** Run periodically (e.g., every 5-10 minutes).
- **Auto-Stop:** If inactive for >15 minutes, the heartbeat script will trigger an auto-stop at the last known active time + 15 mins.

### 4. Stop a Timer
Use this when a task is completed or pausing for a break.
- **Script:** `.agent/TimeTrackingAgent/scripts/stop-clock.ps1`
- **Effect:**
    1. Reads `session_activity.log`, joins unique lines.
    2. Calculates duration.
    3. Appends entry to `history.jsonl`.
    4. Posts comment to Trello (if configured).
    5. Cleans up session files.

### 5. View Reports
- **Scripts:** 
    - `.agent/TimeTrackingAgent/scripts/timesheet.ps1` (Summary)
    - `.agent/TimeTrackingAgent/scripts/detailed-timesheet.ps1` (Full breakdown with activities)

## Integration Details
- **Trello:** API integration exists in `trello-api.ps1`. It maps Trello IDs to card names and handles automated commenting.
- **Persistence:** All data is local and stored in `.agent/TimeTrackingAgent/data/`.
- **Aliases:** `init.ps1` provides aliases `start-time`, `stop-time`, and `history-md` if sourced in a PowerShell environment.
