function env(name) {
  return (process.env[name] || '').trim();
}

function parseTimeoutMs(raw, fallbackMs) {
  const minMs = 200;
  const maxMs = 1500;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallbackMs;
  const normalized = Math.floor(parsed);
  if (normalized < minMs) return minMs;
  if (normalized > maxMs) return maxMs;
  return normalized;
}

function parseTtlMs(raw, fallbackMs) {
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallbackMs;
  return Math.floor(parsed);
}

function parseBodyLimitBytes(raw, fallbackBytes) {
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallbackBytes;
  return Math.floor(parsed);
}

module.exports = {
  botToken: env('BOT_TOKEN') || env('TELEGRAM_BOT_TOKEN'),
  webhookSecret: env('TELEGRAM_WEBHOOK_SECRET'),
  appUrl: env('APP_URL'),
  aiHealthUrl: env('AI_HEALTH_URL'),
  aiHealthTimeoutMs: parseTimeoutMs(env('AI_HEALTH_TIMEOUT_MS'), 1200),
  aiHealthCacheTtlMs: parseTtlMs(env('AI_HEALTH_CACHE_TTL_MS'), 30000),
  bodyLimitBytes: parseBodyLimitBytes(env('TELEGRAM_BODY_LIMIT_BYTES'), 262144),
};
