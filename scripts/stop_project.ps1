$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$processFile = Join-Path $projectRoot ".data\processes.json"
if (-not (Test-Path -LiteralPath $processFile)) { Write-Host "No saved application processes."; return }
$saved = Get-Content -LiteralPath $processFile -Raw | ConvertFrom-Json
foreach ($entry in @($saved.frontend, $saved.backend)) {
    $running = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
    # Protect against Windows reusing a PID after an earlier process exited.
    if ($running -and $running.StartTime.ToUniversalTime().Ticks -eq $entry.started_ticks) {
        & taskkill.exe /PID $entry.pid /T /F | Out-Null
        Write-Host "Stopped application process $($entry.pid)."
    }
}
Remove-Item -LiteralPath $processFile
Write-Host "Docker services are retained. Run docker compose stop to stop them too."
