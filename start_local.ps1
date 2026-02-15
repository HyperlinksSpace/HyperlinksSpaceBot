# ===== START LOCAL STACK (Windows, robust) =====
param(
  [switch]$Reload,
  [switch]$ForegroundBot,
  [switch]$StopOllama
)

$ErrorActionPreference = "Stop"
Write-Host "start_local.ps1: launching local stack..."

function Get-ListeningPids($port) {
  $lines = netstat -ano | findstr ":$port" | findstr "LISTENING"
  if (-not $lines) { return @() }
  $pids = @()
  foreach ($line in $lines) {
    $parts = ($line -split "\s+") | Where-Object { $_ -ne "" }
    if ($parts.Count -gt 0) {
      $procId = $parts[-1]
      if ($procId -match "^\d+$") { $pids += [int]$procId }
    }
  }
  return $pids | Sort-Object -Unique
}

function Stop-Pids([int[]]$pids, [string]$reason) {
  foreach ($procId in ($pids | Sort-Object -Unique)) {
    try {
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
      Write-Host "  Killed PID $procId ($reason)"
    } catch {}
  }
}

function Stop-BotProcesses {
  $botPids = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object CommandLine -Match "bot\.py" |
    Select-Object -ExpandProperty ProcessId -Unique
  Stop-Pids $botPids "bot.py"
}

function Stop-FrontendProcesses {
  $frontPids = Get-CimInstance Win32_Process -Filter "Name='flutter.bat'" |
    Where-Object CommandLine -Match "run -d web-server" |
    Select-Object -ExpandProperty ProcessId -Unique
  Stop-Pids $frontPids "flutter web-server"
}

function Wait-ForHttpReady {
  param(
    [string]$Uri,
    [int]$TimeoutSeconds = 25,
    [int]$IntervalMilliseconds = 500
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $null = Invoke-RestMethod -Uri $Uri -TimeoutSec 5
      return $true
    } catch {
      Start-Sleep -Milliseconds $IntervalMilliseconds
    }
  }
  return $false
}

$root = (Resolve-Path $PSScriptRoot).Path
$venvPython = Join-Path $root ".venv\Scripts\python.exe"

function Get-SystemPythonCommand {
  if (Get-Command py -ErrorAction SilentlyContinue) {
    return @("py", "-3")
  }
  if (Get-Command python -ErrorAction SilentlyContinue) {
    return @("python")
  }
  return $null
}

function Resolve-OllamaExecutable {
  $cmd = Get-Command ollama -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) {
    return $cmd.Source
  }
  $localAppData = [Environment]::GetFolderPath("LocalApplicationData")
  $candidates = @(
    "C:\Program Files\Ollama\ollama.exe",
    (Join-Path $localAppData "Programs\Ollama\ollama.exe"),
    (Join-Path $localAppData "Ollama\ollama.exe")
  )
  foreach ($path in $candidates) {
    if (Test-Path -LiteralPath $path) {
      return $path
    }
  }
  return $null
}

function Add-ToUserPathIfMissing {
  param(
    [string]$DirPath
  )
  if ([string]::IsNullOrWhiteSpace($DirPath)) {
    return
  }

  $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $parts = @()
  if (-not [string]::IsNullOrWhiteSpace($currentUserPath)) {
    $parts = $currentUserPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  }
  if (-not ($parts -contains $DirPath)) {
    $newPath = if ($parts.Count -eq 0) { $DirPath } else { ($parts + $DirPath) -join ";" }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "  Added to User PATH: $DirPath"
  }

  # Also update current process PATH so this shell can use ollama immediately.
  $processParts = ($env:Path -split ";") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if (-not ($processParts -contains $DirPath)) {
    $env:Path = "$env:Path;$DirPath"
    Write-Host "  Added to current session PATH: $DirPath"
  }
}

