# ===== STOP LOCAL STACK (Windows) =====
# Stops services by killing whatever is LISTENING on ports:
# - 8000 (AI backend)
# - 8001 (RAG backend)
# - 11434 (Ollama) [default]

param(
  [switch]$KeepOllama
)

$ErrorActionPreference = "SilentlyContinue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

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
  if (-not $pids -or $pids.Count -eq 0) {
    Write-Host "  No process found for $reason."
    return
  }
  foreach ($procId in $pids) {
    Write-Host "  Killing PID $procId ($reason)..."
    try { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue } catch {}
  }
}

function Stop-PidsWithTree([int[]]$pids, [string]$reason) {
  if (-not $pids -or $pids.Count -eq 0) {
    Write-Host "  No process found for $reason."
    return
  }

  $taskkillExe = Join-Path ([Environment]::GetFolderPath("Windows")) "System32\taskkill.exe"
  foreach ($procId in ($pids | Sort-Object -Unique)) {
    Write-Host "  Killing PID $procId with child tree ($reason)..."
    try {
      if (Test-Path -LiteralPath $taskkillExe) {
        & $taskkillExe /PID $procId /T /F | Out-Null
      } else {
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}

function Kill-Port($port, [switch]$WithTree) {
  Write-Host "Checking port $port..."
  $pids = Get-ListeningPids $port
  if ($WithTree) {
    Stop-PidsWithTree $pids "port $port"
  } else {
    Stop-Pids $pids "port $port"
  }
}

function Kill-BotProcess {
  Write-Host "Checking bot.py processes..."
  $botProcs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object {
      $cmd = $_.CommandLine
      if (-not $cmd) { return $false }
      return ($cmd -like "*bot.py*" -or $cmd -like "*bot\bot.py*")
    }

  if (-not $botProcs) {
    Write-Host "  No bot.py python process found."
    return
  }

  $pids = $botProcs | Select-Object -ExpandProperty ProcessId | Sort-Object -Unique
  Stop-PidsWithTree $pids "bot.py"
}

function Kill-FrontendFlutterProcess {
  Write-Host "Checking frontend flutter web-server processes..."
  $frontProcs = Get-CimInstance Win32_Process -Filter "Name='flutter.bat'" |
    Where-Object CommandLine -Match "run -d web-server"

  if (-not $frontProcs) {
    Write-Host "  No flutter web-server process found."
    return
  }

  $pids = $frontProcs | Select-Object -ExpandProperty ProcessId | Sort-Object -Unique
  Stop-PidsWithTree $pids "flutter web-server"
}

function Kill-BackendPythonByCommand {
  Write-Host "Checking local uvicorn python processes..."
  $targets = @(
    "uvicorn main:app --host 127.0.0.1 --port 8000",
    "uvicorn main:app --host 127.0.0.1 --port 8001"
  )
  $backendPids = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object {
      $cmd = $_.CommandLine
      if (-not $cmd) { return $false }
      foreach ($target in $targets) {
        if ($cmd -like "*$target*") { return $true }
      }
      return $false
    } |
    Select-Object -ExpandProperty ProcessId -Unique

  Stop-PidsWithTree $backendPids "local uvicorn backend"
}

function Kill-OllamaProcesses {
  Write-Host "Checking Ollama processes..."
  $ollamaPids = Get-CimInstance Win32_Process |
    Where-Object {
      $name = ($_.Name | ForEach-Object { $_.ToLowerInvariant() })
      $cmd = $_.CommandLine
      if (-not $name) { return $false }
      if ($name -in @("ollama.exe", "ollama_llama_server.exe")) { return $true }
      if (-not $cmd) { return $false }
      return ($cmd -match "(^|\\s)ollama(\\s|$)")
    } |
    Select-Object -ExpandProperty ProcessId -Unique
  Stop-Pids $ollamaPids "ollama runtime"
}

function Kill-RepoProcesses {
  param(
    [string]$RootPath
  )

  Write-Host "Checking repo-related process leftovers..."
  $rootRegex = [regex]::Escape($RootPath)

  # Target only runtime processes we spawn for local stack.
  $runtimeNames = @("python.exe", "dart.exe", "flutter.bat")
  $repoRuntimePids = Get-CimInstance Win32_Process |
    Where-Object {
      $name = $_.Name
      $cmd = $_.CommandLine
      if (-not $cmd) { return $false }
      if (-not ($runtimeNames -contains $name)) { return $false }
      return ($cmd -match $rootRegex)
    } |
    Select-Object -ExpandProperty ProcessId -Unique

  Stop-PidsWithTree $repoRuntimePids "repo runtime process"
}

function Kill-LogTailWindows {
  param(
    [string]$RootPath
  )

  Write-Host "Checking log-tail viewer windows..."
  $rootRegex = [regex]::Escape($RootPath)
  $tailPids = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object {
      $cmd = $_.CommandLine
      if (-not $cmd) { return $false }
      return (
        ($cmd -match "Get-Content\s+-Path") -and
        ($cmd -match "rag\.ps\.out\.log|ai\.ps\.out\.log|bot\.ps\.out\.log|front\.ps\.out\.log") -and
        ($cmd -match $rootRegex)
      )
    } |
    Select-Object -ExpandProperty ProcessId -Unique

  Stop-Pids $tailPids "service log tail window"
}

function Kill-ServiceWindows {
  param(
    [string]$RootPath
  )

  Write-Host "Checking service terminal windows (RAG/AI/BOT/FRONT)..."
  # Service windows are: powershell.exe -File "...\HyperlinksSpaceBot_<SERVICE>.ps1" (started by start.ps1)
  $serviceWindowPids = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object {
      $cmd = $_.CommandLine
      if (-not $cmd) { return $false }
      return $cmd -match "HyperlinksSpaceBot_(RAG|AI|BOT|FRONT)\.ps1"
    } |
    Select-Object -ExpandProperty ProcessId -Unique

  Stop-PidsWithTree $serviceWindowPids "service window"
}

# First: close our service terminal windows and their full process trees (RAG/AI/BOT/FRONT)
# so no python/flutter child is left running (avoids "another instance consuming updates")
Kill-ServiceWindows -RootPath $root
Kill-LogTailWindows -RootPath $root

# Then: kill by port (with tree for bot/frontend ports) and by command line
Kill-Port 8000
Kill-Port 8001
Kill-Port 8080 -WithTree
Kill-Port 3000 -WithTree
Kill-BackendPythonByCommand
Kill-BotProcess
Kill-FrontendFlutterProcess
Kill-RepoProcesses -RootPath $root

if ($KeepOllama) {
  Write-Host "Keeping Ollama (11434) running. Use without -KeepOllama to stop it."
} else {
  Kill-OllamaProcesses
  Kill-Port 11434
}

# Final sweep: after terminal/process-tree kills, free target ports again.
foreach ($port in 8000, 8001, 8080, 3000, 11434) {
  if ($KeepOllama -and $port -eq 11434) { continue }
  Kill-Port $port -WithTree
}
# One more pass on bot so no instance keeps the token
Kill-BotProcess

Write-Host "Done. Active listeners summary:"
foreach ($port in 8000, 8001, 8080, 3000, 11434) {
  $pids = Get-ListeningPids $port
  if ($pids.Count -gt 0) {
    Write-Host "  Port $port still in use by PID(s): $($pids -join ', ')"
  } else {
    Write-Host "  Port $port is free."
  }
}
