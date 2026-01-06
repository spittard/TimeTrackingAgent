function start-task { param($Id, $Desc) if ($Desc) { & "$PSScriptRoot\start-clock.ps1" -TrelloId $Id -Description $Desc } else { & "$PSScriptRoot\start-clock.ps1" -TrelloId $Id } }
function stop-task { param($Id) & "$PSScriptRoot\stop-clock.ps1" -TrelloId $Id }
function show-history { & "$PSScriptRoot\view-history.ps1" }

New-Alias -Name start-time -Value start-task -Force
New-Alias -Name stop-time -Value stop-task -Force
New-Alias -Name history-md -Value show-history -Force
