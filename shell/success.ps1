param()

$ErrorActionPreference = "SilentlyContinue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$rootRegex = [regex]::Escape($root)
$taskkillExe = Join-Path ([Environment]::GetFolderPath("Windows")) "System32\taskkill.exe"

function Stop-PidsWithTree {
  param(
    [int[]]$Pids,
    [string]$Reason
  )

  if (-not $Pids -or $Pids.Count -eq 0) {
    Write-Host "  No process found for $Reason."
    return
  }

  foreach ($pid in ($Pids | Sort-Object -Unique)) {
    Write-Host "  Closing PID $pid ($Reason)..."
    try {
      if (Test-Path -LiteralPath $taskkillExe) {
        & $taskkillExe /PID $pid /T /F | Out-Null
      } else {
        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}

function Close-DeployTerminalsByTitle {
  Write-Host "Closing deploy windows by title (taskkill)..."
  if (-not (Test-Path -LiteralPath $taskkillExe)) { return }
  # Exact titles set by launch.ps1
  foreach ($t in @("BOT DEPLOY", "AI DEPLOY", "RAG DEPLOY", "FRONT DEPLOY")) {
    try {
      & $taskkillExe /FI "WINDOWTITLE eq $t" /T /F 2>$null
    } catch {}
  }
  # Prefix match (in case title has suffix)
  foreach ($t in @("BOT DEPLOY", "AI DEPLOY", "RAG DEPLOY", "FRONT DEPLOY")) {
    try {
      & $taskkillExe /FI "WINDOWTITLE eq $t*" /T /F 2>$null
    } catch {}
  }
  # Any window with DEPLOY in title
  try {
    & $taskkillExe /FI "WINDOWTITLE lk *DEPLOY*" /T /F 2>$null
  } catch {}
}

function Close-DeployTerminalsByPid {
  Write-Host "Closing deploy terminal processes (by PID)..."
  $myPid = $PID
  $byCmd = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object {
      if ($_.ProcessId -eq $myPid) { return $false }
      $cmd = $_.CommandLine
      if (-not $cmd) { return $false }
      return (
        ($cmd -match "BOT DEPLOY|AI DEPLOY|RAG DEPLOY|FRONT DEPLOY") -or
        ($cmd -match "Invoke-Expression" -and ($cmd -match "railway up|deploy\.sh")) -or
        (($cmd -match "railway up|deploy\.sh") -and ($cmd -match $rootRegex))
      )
    } |
    Select-Object -ExpandProperty ProcessId -Unique

  $byTitle = Get-Process -Name powershell -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne $myPid -and $_.MainWindowTitle -match "BOT DEPLOY|AI DEPLOY|RAG DEPLOY|FRONT DEPLOY" } |
    Select-Object -ExpandProperty Id -Unique

  $allPids = @($byCmd) + @($byTitle) | Sort-Object -Unique
  Stop-PidsWithTree -Pids $allPids -Reason "deploy terminal"
}

function Close-DeployTerminals {
  Close-DeployTerminalsByTitle
  Close-DeployTerminalsByPid
}

function Close-ResidualDeployProcesses {
  Write-Host "Checking residual deploy child processes..."
  $residualPids = Get-CimInstance Win32_Process |
    Where-Object {
      $name = ($_.Name | ForEach-Object { $_.ToLowerInvariant() })
      $cmd = $_.CommandLine
      if (-not $cmd) { return $false }
      if (-not ($cmd -match $rootRegex)) { return $false }
      return (
        $name -in @("railway.exe", "railway.cmd", "node.exe", "sh.exe", "bash.exe", "cmd.exe", "powershell.exe")
      ) -and ($cmd -match "railway up|deploy\.sh")
    } |
    Select-Object -ExpandProperty ProcessId -Unique

  Stop-PidsWithTree -Pids $residualPids -Reason "deploy child process"
}

Close-DeployTerminals
Close-ResidualDeployProcesses
Write-Host "Done. Deploy terminals/processes were closed where found."
