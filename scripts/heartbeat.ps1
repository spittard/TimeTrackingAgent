$sessionFile = Join-Path $PSScriptRoot "..\data\active_session.json"
if (Test-Path $sessionFile) {
    try {
        $json = Get-Content $sessionFile -Raw | ConvertFrom-Json
        $timeStr = if ($json.LastUpdate) { $json.LastUpdate } else { $json.StartTime }
        
        # Robust parsing for yyyy-MM-dd HH:mm:ss
        if ($timeStr -match '(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})') {
            $lastUpdate = Get-Date -Year $matches[1] -Month $matches[2] -Day $matches[3] -Hour $matches[4] -Minute $matches[5] -Second $matches[6]
            $now = Get-Date
            $diffMin = ($now - $lastUpdate).TotalMinutes
            
            if ($diffMin -gt 15) {
                $autoEndTime = $lastUpdate.AddMinutes(15)
                & "$PSScriptRoot\stop-clock.ps1" -TrelloId $json.TrelloId -EndTimeOverride $autoEndTime
                Write-Host "AUTO_STOPPED:$($json.TrelloId)"
            } else {
                $newData = @{
                    TrelloId = $json.TrelloId
                    StartTime = $json.StartTime
                    LastUpdate = $now.ToString("yyyy-MM-dd HH:mm:ss")
                    StartCommit = $json.StartCommit
                } | ConvertTo-Json
                $newData | Out-File -FilePath $sessionFile -Encoding utf8
            }
        }
    } catch {
        Write-Warning "Heartbeat error: $_"
    }
}
