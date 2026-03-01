# TS AI/RAG In-Bot Skeleton (Minimal)

## Current repo reality (as of 2026-03-01)

- `app/` uses `grammy` for webhook + local bot helper (`app/bot/*`), currently minimal.
- `packages/bot/` is already a TypeScript grammY package with reusable bot entrypoints.
- `bot/`, `ai/`, and `rag/` are Python services (separate runtime/deploy path in current docs).
- Deploy shape in root docs is multi-service (`bot` + `ai` + `rag` + frontend), not a single Node container.

## Added TS skeleton (bot-internal only)

New modules under `packages/bot/src/`:

- `ai.ts` - single public `generateAnswer()` flow.
- `rag.ts` - in-bot context fetch + ticker extraction + TTL cache (`swap.coffee` source adapter).
- `llm.ts` - OpenAI-compatible LLM client.
- `fallback.ts` - token-specific fallback narrative + language detection.
- `types.ts` - shared TS contracts.

No microservice split is introduced here; this is bot-local logic only.

## Incremental cutover path (no app-folder changes)

1. Phase 1 (parallel path): wire `generateAnswer()` into TS bot handlers, keep Python AI as temporary fallback.
2. Phase 2 (parity): port ticker fallback behavior fully to TS bot AI module and add snapshot/parity tests against Python outputs.
3. Phase 3 (switch): direct Telegram flows to TS bot AI path by default; keep Python endpoint as rollback only.
4. Phase 4 (retire): remove Python AI dependency after metrics and response parity are stable.

## Wiring points

- For grammY webhook path, call `generateAnswer()` from the bot message handler.
- For local polling path, reuse the same handler path.
- Keep `app/` out of PR scope per direction.
