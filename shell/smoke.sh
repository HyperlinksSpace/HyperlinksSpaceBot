#!/usr/bin/env bash
set -euo pipefail

AI_BACKEND_URL="${AI_BACKEND_URL:-http://127.0.0.1:8000}"
RAG_URL="${RAG_URL:-http://127.0.0.1:8001}"
API_KEY="${API_KEY:-}"
AI_LOG_FILE="${AI_LOG_FILE:-}"
RAG_LOG_FILE="${RAG_LOG_FILE:-}"

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: API_KEY is required (export API_KEY=...)"
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required"; exit 1; }
}

require_cmd curl
require_cmd jq

search_cmd() {
  if command -v rg >/dev/null 2>&1; then
    rg -n "$1" "$2"
  else
    grep -nE "$1" "$2"
  fi
}

echo "== Health checks =="
curl -fsS "$AI_BACKEND_URL/" | jq .
curl -fsS "$RAG_URL/health" | jq .

echo
echo "== RAG token checks =="
for sym in DOGS TON; do
  code=$(curl -s -o /tmp/rag_${sym}.json -w "%{http_code}" "$RAG_URL/tokens/$sym")
  echo "$sym -> HTTP $code"
  if [[ "$code" -eq 200 ]]; then
    jq '{symbol, name, total_supply, holders, tx_24h}' /tmp/rag_${sym}.json
  else
    cat /tmp/rag_${sym}.json
  fi
  echo
 done

echo "== AI chat checks (same prompts as Telegram smoke) =="
run_prompt() {
  local prompt="$1"
  echo "Prompt: $prompt"
  curl -fsS -N -X POST "$AI_BACKEND_URL/api/chat" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d "$(jq -cn --arg p "$prompt" '{messages:[{role:"user",content:$p}],stream:false}')" \
    | tail -n 1 | jq .
  echo
}

assert_no_tx_words_when_tx24h_null() {
  local symbol="$1"
  local prompt="$2"
  local rag_json="/tmp/rag_${symbol}_assert.json"

  curl -fsS "$RAG_URL/tokens/$symbol" > "$rag_json"
  local tx24h
  tx24h=$(jq -r '.tx_24h' "$rag_json")
  if [[ "$tx24h" != "null" ]]; then
    echo "SKIP: $symbol has tx_24h=$tx24h (assert expects null)"
    return 0
  fi

  local chat_line chat_text
  chat_line=$(
    curl -fsS -N -X POST "$AI_BACKEND_URL/api/chat" \
      -H "Content-Type: application/json" \
      -H "X-API-Key: $API_KEY" \
      -d "$(jq -cn --arg p "$prompt" '{messages:[{role:"user",content:$p}],stream:false}')"
  )
  chat_text=$(printf "%s\n" "$chat_line" | tail -n 1 | jq -r '.response // ""')

  if printf "%s\n" "$chat_text" | grep -Eiq '\btx\b|transactions|транзакц'; then
    echo "FAIL: response mentions transactions even though tx_24h is null for $symbol"
    echo "Response: $chat_text"
    exit 1
  fi
  echo "OK: no transaction wording when tx_24h is null for $symbol"
}

run_prompt '$DOGS'
run_prompt 'что такое DOGS?'
run_prompt '$TON'
assert_no_tx_words_when_tx24h_null "TON" '$TON'

echo "== Optional log checks =="
if [[ -n "$AI_LOG_FILE" && -f "$AI_LOG_FILE" ]]; then
  echo "AI log file: $AI_LOG_FILE"
  if search_cmd "RAG verification failed" "$AI_LOG_FILE"; then
    echo "WARNING: found 'RAG verification failed' in AI logs"
  else
    echo "OK: no 'RAG verification failed' in AI logs"
  fi
else
  echo "AI_LOG_FILE not set or not found; skipping AI log grep"
fi

if [[ -n "$RAG_LOG_FILE" && -f "$RAG_LOG_FILE" ]]; then
  echo "RAG log file: $RAG_LOG_FILE"
  if search_cmd "/tokens/(DOGS|TON)|GET /tokens" "$RAG_LOG_FILE"; then
    echo "OK: token endpoint hits found in RAG logs"
  else
    echo "WARNING: token endpoint hits not found in RAG logs"
  fi
else
  echo "RAG_LOG_FILE not set or not found; skipping RAG log grep"
fi

echo
echo "Done. If AI checks pass here, run Telegram final check with the same 3 prompts."
