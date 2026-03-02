import crypto from 'crypto';
import { sql } from './db';

type TelegramUserPayload = {
  id?: number;
  username?: string;
  first_name?: string;
  last_name?: string;
  language_code?: string;
  [key: string]: unknown;
};

type VerifiedInitData = {
  auth_date?: string;
  query_id?: string;
  user?: TelegramUserPayload;
  [key: string]: unknown;
};

function normalizeUsername(raw: unknown): string {
  if (typeof raw !== 'string') return '';
  let s = raw.trim();
  if (s.startsWith('@')) s = s.slice(1);
  return s.toLowerCase();
}

function verifyTelegramWebAppInitData(
  initData: string,
  botToken: string,
  maxAgeSeconds: number = 24 * 3600,
): VerifiedInitData | null {
  if (!initData || !botToken) return null;

  try {
    const params = new URLSearchParams(initData);
    const data: Record<string, string> = {};

    for (const [key, value] of params.entries()) {
      data[key] = value;
    }

    const receivedHash = data['hash'];
    if (!receivedHash) return null;
    delete data['hash'];

    const authDateStr = data['auth_date'];
    if (authDateStr) {
      const authDate = Number(authDateStr);
      if (!Number.isFinite(authDate)) return null;
      const now = Math.floor(Date.now() / 1000);
      if (authDate > now + 60) return null;
      if (maxAgeSeconds != null && now - authDate > maxAgeSeconds) return null;
    }

    const sorted = Object.keys(data)
      .sort()
      .map((key) => `${key}=${data[key]}`)
      .join('\n');

    const dataCheckString = Buffer.from(sorted, 'utf8');

    // Replicate Telegram's spec: secret_key = HMAC_SHA256("WebAppData", bot_token)
    const secretKey = crypto
      .createHmac('sha256', 'WebAppData')
      .update(botToken)
      .digest();

    const computedHash = crypto
      .createHmac('sha256', secretKey)
      .update(dataCheckString)
      .digest('hex');

    // Timing-safe comparison
    const valid =
      receivedHash.length === computedHash.length &&
      crypto.timingSafeEqual(Buffer.from(receivedHash, 'hex'), Buffer.from(computedHash, 'hex'));

    if (!valid) return null;

    const result: VerifiedInitData = { ...data };

    if (data.user) {
      try {
        result.user = JSON.parse(data.user) as TelegramUserPayload;
      } catch {
        return null;
      }
    }

    return result;
  } catch {
    return null;
  }
}

async function handler(request: Request): Promise<Response> {
  if (request.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  let body: any;
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ ok: false, error: 'bad_json' }), {
      status: 400,
      headers: { 'content-type': 'application/json' },
    });
  }

  const initData = typeof body?.initData === 'string' ? body.initData : '';
  if (!initData) {
    return new Response(JSON.stringify({ ok: false, error: 'missing_initData' }), {
      status: 400,
      headers: { 'content-type': 'application/json' },
    });
  }

  const botToken = (process.env.BOT_TOKEN || '').trim();
  if (!botToken) {
    return new Response(JSON.stringify({ ok: false, error: 'bot_token_not_configured' }), {
      status: 500,
      headers: { 'content-type': 'application/json' },
    });
  }

  const verified = verifyTelegramWebAppInitData(initData, botToken);
  if (!verified) {
    return new Response(JSON.stringify({ ok: false, error: 'invalid_initdata' }), {
      status: 401,
      headers: { 'content-type': 'application/json' },
    });
  }

  const user: TelegramUserPayload =
    verified.user && typeof verified.user === 'object' ? (verified.user as TelegramUserPayload) : {};

  const telegramUsername = normalizeUsername(user.username);
  if (!telegramUsername) {
    return new Response(JSON.stringify({ ok: false, error: 'username_required' }), {
      status: 400,
      headers: { 'content-type': 'application/json' },
    });
  }

  const locale = typeof user.language_code === 'string' ? user.language_code : null;

  // Upsert user row in Neon.
  await sql`
    INSERT INTO users (telegram_username, locale, created_at, updated_at, last_tma_seen_at)
    VALUES (${telegramUsername}, ${locale}, NOW(), NOW(), NOW())
    ON CONFLICT (telegram_username) DO UPDATE
      SET locale = EXCLUDED.locale,
          last_tma_seen_at = NOW(),
          updated_at = NOW();
  `;

  return new Response(
    JSON.stringify({
      ok: true,
      telegram_username: telegramUsername,
    }),
    {
      status: 200,
      headers: { 'content-type': 'application/json' },
    },
  );
}

export default handler;
export const POST = handler;

