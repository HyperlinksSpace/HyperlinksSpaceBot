# ===== START LOCAL STACK (Windows, robust) =====
param(
  [switch]$Reload,
  [switch]$ForegroundBot,
  [switch]$StopOllama,
  [switch]$OpenLogWindows,
  [switch]$NoServiceWindowLogs  # If set, log to files instead of service windows (default: logs in service windows)
)

$LogsInServiceWindows = -not $NoServiceWindowLogs
$ErrorActionPreference = "Stop"
Write-Host "start.ps1: launching local stack..."

function Get-ListeningPids($port) {
  try {
    $netConns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($netConns) {
      return @($netConns | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { [int]$_ })
    }
  } catch {}

  # Fallback for environments where Get-NetTCPConnection isn't available.
  $netstatExe = Join-Path ([Environment]::GetFolderPath("Windows")) "System32\netstat.exe"
  if (-not (Test-Path -LiteralPath $netstatExe)) {
    return @()
  }

  $lines = (& $netstatExe -ano) | Select-String ":$port" | Select-String "LISTENING"
  if (-not $lines) { return @() }
  $pids = @()
  foreach ($line in $lines) {
    $parts = ($line.ToString() -split "\s+") | Where-Object { $_ -ne "" }
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

function Stop-PidsWithTree([int[]]$pids, [string]$reason) {
  if (-not $pids -or $pids.Count -eq 0) { return }
  $taskkillExe = Join-Path ([Environment]::GetFolderPath("Windows")) "System32\taskkill.exe"
  foreach ($procId in ($pids | Sort-Object -Unique)) {
    try {
      Write-Host "  Killing PID $procId with child tree ($reason)..."
      if (Test-Path -LiteralPath $taskkillExe) {
        & $taskkillExe /PID $procId /T /F | Out-Null
      } else {
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}

function Stop-BotProcesses {
  $botPids = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object {
      $cmd = $_.CommandLine
      if (-not $cmd) { return $false }
      return ($cmd -like "*bot.py*" -or $cmd -like "*bot\bot.py*")
    } |
    Select-Object -ExpandProperty ProcessId -Unique
  Stop-PidsWithTree $botPids "bot.py"
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

function Wait-ForFrontendReady {
  param(
    [string]$BaseUrl,
    [int]$TimeoutSeconds = 120,
    [int]$IntervalMilliseconds = 800,
    [int]$MinMainDartJsBytes = 50000,
    [int]$RootStableChecks = 3,
    [int]$FallbackAfterSeconds = 20
  )

  $base = $BaseUrl.TrimEnd('/')
  $startTime = Get-Date
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $supportsBasicParsing = (Get-Command Invoke-WebRequest).Parameters.ContainsKey("UseBasicParsing")
  $stableRootHits = 0
  while ((Get-Date) -lt $deadline) {
    try {
      $rootReqParams = @{
        Uri = $base
        TimeoutSec = 8
      }
      if ($supportsBasicParsing) {
        $rootReqParams.UseBasicParsing = $true
      }
      $rootResp = Invoke-WebRequest @rootReqParams
      if ($rootResp.StatusCode -ge 200 -and $rootResp.StatusCode -lt 400) {
        $stableRootHits++

        $assetReqParams = @{
          Uri = "$base/main.dart.js"
          TimeoutSec = 8
        }
        if ($supportsBasicParsing) {
          $assetReqParams.UseBasicParsing = $true
        }

        try {
          $assetResp = Invoke-WebRequest @assetReqParams
          $contentLength = 0
          if ($null -ne $assetResp.Content) {
            $contentLength = $assetResp.Content.Length
          }
          if ($assetResp.StatusCode -ge 200 -and $assetResp.StatusCode -lt 400 -and $contentLength -ge $MinMainDartJsBytes) {
            return $true
          }
        } catch {}

        $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds
        if ($stableRootHits -ge $RootStableChecks -and $elapsedSeconds -ge $FallbackAfterSeconds) {
          # Fallback for flutter web-server mode where main.dart.js may be generated lazily.
          return $true
        }
      } else {
        $stableRootHits = 0
      }
    } catch {
      $stableRootHits = 0
    }

    Start-Sleep -Milliseconds $IntervalMilliseconds
  }
  return $false
}

function To-SingleQuotedLiteral {
  param(
    [string]$Text
  )
  if ($null -eq $Text) { return "''" }
  return "'" + ($Text -replace "'", "''") + "'"
}

function Start-ServiceLogWindow {
  param(
    [string]$ServiceName,
    [string]$Title,
    [string]$OutLogPath,
    [string]$ErrLogPath
  )

  $titleLiteral = To-SingleQuotedLiteral -Text $Title
  $outLiteral = To-SingleQuotedLiteral -Text $OutLogPath
  $errLiteral = To-SingleQuotedLiteral -Text $ErrLogPath
  $cmd = @"
`$Host.UI.RawUI.WindowTitle = $titleLiteral
Write-Host "[$ServiceName]" -ForegroundColor Cyan
Write-Host "Streaming logs for $Title (Ctrl+C to stop this viewer)" -ForegroundColor Cyan
Write-Host "OUT: $OutLogPath"
Write-Host "ERR: $ErrLogPath"
if (-not (Test-Path -LiteralPath $outLiteral)) { New-Item -ItemType File -Path $outLiteral -Force | Out-Null }
if (-not (Test-Path -LiteralPath $errLiteral)) { New-Item -ItemType File -Path $errLiteral -Force | Out-Null }
Get-Content -Path $outLiteral, $errLiteral -Tail 30 -Wait
"@

  Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoExit", "-Command", $cmd) `
    -WindowStyle Normal | Out-Null
}

function Start-ServiceProcessWindow {
  param(
    [string]$ServiceName,
    [string]$WorkingDirectory,
    [string]$ExecutablePath,
    [string[]]$Arguments
  )

  # Use native Windows paths so the child PowerShell resolves .venv and dirs correctly
  $wdNative = $WorkingDirectory -replace '/', '\'
  if ($wdNative -match '^\\[cC]\\') {
    $wdNative = ($wdNative -replace '^\\([cC])\\', '$1:\').TrimStart('\')
  }
  if (-not [System.IO.Path]::IsPathRooted($wdNative)) {
    $wdNative = (Resolve-Path -LiteralPath $WorkingDirectory).Path
  }
  $exeNative = $ExecutablePath -replace '/', '\'
  if ($exeNative -match '^\\[cC]\\') {
    $exeNative = ($exeNative -replace '^\\([cC])\\', '$1:\').TrimStart('\')
  }
  # Resolve to full path only when it looks like a file path; leave bare command names (e.g. "flutter") as-is
  if ($exeNative -match '[\\/:]' -and -not [System.IO.Path]::IsPathRooted($exeNative)) {
    $exeNative = (Resolve-Path -LiteralPath $ExecutablePath).Path
  }

  $serviceLiteral = To-SingleQuotedLiteral -Text $ServiceName
  $wdLiteral = To-SingleQuotedLiteral -Text $wdNative
  $exeLiteral = To-SingleQuotedLiteral -Text $exeNative
  $argList = ($Arguments | ForEach-Object { To-SingleQuotedLiteral -Text $_ }) -join " "
  $scriptLines = @(
    "`$Host.UI.RawUI.WindowTitle = $serviceLiteral",
    "Write-Host `"[$ServiceName]`" -ForegroundColor Cyan",
    "Set-Location -LiteralPath $wdLiteral",
    "& $exeLiteral $argList"
  )
  $scriptContent = $scriptLines -join "`r`n"
  $tempDir = [System.IO.Path]::GetTempPath()
  $tempScript = Join-Path $tempDir "HyperlinksSpaceBot_$ServiceName.ps1"
  # UTF-8 without BOM so child PowerShell parses the script reliably
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($tempScript, $scriptContent, $utf8NoBom)
  $tempScriptFull = [System.IO.Path]::GetFullPath($tempScript)

  # Launch via cmd /c start so the new window gets a real console and shows output
  # (avoids empty windows when parent was started from bash / non-console)
  $startTitle = "HyperlinksSpaceBot $ServiceName"
  $proc = Start-Process -FilePath "cmd.exe" `
    -ArgumentList @(
      "/c", "start", "`"$startTitle`"",
      "powershell.exe", "-NoExit", "-ExecutionPolicy", "Bypass", "-NoProfile",
      "-File", "`"$tempScriptFull`""
    ) `
    -WindowStyle Normal `
    -PassThru
  # Return a dummy process object so callers still get $ragProc.Id etc.; cmd exits immediately
  if (-not $proc) {
    return $proc
  }
  Start-Sleep -Milliseconds 200
  $psProcs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*HyperlinksSpaceBot_$ServiceName.ps1*" } |
    Sort-Object CreationDate -Descending |
    Select-Object -First 1
  if ($psProcs) {
    return Get-Process -Id $psProcs.ProcessId -ErrorAction SilentlyContinue
  }
  return $proc
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
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

  # Avoid pulling on every startup: check local tags first.
  $modelInstalled = $false
  try {
    $tags = Invoke-RestMethod -Uri "$($OllamaUrl.TrimEnd('/'))/api/tags" -TimeoutSec 8
    foreach ($m in @($tags.models)) {
      if ($null -ne $m -and $m.name -eq $ModelName) {
        $modelInstalled = $true
        break
      }
    }
  } catch {}

  if ($modelInstalled) {
    Write-Host "Ollama model already installed locally: $ModelName"
    return
  }

  $maxAttempts = 4
  for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    Write-Host "Ensuring Ollama model is installed: $ModelName (attempt $attempt/$maxAttempts)"
    & $OllamaExe pull $ModelName
    if ($LASTEXITCODE -eq 0) {
      return
    }

    if ($attempt -lt $maxAttempts) {
      $delaySeconds = [Math]::Pow(2, $attempt)
      Write-Host "  Ollama pull failed (exit code: $LASTEXITCODE). Retrying in $delaySeconds s..." -ForegroundColor Yellow
      Start-Sleep -Seconds $delaySeconds
    }
  }

  throw "Failed to pull Ollama model '$ModelName' after $maxAttempts attempts."
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

  function Get-RequirementsArgumentPath {
    param(
      [string]$BasePath,
      [string]$FullPath
    )
    $baseNorm = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\')
    $fullNorm = (Resolve-Path -LiteralPath $FullPath).Path
    if ($fullNorm.StartsWith($baseNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $fullNorm.Substring($baseNorm.Length).TrimStart('\')
    }
    return $fullNorm
  }

  function Invoke-PipInstallWithRetry {
    param(
      [string]$RequirementsPath,
      [int]$MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
      Write-Host "  pip install (attempt $attempt/$MaxAttempts): $RequirementsPath"
      $reqArg = Get-RequirementsArgumentPath -BasePath $RootPath -FullPath $RequirementsPath
      $pipProc = Start-Process -FilePath $VenvPythonPath `
        -WorkingDirectory $RootPath `
        -ArgumentList "-m", "pip", "install", "-r", $reqArg `
        -Wait `
        -PassThru
      if ($pipProc.ExitCode -eq 0) {
        return
      }
      if ($attempt -lt $MaxAttempts) {
        Write-Host "  pip install failed (exit=$($pipProc.ExitCode)), retrying in 3s..." -ForegroundColor Yellow
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

# ===== Environment configuration =====
# Load repo root .env (BOT_TOKEN and any other vars)
$rootEnvPath = Join-Path $root ".env"
if (Test-Path -LiteralPath $rootEnvPath) {
  Get-Content -LiteralPath $rootEnvPath -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line -match "^\s*([^#=]+)=(.*)$") {
      $key = $Matches[1].Trim()
      $val = $Matches[2].Trim().Trim('"').Trim("'")
      if ($key) { Set-Item -Path "Env:$key" -Value $val -ErrorAction SilentlyContinue }
    }
  }
}

# Shared internal auth across front/bot/ai/rag
$env:INNER_CALLS_KEY = "local-dev-inner-calls-key"

# RAG
$env:RAG_URL         = "http://127.0.0.1:8001"
$env:COFFEE_URL      = "https://tokens.swap.coffee"
# Optional swap.coffee key (blank by default for local run).
$env:COFFEE_KEY      = ""

# AI
$env:AI_BACKEND_URL  = "http://127.0.0.1:8000"
$env:OLLAMA_URL      = "http://127.0.0.1:11434"
$env:OLLAMA_MODEL    = "qwen2.5:1.5b"

# Bot (BOT_TOKEN is loaded from .env above)
$env:HTTP_PORT       = "8080"
if ([string]::IsNullOrWhiteSpace($env:BOT_TOKEN)) {
  throw "BOT_TOKEN is not set. Add BOT_TOKEN=your_token to the repo root .env file (copy from .env.example)."
}

# Frontend
$frontendPort        = 3000
$env:APP_URL         = "http://127.0.0.1:$frontendPort"

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
# Allow port 8080 and Telegram token to be released before starting a new bot (avoids double /start replies)
Start-Sleep -Seconds 1

# Frontend .env sync for direct bot API flow
$frontEnvPath = Join-Path $frontDir ".env"
$frontEnvBody = @(
  "BOT_API_URL=http://127.0.0.1:$($env:HTTP_PORT)"
  "INNER_CALLS_KEY=$($env:INNER_CALLS_KEY)"
  "BOT_API_KEY=$($env:INNER_CALLS_KEY)"
) -join "`r`n"
Set-Content -LiteralPath $frontEnvPath -Value ($frontEnvBody + "`r`n") -Encoding UTF8
Write-Host "Synced frontend env: $frontEnvPath"
Write-Host "  BOT_API_URL=http://127.0.0.1:$($env:HTTP_PORT)"
Write-Host "  INNER_CALLS_KEY=$($env:INNER_CALLS_KEY)"
Write-Host "  BOT_API_KEY=$($env:INNER_CALLS_KEY)"

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

if ($LogsInServiceWindows) {
  Write-Host "Service logs mode: using each service window output (no extra tail windows)." -ForegroundColor Cyan
  $ragProc = Start-ServiceProcessWindow -ServiceName "RAG" -WorkingDirectory $ragDir -ExecutablePath $venvPython -Arguments $ragArgs
  $aiProc = Start-ServiceProcessWindow -ServiceName "AI" -WorkingDirectory $aiDir -ExecutablePath $venvPython -Arguments $aiArgs
} else {
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
}

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

# Ensure no leftover bot process (avoids double /start replies)
Stop-BotProcesses
Start-Sleep -Milliseconds 800
if ($LogsInServiceWindows) {
  $botProc = Start-ServiceProcessWindow -ServiceName "BOT" -WorkingDirectory $botDir -ExecutablePath $venvPython -Arguments @("bot.py")
} else {
  $botProc = Start-Process -FilePath $venvPython `
    -WorkingDirectory $botDir `
    -ArgumentList "bot.py" `
    -RedirectStandardOutput $botOutLog `
    -RedirectStandardError $botErrLog `
    -PassThru
}

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
  "--dart-define", "INNER_CALLS_KEY=$($env:INNER_CALLS_KEY)",
  "--dart-define", "BOT_API_KEY=$($env:INNER_CALLS_KEY)"
)
if ($LogsInServiceWindows) {
  $frontProc = Start-ServiceProcessWindow -ServiceName "FRONT" -WorkingDirectory $frontDir -ExecutablePath "flutter" -Arguments $frontArgs
} else {
  $frontProc = Start-Process -FilePath "flutter" `
    -WorkingDirectory $frontDir `
    -ArgumentList $frontArgs `
    -RedirectStandardOutput $frontOutLog `
    -RedirectStandardError $frontErrLog `
    -PassThru
}

if ($OpenLogWindows -and -not $LogsInServiceWindows) {
  Start-ServiceLogWindow -ServiceName "RAG" -Title "RAG logs" -OutLogPath $ragOutLog -ErrLogPath $ragErrLog
  Start-ServiceLogWindow -ServiceName "AI" -Title "AI logs" -OutLogPath $aiOutLog -ErrLogPath $aiErrLog
  Start-ServiceLogWindow -ServiceName "BOT" -Title "Bot logs" -OutLogPath $botOutLog -ErrLogPath $botErrLog
  Start-ServiceLogWindow -ServiceName "FRONT" -Title "Front logs" -OutLogPath $frontOutLog -ErrLogPath $frontErrLog
}

$ragUp = Wait-ForHttpReady -Uri "http://127.0.0.1:8001/health" -TimeoutSeconds 25
$aiUp = Wait-ForHttpReady -Uri "http://127.0.0.1:8000/" -TimeoutSeconds 25
$botApiUp = Wait-ForHttpReady -Uri "http://127.0.0.1:$($env:HTTP_PORT)/health" -TimeoutSeconds 25
$frontUp = Wait-ForFrontendReady -BaseUrl "http://127.0.0.1:$frontendPort" -TimeoutSeconds 120
$ollamaModelUp = $true
if ($env:LLM_PROVIDER -eq "ollama") {
  $ollamaModelUp = Test-OllamaModelHealthy -OllamaUrl $env:OLLAMA_URL -ModelName $env:OLLAMA_MODEL
}

Write-Host "Started processes:"
if ($LogsInServiceWindows) {
  Write-Host "  RAG PID: $($ragProc.Id)  logs: service window"
  Write-Host "  AI  PID: $($aiProc.Id)   logs: service window"
  Write-Host "  Bot PID: $($botProc.Id)  logs: service window"
  Write-Host "  Front PID: $($frontProc.Id) logs: service window"
} else {
  Write-Host "  RAG PID: $($ragProc.Id)  out: $([System.IO.Path]::GetFullPath($ragOutLog))  err: $([System.IO.Path]::GetFullPath($ragErrLog))"
  Write-Host "  AI  PID: $($aiProc.Id)   out: $([System.IO.Path]::GetFullPath($aiOutLog))   err: $([System.IO.Path]::GetFullPath($aiErrLog))"
  Write-Host "  Bot PID: $($botProc.Id)  out: $([System.IO.Path]::GetFullPath($botOutLog))  err: $([System.IO.Path]::GetFullPath($botErrLog))"
  Write-Host "  Front PID: $($frontProc.Id) out: $([System.IO.Path]::GetFullPath($frontOutLog)) err: $([System.IO.Path]::GetFullPath($frontErrLog))"
}
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
if ($LogsInServiceWindows) {
  Write-Host "  Logs: frontend service window"
} else {
  Write-Host "  Logs: $([System.IO.Path]::GetFullPath($frontOutLog)) / $([System.IO.Path]::GetFullPath($frontErrLog))"
}
Write-Host "Frontend deploy flow (Vercel):"
Write-Host "  1) cd front"
Write-Host "  2) bash deploy.sh   (or .\deploy.bat on Windows)"
