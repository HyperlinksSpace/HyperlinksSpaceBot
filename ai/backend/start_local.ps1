# ===== START LOCAL STACK (Windows, robust) =====

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$venvPython = Join-Path $root ".venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $venvPython)) {
  throw "Missing virtualenv python: $venvPython"
}

# REQUIRED env vars
$env:API_KEY        = "my-local-dev-secret"
$env:RAG_URL        = "http://127.0.0.1:8001"
$env:AI_BACKEND_URL = "http://127.0.0.1:8000"
$env:OLLAMA_URL     = "http://127.0.0.1:11434"
$env:OLLAMA_MODEL   = "qwen2.5:1.5b"

# Put your Telegram token here
$env:BOT_TOKEN = "8424280939:AAF5LpTE4p1roIU61NWAJJt7dKnYswaNFls"

$ragDir = Join-Path $root "rag\backend"
$aiDir  = Join-Path $root "ai\backend"
$botDir = Join-Path $root "bot"

if (-not (Test-Path -LiteralPath $ragDir)) { throw "Missing directory: $ragDir" }
if (-not (Test-Path -LiteralPath $aiDir)) { throw "Missing directory: $aiDir" }
if (-not (Test-Path -LiteralPath $botDir)) { throw "Missing directory: $botDir" }

# Start RAG
Start-Process -FilePath $venvPython `
  -WorkingDirectory $ragDir `
  -ArgumentList "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", "8001", "--reload"

# Start AI backend
Start-Process -FilePath $venvPython `
  -WorkingDirectory $aiDir `
  -ArgumentList "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", "8000", "--reload"

# Start Telegram bot
Start-Process -FilePath $venvPython `
  -WorkingDirectory $botDir `
  -ArgumentList "bot.py"
