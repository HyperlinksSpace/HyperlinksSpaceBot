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

GOLDEN_FILE="${GOLDEN_FILE:-ai/backend/tests/golden_prompts.json}"
LLM_PROVIDER="${LLM_PROVIDER:-unknown}"
MODEL="${MODEL:-${OLLAMA_MODEL:-${OPENAI_MODEL:-unknown}}}"
AI_HEALTH_JSON="/tmp/ai_health.json"
AI_CAPABILITIES_JSON="/tmp/ai_capabilities.json"
CAPABILITIES_AVAILABLE=0

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
echo "== AI provider/capability probe =="
probe_ai_capabilities() {
  local health_code capabilities_code
  health_code=$(curl -s -o "$AI_HEALTH_JSON" -w "%{http_code}" "$AI_BACKEND_URL/health")
  echo "/health -> HTTP $health_code"
  if [[ "$health_code" -eq 200 || "$health_code" -eq 503 ]]; then
    jq '{status, provider, response_format_version, llm: .dependencies.llm}' "$AI_HEALTH_JSON"
  else
    echo "WARNING: unexpected /health status"
    cat "$AI_HEALTH_JSON"
  fi

  capabilities_code=$(curl -s -o "$AI_CAPABILITIES_JSON" -w "%{http_code}" "$AI_BACKEND_URL/capabilities")
  echo "/capabilities -> HTTP $capabilities_code"
  if [[ "$capabilities_code" -eq 200 ]]; then
    CAPABILITIES_AVAILABLE=1
    jq . "$AI_CAPABILITIES_JSON"
  else
    CAPABILITIES_AVAILABLE=0
    echo "SKIP: /capabilities not available yet (continuing)"
  fi
}

capability_enabled() {
  local capability="$1"
  if [[ "$CAPABILITIES_AVAILABLE" -ne 1 ]]; then
    return 1
  fi
  jq -e --arg k "$capability" '((.capabilities // .)[$k]) == true' "$AI_CAPABILITIES_JSON" >/dev/null
}

probe_ai_capabilities

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

echo "== Golden checks (provider: $LLM_PROVIDER, model: $MODEL) =="
echo "Base URL: $AI_BACKEND_URL"
run_golden_checks() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "SKIP: golden file not found at $file"
    return 0
  fi

  local total failures
  total=$(jq '.cases | length' "$file")
  failures=0
  echo "Using golden file: $file (cases=$total)"

  while IFS= read -r case_json; do
    local name prompt response line case_kind required_capability
    name=$(jq -r '.name' <<<"$case_json")
    prompt=$(jq -r '.prompt' <<<"$case_json")
    case_kind=$(jq -r '.kind // "text"' <<<"$case_json")
    required_capability=$(jq -r '.requires_capability // ""' <<<"$case_json")

    if [[ -n "$required_capability" ]] && ! capability_enabled "$required_capability"; then
      echo "SKIP [$name] capability '$required_capability' is not reported as supported"
      continue
    fi

    if [[ "$case_kind" == "capability_tools_request" ]]; then
      local tool_http_code tool_body tool_last
      tool_http_code=$(
        curl -s -o /tmp/golden_tools_body.ndjson -w "%{http_code}" -N -X POST "$AI_BACKEND_URL/api/chat" \
          -H "Content-Type: application/json" \
          -H "X-API-Key: $API_KEY" \
          -d '{
            "messages":[{"role":"user","content":"Use tool if available. Otherwise reply briefly."}],
            "tools":[{"type":"function","function":{"name":"ping","description":"ping","parameters":{"type":"object","properties":{"value":{"type":"string"}}}}}],
            "stream":false
          }'
      )
      tool_body=$(cat /tmp/golden_tools_body.ndjson)
      if [[ "$tool_http_code" -ne 200 ]]; then
        echo "FAIL [$name] tool request returned HTTP $tool_http_code"
        echo "Response [$name]: $tool_body"
        failures=$((failures + 1))
        continue
      fi
      tool_last=$(printf "%s\n" "$tool_body" | tail -n 1)
      if ! printf "%s" "$tool_last" | jq -e '.response? | type=="string"' >/dev/null 2>&1; then
        echo "FAIL [$name] unexpected tool response shape"
        echo "Response [$name]: $tool_body"
        failures=$((failures + 1))
        continue
      fi
      echo "OK [$name]"
      continue
    fi

    line=$(
      curl -fsS -N -X POST "$AI_BACKEND_URL/api/chat" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d "$(jq -cn --arg p "$prompt" '{messages:[{role:"user",content:$p}],stream:false}')"
    )
    response=$(printf "%s\n" "$line" | tail -n 1 | jq -r '.response // ""')

    local case_failed
    case_failed=0

    while IFS= read -r expected; do
      [[ -z "$expected" ]] && continue
      if ! printf "%s" "$response" | grep -Fqi -- "$expected"; then
        echo "FAIL [$name] missing expected text: $expected"
        case_failed=1
      fi
    done < <(jq -r '.expect_contains[]?' <<<"$case_json")

    while IFS= read -r forbidden; do
      [[ -z "$forbidden" ]] && continue
      if printf "%s" "$response" | grep -Fqi -- "$forbidden"; then
        echo "FAIL [$name] found forbidden text: $forbidden"
        case_failed=1
      fi
    done < <(jq -r '.forbid_contains[]?' <<<"$case_json")

    if [[ "$case_failed" -eq 1 ]]; then
      failures=$((failures + 1))
      echo "Response [$name]: $response"
    else
      echo "OK [$name]"
    fi
  done < <(jq -c '.cases[]' "$file")

  if [[ "$failures" -gt 0 ]]; then
    echo "Golden checks failed: $failures/$total"
    exit 1
  fi

  echo "Golden checks passed: $total/$total"
}

run_golden_checks "$GOLDEN_FILE"

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
