function Get-TrelloConfig {
    $configPath = Join-Path $PSScriptRoot "..\trello_secrets.json"
    if (Test-Path $configPath) {
        return Get-Content $configPath | ConvertFrom-Json
    }
    return $null
}

function Invoke-TrelloRequest {
    param(
        [string]$Method,
        [string]$Endpoint,
        [hashtable]$Body = $null
    )
    $config = Get-TrelloConfig
    if (-not $config) {
        return $null
    }

    $url = "https://api.trello.com/1/($Endpoint)?key=($config.Key)&token=($config.Token)"
    
    if ($Method -eq "Get" -and $Body) {
        foreach ($key in $Body.Keys) {
            $url += "&($key)=($Body[$key])"
        }
        $Body = $null
    }

    $params = @{
        Method = $Method
        Uri = $url
        ContentType = "application/json"
    }
    if ($Body) {
        $params.Body = $Body | ConvertTo-Json
    }

    return Invoke-RestMethod @params
}

function Get-TrelloCard {
    param([string]$CardId)
    return Invoke-TrelloRequest -Method Get -Endpoint "cards/$CardId"
}

function Add-TrelloComment {
    param(
        [string]$CardId,
        [string]$Text
    )
    return Invoke-TrelloRequest -Method Post -Endpoint "cards/$CardId/actions/comments" -Body @{ text = $Text }
}

function Search-TrelloCards {
    param([string]$Query)
    return Invoke-TrelloRequest -Method Get -Endpoint "search" -Body @{ query = $Query; cards_limit = 10 }
}
