param(
    [ValidateRange(1, 65535)][int]$BackendPort = 8000,
    [ValidateRange(1, 65535)][int]$FrontendPort = 3000
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$backendDirectory = Join-Path $projectRoot "backend"
$frontendDirectory = Join-Path $projectRoot "frontend"
$pythonPath = Join-Path $backendDirectory ".venv\Scripts\python.exe"
$dataDirectory = Join-Path $projectRoot ".data"
$processFile = Join-Path $dataDirectory "processes.json"
$nextPath = Join-Path $frontendDirectory "node_modules\next\dist\bin\next"

if (-not (Test-Path -LiteralPath $pythonPath)) { throw "Install backend dependencies first (see README)." }
if (-not (Test-Path -LiteralPath (Join-Path $frontendDirectory ".next\BUILD_ID"))) {
    throw "Run npm ci and npm run build in frontend first."
}
if (Test-Path -LiteralPath $processFile) {
    $saved = Get-Content -LiteralPath $processFile -Raw | ConvertFrom-Json
    foreach ($entry in @($saved.backend, $saved.frontend)) {
        $running = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
        if ($running -and $running.StartTime.ToUniversalTime().ToString("o") -eq $entry.started) {
            throw "The project is already running. Use scripts/stop_project.ps1 before restarting."
        }
    }
}

$portableNode = Get-ChildItem -LiteralPath (Join-Path $projectRoot ".tools") -Directory -Filter "node-*-win-x64" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($portableNode) {
    $nodePath = Join-Path $portableNode.FullName "node.exe"
    $env:PATH = "$($portableNode.FullName);$env:PATH"
} else {
    $nodePath = (Get-Command node.exe -ErrorAction Stop).Source
}

New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
$env:PYTHONIOENCODING = "utf-8"
$env:HF_HOME = Join-Path $dataDirectory "huggingface"
$env:NEXT_PUBLIC_API_BASE_URL = "http://127.0.0.1:$BackendPort"
$env:NEXT_TELEMETRY_DISABLED = "1"

Push-Location $projectRoot
try {
    & docker compose up -d postgres etcd minio milvus
    if ($LASTEXITCODE -ne 0) { throw "Docker infrastructure startup failed." }
} finally { Pop-Location }

Write-Host "Waiting for PostgreSQL and Milvus..."
$ready = $false
for ($attempt = 0; $attempt -lt 90; $attempt++) {
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        try { $tcp.Connect("127.0.0.1", 5432) } finally { $tcp.Dispose() }
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:9091/healthz" -TimeoutSec 2
        if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Seconds 1 }
}
if (-not $ready) { throw "Infrastructure is not ready. Check docker compose logs." }

$backendProcess = $null
$frontendProcess = $null
try {
    $backendProcess = Start-Process -FilePath $pythonPath `
        -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "$BackendPort") `
        -WorkingDirectory $backendDirectory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $dataDirectory "backend.out.log") `
        -RedirectStandardError (Join-Path $dataDirectory "backend.err.log")

    $backendReady = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        if ($backendProcess.HasExited) { throw "Backend exited. Check .data/backend.err.log." }
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$BackendPort/health" -TimeoutSec 2
            if ($health.status -eq "ok") { $backendReady = $true; break }
        } catch { Start-Sleep -Seconds 1 }
    }
    if (-not $backendReady) { throw "Backend startup timed out. Check .data/backend.err.log." }

    $frontendProcess = Start-Process -FilePath $nodePath `
        -ArgumentList @("`"$nextPath`"", "start", "-H", "127.0.0.1", "-p", "$FrontendPort") `
        -WorkingDirectory $frontendDirectory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $dataDirectory "frontend.out.log") `
        -RedirectStandardError (Join-Path $dataDirectory "frontend.err.log")

    $frontendReady = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($frontendProcess.HasExited) { throw "Frontend exited. Check .data/frontend.err.log." }
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$FrontendPort" -TimeoutSec 2 | Out-Null
            $frontendReady = $true; break
        } catch { Start-Sleep -Seconds 1 }
    }
    if (-not $frontendReady) { throw "Frontend startup timed out. Check .data/frontend.err.log." }

    @{
        backend = @{ pid = $backendProcess.Id; started = $backendProcess.StartTime.ToUniversalTime().ToString("o") }
        frontend = @{ pid = $frontendProcess.Id; started = $frontendProcess.StartTime.ToUniversalTime().ToString("o") }
        backend_port = $BackendPort; frontend_port = $FrontendPort
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $processFile -Encoding UTF8
    Write-Host "DevFlow AI is running: http://localhost:$FrontendPort"
    Write-Host "API: http://127.0.0.1:$BackendPort/docs"
    Write-Host "Logs: $dataDirectory"
} catch {
    if ($frontendProcess -and -not $frontendProcess.HasExited) { Stop-Process -Id $frontendProcess.Id }
    if ($backendProcess -and -not $backendProcess.HasExited) { Stop-Process -Id $backendProcess.Id }
    throw
}
