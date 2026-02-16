param()

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function To-SingleQuotedLiteral {
  param([string]$Text)
  if ($null -eq $Text) { return "''" }
  return "'" + ($Text -replace "'", "''") + "'"
}

function Start-DeployTerminal {
  param(
    [string]$ServiceName,
    [string]$WorkingDirectory,
    [string]$CommandLine
  )

  if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
    throw "Missing directory for ${ServiceName}: $WorkingDirectory"
  }

  $serviceLiteral = To-SingleQuotedLiteral -Text $ServiceName
  $wdLiteral = To-SingleQuotedLiteral -Text $WorkingDirectory
  $cmdLiteral = To-SingleQuotedLiteral -Text $CommandLine

  $psCommand = @"
`$Host.UI.RawUI.WindowTitle = $serviceLiteral
Write-Host "[$ServiceName]" -ForegroundColor Cyan
Set-Location -LiteralPath $wdLiteral
Write-Host "Running: $CommandLine" -ForegroundColor DarkGray
Invoke-Expression $cmdLiteral
"@

  Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $psCommand) `
    -WindowStyle Normal | Out-Null
}

if (-not (Get-Command railway -ErrorAction SilentlyContinue)) {
  throw "railway CLI not found in PATH. Install with: npm i -g @railway/cli"
}

Start-DeployTerminal -ServiceName "BOT DEPLOY" -WorkingDirectory (Join-Path $root "bot") -CommandLine "railway up"
Start-DeployTerminal -ServiceName "AI DEPLOY" -WorkingDirectory (Join-Path $root "ai") -CommandLine "railway up"
Start-DeployTerminal -ServiceName "RAG DEPLOY" -WorkingDirectory (Join-Path $root "rag") -CommandLine "railway up"
Start-DeployTerminal -ServiceName "FRONT DEPLOY" -WorkingDirectory (Join-Path $root "front") -CommandLine "sh deploy.sh"

Write-Host "Started deploy terminals in parallel: BOT, AI, RAG, FRONT."
