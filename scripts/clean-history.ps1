$historyFile = Join-Path $PSScriptRoot "..\data\history.jsonl"
if (Test-Path $historyFile) {
    $content = Get-Content $historyFile
    $validLines = @()
    foreach ($line in $content) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $line | ConvertFrom-Json | Out-Null
            $validLines += $line
        }
        catch {
            Write-Host "Skipping corrupted line: $line" -ForegroundColor Gray
        }
    }
    $validLines | Set-Content $historyFile -Force
}
