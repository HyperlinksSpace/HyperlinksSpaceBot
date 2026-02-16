param(
    [string]$AiBackendUrl = $(if ($env:AI_BACKEND_URL) { $env:AI_BACKEND_URL } else { "http://127.0.0.1:8000" }),
    [string]$RagUrl = $(if ($env:RAG_URL) { $env:RAG_URL } else { "http://127.0.0.1:8001" }),
    [string]$ApiKey = $env:API_KEY,
    [string]$AiLogFile = $env:AI_LOG_FILE,
    [string]$RagLogFile = $env:RAG_LOG_FILE
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $ApiKey) {
    throw "API_KEY is required. Set `$env:API_KEY first."
}

function Invoke-JsonGet {
    param([Parameter(Mandatory = $true)][string]$Url)
    return Invoke-RestMethod -Method Get -Uri $Url -TimeoutSec 30
}

function Invoke-AiPrompt {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    Write-Host "Prompt: $Prompt" -ForegroundColor Cyan

    $body = @{
        messages = @(@{ role = "user"; content = $Prompt })
        stream = $false
    } | ConvertTo-Json -Depth 6

    $raw = Invoke-RestMethod -Method Post -Uri "$AiBackendUrl/api/chat" -Headers @{
        "X-API-Key" = $ApiKey
    } -ContentType "application/json" -Body $body -TimeoutSec 60

    if ($raw -is [string]) {
        $lines = $raw -split "`n" | Where-Object { $_.Trim() -ne "" }
        if ($lines.Count -gt 0) {
            try {
                $last = $lines[-1] | ConvertFrom-Json
                $last | ConvertTo-Json -Depth 8
            } catch {
                $raw
            }
        }
        return
    }

    $raw | ConvertTo-Json -Depth 8
}

Write-Host "== Health checks ==" -ForegroundColor Yellow
(Invoke-JsonGet -Url "$AiBackendUrl/") | ConvertTo-Json -Depth 8
(Invoke-JsonGet -Url "$RagUrl/health") | ConvertTo-Json -Depth 8

Write-Host "`n== RAG token checks ==" -ForegroundColor Yellow
foreach ($sym in @("DOGS", "TON")) {
    try {
        $token = Invoke-JsonGet -Url "$RagUrl/tokens/$sym"
        Write-Host "$sym -> HTTP 200" -ForegroundColor Green
        @{
            symbol = $token.symbol
            name = $token.name
            total_supply = $token.total_supply
            holders = $token.holders
            tx_24h = $token.tx_24h
        } | ConvertTo-Json -Depth 8
    } catch {
        Write-Warning "$sym token lookup failed: $($_.Exception.Message)"
    }
}

Write-Host "`n== AI chat checks (same prompts as Telegram smoke) ==" -ForegroundColor Yellow
Invoke-AiPrompt -Prompt '$DOGS'
Invoke-AiPrompt -Prompt 'что такое DOGS?'
Invoke-AiPrompt -Prompt '$TON'

Write-Host "`n== Optional log checks ==" -ForegroundColor Yellow
if ($AiLogFile -and (Test-Path -LiteralPath $AiLogFile)) {
    Write-Host "AI log file: $AiLogFile"
    $aiHits = Select-String -Path $AiLogFile -Pattern "RAG verification failed" -SimpleMatch
    if ($aiHits) {
        Write-Warning "Found 'RAG verification failed' in AI logs"
        $aiHits | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line }
    } else {
        Write-Host "OK: no 'RAG verification failed' in AI logs" -ForegroundColor Green
    }
} else {
    Write-Host "AI_LOG_FILE not set or not found; skipping AI log check"
}

if ($RagLogFile -and (Test-Path -LiteralPath $RagLogFile)) {
    Write-Host "RAG log file: $RagLogFile"
    $ragHits = Select-String -Path $RagLogFile -Pattern "/tokens/DOGS|/tokens/TON|GET /tokens"
    if ($ragHits) {
        Write-Host "OK: token endpoint hits found in RAG logs" -ForegroundColor Green
        $ragHits | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line }
    } else {
        Write-Warning "Token endpoint hits not found in RAG logs"
    }
} else {
    Write-Host "RAG_LOG_FILE not set or not found; skipping RAG log check"
}

Write-Host "`nDone. If checks pass, run Telegram smoke prompts." -ForegroundColor Green
