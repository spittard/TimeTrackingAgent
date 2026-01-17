# TimeTrackingAgent Initialization Script
# Source this file to enable time tracking aliases and functions

# Core timer functions
function start-task {
    param($Id, $Desc)
    if ($Desc) {
        & "$PSScriptRoot\start-clock.ps1" -TrelloId $Id -Description $Desc
    } else {
        & "$PSScriptRoot\start-clock.ps1" -TrelloId $Id
    }
}

function stop-task {
    param($Id)
    if ($Id) {
        & "$PSScriptRoot\stop-clock.ps1" -TrelloId $Id
    } else {
        & "$PSScriptRoot\stop-clock.ps1"
    }
}

function show-history { & "$PSScriptRoot\view-history.ps1" }

# Progress functions
function add-milestone {
    param([Parameter(Mandatory=$true)][string]$Summary, [string]$Details)
    if ($Details) {
        & "$PSScriptRoot\add-progress.ps1" -Type milestone -Summary $Summary -Details $Details
    } else {
        & "$PSScriptRoot\add-progress.ps1" -Type milestone -Summary $Summary
    }
}

function add-note {
    param([Parameter(Mandatory=$true)][string]$Summary)
    & "$PSScriptRoot\add-progress.ps1" -Type note -Summary $Summary
}

# Report functions
function daily-report {
    param([DateTime]$Date = (Get-Date))
    & "$PSScriptRoot\generate-report.ps1" -Type daily -Date $Date
}

function weekly-report {
    param([DateTime]$Date = (Get-Date))
    & "$PSScriptRoot\generate-report.ps1" -Type weekly -Date $Date
}

# Context functions
function current-context { & "$PSScriptRoot\get-context.ps1" -Type current }
function resume-context { & "$PSScriptRoot\get-context.ps1" -Type resume }

# Aliases
New-Alias -Name start-time -Value start-task -Force
New-Alias -Name stop-time -Value stop-task -Force
New-Alias -Name history-md -Value show-history -Force

# New aliases
Set-Alias -Name checkpoint -Value "$PSScriptRoot\auto-checkpoint.ps1" -Force
Set-Alias -Name progress -Value "$PSScriptRoot\add-progress.ps1" -Force
Set-Alias -Name report -Value "$PSScriptRoot\generate-report.ps1" -Force
Set-Alias -Name context -Value "$PSScriptRoot\get-context.ps1" -Force
Set-Alias -Name timesheet -Value "$PSScriptRoot\timesheet.ps1" -Force
Set-Alias -Name summarize -Value "$PSScriptRoot\summarize-session.ps1" -Force
Set-Alias -Name backup-time -Value "$PSScriptRoot\backup-db.ps1" -Force

Write-Host "TimeTrackingAgent initialized." -ForegroundColor Green
Write-Host "Commands: start-time, stop-time, progress, report, context, timesheet" -ForegroundColor Gray
