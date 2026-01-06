# Timesheet Command
# Quick command to view time tracking reports
# Usage: 
#   timesheet           - Show summary report
#   timesheet -d        - Show detailed report
#   timesheet t616      - Show report for specific Trello ID
#   timesheet t616 -d   - Show detailed report for specific Trello ID

param(
    [Parameter(Position=0)]
    [string]$TrelloId,
    
    [Alias("d")]
    [switch]$Detailed
)

$reportScript = Join-Path $PSScriptRoot "time-report.ps1"

# Build parameters for the report script
$params = @{}
if ($Detailed) {
    $params['Detailed'] = $true
}
if ($TrelloId) {
    $params['TrelloId'] = $TrelloId
}

# Execute the report
& $reportScript @params
