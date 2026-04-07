/**
 * Set Telegram webhook on deploy. Run during Vercel build.
 * Requires BOT_TOKEN and a base URL. Base URL is VERCEL_PROJECT_PRODUCTION_URL
 * (Vercel's production alias, e.g. hsbexpo.vercel.app) or VERCEL_URL (deployment-specific).
 */

const BOT_TOKEN = process.env.BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN;
const VERCEL_PROJECT_PRODUCTION_URL = process.env.VERCEL_PROJECT_PRODUCTION_URL;
const VERCEL_URL = process.env.VERCEL_URL;
const baseUrl =
  VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${VERCEL_PROJECT_PRODUCTION_URL}`
    : VERCEL_URL
      ? `https://${VERCEL_URL}`
      : '';

const WEBHOOK_PATH = '/api/bot';
const FETCH_TIMEOUT_MS = 15_000;

async function setWebhook(): Promise<void> {
  console.log(
    '[set-webhook] env: VERCEL_ENV=%s VERCEL_URL=%s VERCEL_PROJECT_PRODUCTION_URL=%s',
    process.env.VERCEL_ENV ?? '',
    VERCEL_URL ?? '(none)',
    VERCEL_PROJECT_PRODUCTION_URL ?? '(none)',
  );

  if (!BOT_TOKEN) {
    console.log('[set-webhook] Skip: BOT_TOKEN not set. Add BOT_TOKEN in Vercel → Settings → Environment Variables (Production, include in Build).');
    return;
  }

  if (!baseUrl) {
    console.log('[set-webhook] Skip: no webhook URL (VERCEL_URL / VERCEL_PROJECT_PRODUCTION_URL).');
    return;
  }

  const url = `${baseUrl}${WEBHOOK_PATH}`;
  console.log('[set-webhook] Setting webhook to:', url);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

  const res = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/setWebhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url }),
    signal: controller.signal,
  });
  clearTimeout(timeout);

  const data = (await res.json()) as { ok?: boolean; description?: string };
  if (data.ok) {
    console.log('[set-webhook] OK:', url);
    return;
  }

  console.error('[set-webhook] Telegram setWebhook failed:', data.description ?? data);
  process.exit(1);
}

setWebhook()
  .then(() => process.exit(0))
  .catch((err: Error) => {
    console.error('[set-webhook] Error:', err.message);
    process.exit(1);
  });
