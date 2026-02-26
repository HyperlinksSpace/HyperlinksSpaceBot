const config = require('./config');

let cache = {
  ok: false,
  expiresAt: 0,
};

async function probeAiHealth() {
  if (!config.aiHealthUrl) return false;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.aiHealthTimeoutMs);

  try {
    const response = await fetch(config.aiHealthUrl, {
      method: 'GET',
      signal: controller.signal,
      cache: 'no-store',
    });
    return Boolean(response && response.ok);
  } catch (_) {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

async function isAiAvailableCached() {
  const now = Date.now();
  if (cache.expiresAt > now) {
    return cache.ok;
  }

  const ok = await probeAiHealth();
  cache = {
    ok,
    expiresAt: now + config.aiHealthCacheTtlMs,
  };
  return ok;
}

module.exports = {
  isAiAvailableCached,
};
