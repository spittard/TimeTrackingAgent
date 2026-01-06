param(
    [Parameter(Mandatory=$true)]
    [string]$Key,
    [Parameter(Mandatory=$true)]
    [string]$Token
)

$configPath = Join-Path $PSScriptRoot "..\trello_secrets.json"
$config = @{
    Key = $Key
    Token = $Token
} | ConvertTo-Json

$config | Out-File -FilePath $configPath -Encoding utf8
Write-Host "Trello credentials saved to .agent/trello_secrets.json"