function Ensure-OllamaInstalled {
  $ollamaExe = Resolve-OllamaExecutable
  if (-not [string]::IsNullOrWhiteSpace($ollamaExe)) {
    Add-ToUserPathIfMissing -DirPath (Split-Path -Path $ollamaExe -Parent)
    return $ollamaExe
  }

  Write-Host "Ollama not found. Attempting install via winget..." -ForegroundColor Yellow
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "Ollama is not installed and winget is unavailable. Install Ollama manually from https://ollama.com/download/windows"
  }

  & winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) {
    throw "winget failed to install Ollama (exit code: $LASTEXITCODE). Install manually from https://ollama.com/download/windows"
  }

  $ollamaExe = Resolve-OllamaExecutable
  if ([string]::IsNullOrWhiteSpace($ollamaExe)) {
    throw "Ollama installation finished but executable was not found. Restart terminal or install manually."
  }

  Add-ToUserPathIfMissing -DirPath (Split-Path -Path $ollamaExe -Parent)
  return $ollamaExe
}

function Ensure-OllamaServerAndModel {
  param(
    [string]$OllamaExe,
    [string]$OllamaUrl,
    [string]$ModelName
  )

  if (-not (Wait-ForHttpReady -Uri "$($OllamaUrl.TrimEnd('/'))/api/tags" -TimeoutSeconds 3 -IntervalMilliseconds 500)) {
    Write-Host "Starting Ollama server..." -ForegroundColor Yellow
    Start-Process -FilePath $OllamaExe -ArgumentList "serve" -WindowStyle Hidden | Out-Null
    $ollamaUp = Wait-ForHttpReady -Uri "$($OllamaUrl.TrimEnd('/'))/api/tags" -TimeoutSeconds 40 -IntervalMilliseconds 1000
    if (-not $ollamaUp) {
      throw "Ollama server did not start at $OllamaUrl. Try running: `"$OllamaExe`" serve"
    }
  }

  Write-Host "Ensuring Ollama model is installed: $ModelName"
  & $OllamaExe pull $ModelName
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to pull Ollama model '$ModelName' (exit code: $LASTEXITCODE)"
  }
}

function Test-OllamaModelHealthy {
  param(
    [string]$OllamaUrl,
    [string]$ModelName
  )

  try {
    $resp = Invoke-RestMethod -Uri "$($OllamaUrl.TrimEnd('/'))/api/tags" -TimeoutSec 8
    $models = @($resp.models)
    foreach ($m in $models) {
      if ($null -ne $m -and $m.name -eq $ModelName) {
        return $true
      }
    }
  } catch {}
  return $false
}

function Ensure-VenvPython {
  param(
    [string]$RootPath,
    [string]$VenvPythonPath
  )

  if (Test-Path -LiteralPath $VenvPythonPath) {
    return
  }

  Write-Host "Missing virtualenv python: $VenvPythonPath" -ForegroundColor Yellow
  Write-Host "Attempting to bootstrap local virtualenv (.venv)..."

  $pyCmd = Get-SystemPythonCommand
  if (-not $pyCmd) {
    throw @"
Missing virtualenv python: $VenvPythonPath
Could not find system Python launcher.
Install Python 3 and ensure one of these works in shell:
  - py -3
  - python
"@
  }

  Push-Location $RootPath
  try {
    if ($pyCmd.Count -eq 2) {
      & $pyCmd[0] $pyCmd[1] -m venv ".venv"
    } else {
      & $pyCmd[0] -m venv ".venv"
    }
  } finally {
    Pop-Location
  }

  if (-not (Test-Path -LiteralPath $VenvPythonPath)) {
    throw @"
Missing virtualenv python: $VenvPythonPath
Auto-bootstrap failed.
Please run manually:
  py -3 -m venv .venv
Then install dependencies:
  .\.venv\Scripts\python.exe -m pip install -r bot\requirements.txt
  .\.venv\Scripts\python.exe -m pip install -r ai\backend\requirements.txt
  # Optional (only if file exists):
  .\.venv\Scripts\python.exe -m pip install -r rag\backend\requirements.txt
"@
  }

  function Install-RequirementsIfExists {
    param(
      [string]$RequirementsPath
    )
    if (Test-Path -LiteralPath $RequirementsPath) {
      Write-Host "  Installing: $RequirementsPath"
      & $VenvPythonPath -m pip install -r $RequirementsPath
    } else {
      Write-Host "  Skipping missing requirements: $RequirementsPath" -ForegroundColor Yellow
    }
  }

  Write-Host "Virtualenv created at .venv"
  Write-Host "Installing service dependencies..."
  Install-RequirementsIfExists -RequirementsPath (Join-Path $RootPath "bot\requirements.txt")
  Install-RequirementsIfExists -RequirementsPath (Join-Path $RootPath "ai\backend\requirements.txt")
  Install-RequirementsIfExists -RequirementsPath (Join-Path $RootPath "rag\backend\requirements.txt")
  Write-Host "Virtualenv bootstrap complete."
}

function Install-ServiceDependencies {
  param(
    [string]$RootPath,
    [string]$VenvPythonPath
  )

  function Invoke-PipInstallWithRetry {
    param(
      [string]$RequirementsPath,
      [int]$MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
      Write-Host "  pip install (attempt $attempt/$MaxAttempts): $RequirementsPath"
      & $VenvPythonPath -m pip install -r $RequirementsPath
      if ($LASTEXITCODE -eq 0) {
        return
      }
      if ($attempt -lt $MaxAttempts) {
        Write-Host "  pip install failed, retrying in 3s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
      }
    }
    throw "Failed to install requirements after $MaxAttempts attempts: $RequirementsPath"
  }

  function Install-RequirementsIfExistsAlways {
    param(
      [string]$RequirementsPath
    )
    if (Test-Path -LiteralPath $RequirementsPath) {
      Write-Host "Installing requirements: $RequirementsPath"
      Invoke-PipInstallWithRetry -RequirementsPath $RequirementsPath
    } else {
      Write-Host "Skipping missing requirements: $RequirementsPath" -ForegroundColor Yellow
    }
  }

  # Always ensure dependencies are present even when .venv already exists.
  Install-RequirementsIfExistsAlways -RequirementsPath (Join-Path $RootPath "ai\backend\requirements.txt")
  Install-RequirementsIfExistsAlways -RequirementsPath (Join-Path $RootPath "rag\backend\requirements.txt")
  # Install bot deps last so python-telegram-bot compatible httpx wins in shared .venv.
  Install-RequirementsIfExistsAlways -RequirementsPath (Join-Path $RootPath "bot\requirements.txt")
}

Ensure-VenvPython -RootPath $root -VenvPythonPath $venvPython
Install-ServiceDependencies -RootPath $root -VenvPythonPath $venvPython

# REQUIRED env vars
$env:SELF_API_KEY   = "local-dev-self-api-key"
$env:API_KEY        = $env:SELF_API_KEY
$env:RAG_URL        = "http://127.0.0.1:8001"
$env:AI_BACKEND_URL = "http://127.0.0.1:8000"
$env:OLLAMA_URL     = "http://127.0.0.1:11434"
$env:OLLAMA_MODEL   = "qwen2.5:1.5b"
$env:HTTP_PORT      = "8080"
$frontendPort       = 3000
$env:BOT_TOKEN      = "8424280939:AAF5LpTE4p1roIU61NWAJJt7dKnYswaNFls"

# LLM provider auto-selection:
# - Prefer OpenAI when OPENAI_API_KEY is present
# - Otherwise default to local Ollama
$openAiApiKey = (Get-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue).Value
if (-not [string]::IsNullOrWhiteSpace($openAiApiKey)) {
  $env:LLM_PROVIDER = "openai"
  if ([string]::IsNullOrWhiteSpace((Get-Item Env:OPENAI_MODEL -ErrorAction SilentlyContinue).Value)) {
    $env:OPENAI_MODEL = "gpt-4o-mini"
  }
  Write-Host "LLM provider selected: OPENAI ($($env:OPENAI_MODEL))"
} else {
  $env:LLM_PROVIDER = "ollama"
  Write-Host "LLM provider selected: OLLAMA ($($env:OLLAMA_MODEL) @ $($env:OLLAMA_URL))"
  $ollamaExe = Ensure-OllamaInstalled
  Write-Host "  Detected Ollama executable: $ollamaExe"
  Ensure-OllamaServerAndModel -OllamaExe $ollamaExe -OllamaUrl $env:OLLAMA_URL -ModelName $env:OLLAMA_MODEL
}

$ragDir = Join-Path $root "rag\backend"
$aiDir  = Join-Path $root "ai\backend"
$botDir = Join-Path $root "bot"
$frontDir = Join-Path $root "front"

if (-not (Test-Path -LiteralPath $ragDir)) { throw "Missing directory: $ragDir" }
if (-not (Test-Path -LiteralPath $aiDir)) { throw "Missing directory: $aiDir" }
if (-not (Test-Path -LiteralPath $botDir)) { throw "Missing directory: $botDir" }
if (-not (Test-Path -LiteralPath $frontDir)) { throw "Missing directory: $frontDir" }

Write-Host "Pre-cleanup..."
Stop-BotProcesses
Stop-FrontendProcesses
Stop-Pids (Get-ListeningPids 8000) "port 8000"
Stop-Pids (Get-ListeningPids 8001) "port 8001"
Stop-Pids (Get-ListeningPids 8080) "port 8080"
Stop-Pids (Get-ListeningPids $frontendPort) "port $frontendPort"
if ($StopOllama) {
  Stop-Pids (Get-ListeningPids 11434) "port 11434"
}
Start-Sleep -Milliseconds 300

# Frontend .env sync for direct bot API flow
$frontEnvPath = Join-Path $frontDir ".env"
$frontEnvBody = @(
  "BOT_API_URL=http://127.0.0.1:$($env:HTTP_PORT)"
  "BOT_API_KEY=$($env:SELF_API_KEY)"
) -join "`r`n"
Set-Content -LiteralPath $frontEnvPath -Value ($frontEnvBody + "`r`n") -Encoding UTF8
Write-Host "Synced frontend env: $frontEnvPath"
Write-Host "  BOT_API_URL=http://127.0.0.1:$($env:HTTP_PORT)"
Write-Host "  BOT_API_KEY=$($env:SELF_API_KEY)"

$reloadArgs = @()
if ($Reload) { $reloadArgs = @("--reload") }
$ragArgs = @("-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", "8001") + $reloadArgs
$aiArgs  = @("-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", "8000") + $reloadArgs

$logDir = Join-Path $root ".logs\local"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ragOutLog = (Join-Path $logDir "rag.ps.out.log")
$ragErrLog = (Join-Path $logDir "rag.ps.err.log")
$aiOutLog  = (Join-Path $logDir "ai.ps.out.log")
$aiErrLog  = (Join-Path $logDir "ai.ps.err.log")
$botOutLog = (Join-Path $logDir "bot.ps.out.log")
$botErrLog = (Join-Path $logDir "bot.ps.err.log")
$frontOutLog = (Join-Path $logDir "front.ps.out.log")
$frontErrLog = (Join-Path $logDir "front.ps.err.log")

$ragProc = Start-Process -FilePath $venvPython `
  -WorkingDirectory $ragDir `
  -ArgumentList $ragArgs `
  -RedirectStandardOutput $ragOutLog `
  -RedirectStandardError $ragErrLog `
  -PassThru

$aiProc = Start-Process -FilePath $venvPython `
  -WorkingDirectory $aiDir `
  -ArgumentList $aiArgs `
  -RedirectStandardOutput $aiOutLog `
  -RedirectStandardError $aiErrLog `
  -PassThru

if ($ForegroundBot) {
  Write-Host "Foreground bot mode enabled. Press Ctrl+C to stop all services."
  try {
    Push-Location $botDir
    & $venvPython "bot.py"
  } finally {
    Pop-Location
    Write-Host "Stopping services..."
    try { Stop-Process -Id $ragProc.Id -Force -ErrorAction SilentlyContinue; Write-Host "  Stopped RAG PID $($ragProc.Id)" } catch {}
    try { Stop-Process -Id $aiProc.Id -Force -ErrorAction SilentlyContinue; Write-Host "  Stopped AI PID $($aiProc.Id)" } catch {}
  }
  return
}

$botProc = Start-Process -FilePath $venvPython `
  -WorkingDirectory $botDir `
  -ArgumentList "bot.py" `
  -RedirectStandardOutput $botOutLog `
  -RedirectStandardError $botErrLog `
  -PassThru

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter is not installed or not available in PATH. Cannot start local frontend."
}

& flutter pub get --directory $frontDir
if ($LASTEXITCODE -ne 0) {
  throw "flutter pub get failed for $frontDir"
}

$frontArgs = @(
  "run", "-d", "web-server",
  "--web-hostname", "127.0.0.1",
  "--web-port", "$frontendPort",
  "--dart-define", "BOT_API_URL=http://127.0.0.1:$($env:HTTP_PORT)",
  "--dart-define", "BOT_API_KEY=$($env:SELF_API_KEY)"
)
$frontProc = Start-Process -FilePath "flutter" `
  -WorkingDirectory $frontDir `
  -ArgumentList $frontArgs `
  -RedirectStandardOutput $frontOutLog `
  -RedirectStandardError $frontErrLog `
  -PassThru

$ragUp = Wait-ForHttpReady -Uri "http://127.0.0.1:8001/health" -TimeoutSeconds 25
$aiUp = Wait-ForHttpReady -Uri "http://127.0.0.1:8000/" -TimeoutSeconds 25
$botApiUp = Wait-ForHttpReady -Uri "http://127.0.0.1:$($env:HTTP_PORT)/health" -TimeoutSeconds 25
$frontUp = Wait-ForHttpReady -Uri "http://127.0.0.1:$frontendPort" -TimeoutSeconds 60
$ollamaModelUp = $true
if ($env:LLM_PROVIDER -eq "ollama") {
  $ollamaModelUp = Test-OllamaModelHealthy -OllamaUrl $env:OLLAMA_URL -ModelName $env:OLLAMA_MODEL
}

Write-Host "Started processes:"
Write-Host "  RAG PID: $($ragProc.Id)  out: $([System.IO.Path]::GetFullPath($ragOutLog))  err: $([System.IO.Path]::GetFullPath($ragErrLog))"
Write-Host "  AI  PID: $($aiProc.Id)   out: $([System.IO.Path]::GetFullPath($aiOutLog))   err: $([System.IO.Path]::GetFullPath($aiErrLog))"
Write-Host "  Bot PID: $($botProc.Id)  out: $([System.IO.Path]::GetFullPath($botOutLog))  err: $([System.IO.Path]::GetFullPath($botErrLog))"
Write-Host "  Front PID: $($frontProc.Id) out: $([System.IO.Path]::GetFullPath($frontOutLog)) err: $([System.IO.Path]::GetFullPath($frontErrLog))"
Write-Host "Health:"
Write-Host "  RAG /health: $(if ($ragUp) { 'OK' } else { 'FAILED' })"
Write-Host "  AI  /health: $(if ($aiUp) { 'OK' } else { 'FAILED' })"
Write-Host "  BOT /health (:$($env:HTTP_PORT)): $(if ($botApiUp) { 'OK' } else { 'FAILED' })"
Write-Host "  Frontend http://127.0.0.1:$frontendPort : $(if ($frontUp) { 'OK' } else { 'FAILED' })"
if ($env:LLM_PROVIDER -eq "ollama") {
  Write-Host "  OLLAMA model '$($env:OLLAMA_MODEL)': $(if ($ollamaModelUp) { 'OK' } else { 'FAILED' })"
}
if (-not $ragUp -or -not $aiUp -or -not $botApiUp -or -not $frontUp -or -not $ollamaModelUp) {
  Write-Host "One or more health checks failed. Inspect *.err.log files above." -ForegroundColor Yellow
  if (-not $botApiUp) {
    if ($botProc -and $botProc.HasExited) {
      Write-Host "Bot process exited with code: $($botProc.ExitCode)" -ForegroundColor Yellow
    } else {
      Write-Host "Bot process is running but /health is unreachable on port $($env:HTTP_PORT)." -ForegroundColor Yellow
    }
  }
  if ($env:LLM_PROVIDER -eq "ollama" -and -not $ollamaModelUp) {
    Write-Host "Ollama server is up but model '$($env:OLLAMA_MODEL)' is unavailable." -ForegroundColor Yellow
  }
}

if ($frontUp) {
  Start-Process "http://127.0.0.1:$frontendPort"
}

Write-Host ""
Write-Host "Frontend local flow:"
Write-Host "  Auto-started at: http://127.0.0.1:$frontendPort"
Write-Host "  Logs: $([System.IO.Path]::GetFullPath($frontOutLog)) / $([System.IO.Path]::GetFullPath($frontErrLog))"
Write-Host "Frontend deploy flow (Vercel):"
Write-Host "  1) cd front"
Write-Host "  2) bash deploy.sh   (or .\deploy.bat on Windows)"
