# Time Report Command
# Quick alias to generate time tracking reports

param(
    [switch]$Detailed,
    [string]$TrelloId
)

$scriptPath = Join-Path $PSScriptRoot "time-report.ps1"

if ($TrelloId) {
    & $scriptPath -TrelloId $TrelloId -Detailed:$Detailed
} else {
    & $scriptPath -Detailed:$Detailed
}
