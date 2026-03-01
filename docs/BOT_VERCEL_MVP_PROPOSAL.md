# Proposal: MVP Telegram bot — same folder as frontend

## Summary

Add a **Telegram bot** in the **same repo and same frontend folder** (`front/`). **Recommended approach:**

- **JS webhook on Vercel** — Thin receiver in **`front/api/bot/`**: receives Telegram webhook POSTs, **forwards** the Update JSON to a Dart service, returns 200. If the Dart service is down, responds with a minimal fallback (e.g. “Service temporarily unavailable”) so the bot stays alive.
- **Televerse (Dart) for all logic** — Bot logic lives in **`front/bot/`** using [Televerse](https://pub.dev/packages/televerse). A small HTTP server on Railway/Fly/Cloud Run receives the forwarded updates and calls **`bot.handleUpdate(update)`**; all commands, conversations, and API calls are written in Dart/Televerse.

One webhook URL (Vercel); no need to expose the Dart host to Telegram. Env: `BOT_TOKEN` on both; `BOT_LOGIC_URL` on Vercel pointing to the Dart service. Later: add calls to your APIs (auth, AI, unified) from the Televerse handlers.

**Vercel-only (unified deploy):** Use **[Grammy](https://grammy.dev)** in **`front/api/bot/`**: the route receives the webhook and handles it **in-process** (no forwarding). One deploy with the app and other API routes. See "Vercel-only: Grammy + unified deploy" below.

---

## Can Televerse be hosted on Vercel?

**No.** Vercel’s serverless platform does not support the Dart runtime. Supported runtimes are Node.js, Python, Go, and Ruby. Televerse is a Dart package and requires the Dart VM, so it cannot run as a Vercel serverless function.

**To avoid deploying on another host:** Use **Grammy** (or raw Telegram API) in **`front/api/bot/`**. The webhook handler parses the Update, runs command logic, and sends replies. **Unified deploy:** app, config, ai, and bot all on Vercel in one project. One deploy, one host. See "Vercel-only: Grammy + unified deploy".

| Goal | Approach |
|------|----------|
| **Vercel-only, unified deploy** | [Grammy](https://grammy.dev) in `front/api/bot/`. Same route receives webhook and handles it (no forwarding). One deploy: app + API routes + bot on Vercel. |
| **Logic in Dart (Televerse)** | JS webhook on Vercel **forwards** the Update to a Dart service on **another host** (Railway/Fly/Cloud Run). Two deploys. |

---

## Vercel-only: Grammy + unified deploy

Use **Grammy** in **`front/api/bot/`** so the bot and the rest of the app deploy together on Vercel. One host, one deploy, no `BOT_LOGIC_URL`, no Dart service.

**No forwarding.** When you use Grammy on Vercel, the webhook route does **not** forward the request anywhere. The same serverless function receives the POST from Telegram and passes it **in-process** to Grammy’s `webhookCallback(bot, ...)`. Grammy runs your command handlers in that same invocation. There is no “thin gateway that forwards to Grammy” — the route **is** the Grammy handler. Forwarding (JS receives → HTTP forward → another service) only exists in the **JS + Televerse** setup, where the other service is on a **different host** (Railway/Fly/Cloud Run).

**Folder (Vercel-only):**

```text
front/
  api/
    config.js    # existing
    ai.js        # existing
    bot/
      route.js   # or route.ts — Grammy webhook handler (POST + GET)
  lib/           # Flutter app
  web/
```

**Handler (Grammy):** The webhook route receives the Telegram POST and passes it **in the same function** to Grammy’s `webhookCallback(bot, ...)`. No HTTP forward — Grammy runs in the same Vercel invocation and handles commands (e.g. `/start`, `/help`, `/ping`) and sends replies. You can call your unified/AI/auth APIs from handlers with `fetch` and `INNER_CALLS_KEY`.

**Config:** `BOT_TOKEN` in Vercel env only. Set webhook to `https://<vercel-domain>/api/bot`. No `BOT_LOGIC_URL`, no second host.

**Example (minimal Grammy webhook on Vercel):**

```js
// front/api/bot/route.js (or use route.ts)
import { Bot, webhookCallback } from "grammy";

const bot = new Bot(process.env.BOT_TOKEN);

bot.command("start", (ctx) => ctx.reply("Welcome! Open the app: ..."));
bot.command("help", (ctx) => ctx.reply("Commands: /start, /help, /ping"));
bot.command("ping", (ctx) => ctx.reply("Pong"));

// Optional: call your APIs (unified, AI, auth) from handlers
// bot.on("message", async (ctx) => { await fetch(UNIFIED_URL, ...); });

export const config = { runtime: "nodejs" };

export async function POST(req) {
  const body = await req.text();
  try {
    await webhookCallback(bot, "std/http")(new Request(req.url, { method: "POST", body, headers: req.headers }));
  } catch (e) {
    console.error(e);
  }
  return new Response(null, { status: 200 });
}

export async function GET() {
  return Response.json({ status: "ok", message: "Telegram bot webhook endpoint is running" });
}
```

**Unified deploy:** Flutter app, `api/config.js`, `api/ai.js`, and `api/bot` are all part of the same Vercel project. One `vercel deploy` (or Git push) updates app and bot together.

---

## Where to put the bot: suggested folder

**Recommended (JS webhook + Televerse logic):** Two parts in the same `front/` tree:

```text
front/
  api/              # Vercel serverless
    config.js       # existing
    ai.js           # existing
    bot/
      route.js      # JS: receive webhook, forward body to BOT_LOGIC_URL, fallback if down
  bot/              # Dart (Televerse) — all bot logic
    pubspec.yaml
    bin/
      server.dart   # HTTP server: receive POST → bot.handleUpdate(update)
    lib/
      bot/          # handlers (commands, AI, etc.)
  lib/              # Flutter app
  web/
```

- **`front/api/bot/`** — JS only: receive POST from Telegram, forward raw body to Dart service (`BOT_LOGIC_URL`), return 200; on timeout/failure, send minimal fallback via Telegram API and return 200. GET for health.
- **`front/bot/`** — All logic in Televerse (Dart). Deployed as a long-running process on Railway/Fly/Cloud Run; exposes an HTTP endpoint that receives the forwarded Update JSON and calls `bot.handleUpdate(Update.fromJson(...))`.

**Why this split**

- **One webhook URL** (Vercel). Telegram never talks to the Dart host.
- **Logic in Dart:** All commands and behavior live in Televerse; no duplicate logic in JS.
- **Antifragile:** If the Dart service is down, the JS gateway still replies (fallback) so the webhook stays valid.
- **Same folder:** One repo, one `front/` tree; app, JS gateway, and Dart bot code together.

---

## What “same folder” + “bot on Vercel” means here

- **Frontend / Mini App:** Flutter (Dart) in `front/lib/`, built and deployed to Vercel.
- **Recommended:** **JS webhook** in **`front/api/bot/`** (receive → forward to `BOT_LOGIC_URL` → fallback if down). **All bot logic** in **`front/bot/`** (Televerse, Dart) on Railway/Fly/Cloud Run; that service receives forwarded updates and runs `bot.handleUpdate(update)`. One webhook URL (Vercel); logic in Dart only.
- **Alternatives:** Vercel-only with full logic in JS (e.g. Grammy), or Dart-only with Televerse polling and no Vercel gateway — see later sections.
---

## Deployment

**Recommended (JS webhook + Televerse logic):**

- **Vercel:** Flutter app + `api/config.js`, `api/ai.js`, and **`api/bot`** (JS webhook). Set Telegram webhook to `https://<vercel-domain>/api/bot`. Env: `BOT_TOKEN`, **`BOT_LOGIC_URL`** (Dart service URL, e.g. `https://your-bot.up.railway.app/update`).
- **Dart service (Railway/Fly/Cloud Run):** Run the **`front/bot/`** app (HTTP server that receives POST with Update JSON and calls `bot.handleUpdate(update)`). Env: `BOT_TOKEN`. No webhook set on Telegram to this host — it only receives forwards from Vercel.

---

## Pros

| Point | Detail |
|-------|--------|
| **JS webhook + Televerse logic** | One webhook URL (Vercel). JS only receives and forwards; all logic in Dart/Televerse. Single place to write and maintain bot behavior. |
| **Same folder as frontend** | Gateway in `front/api/bot/`, logic in `front/bot/`; one repo, one `front/` tree. |
| **Antifragile** | If the Dart service is down, JS gateway sends a fallback reply and still returns 200 — bot stays alive. |
| **No duplicate logic** | Commands and AI live only in Televerse; JS is a thin forwarder. |
| **Incremental** | Ship JS gateway + minimal Dart endpoint first; add /start, /help, /ping, then AI and APIs in Televerse. |

---

## Cons / risks

| Point | Detail |
|-------|--------|
| **Vercel: Node/TS only** | Serverless doesn’t run Dart; webhook handler is TypeScript/Node. App stays Dart; bot in same folder but different runtime. |
| **Dart path: second host** | Bot process runs on Railway/Fly/Cloud Run, not Vercel. Two deploys (app on Vercel, bot elsewhere). |
| **Cold starts (Vercel)** | First request after idle can be ~1–3 s. Acceptable for most bots. |
| **Execution limit (Vercel)** | Free (e.g. 10 s) and Pro (e.g. 60 s). Keep the handler fast; offload heavy work to your APIs. |
| **No in-process state (Vercel)** | Stateless function; use env and external APIs/DB for any state. |
| **Python bot** | Current Python bot has more features. This MVP can coexist; migrate features gradually or keep Python for “full” mode. |

---

## Serverless constraints and how to meet them in the future

Vercel (and similar) serverless has fixed limits. The current design already respects most of them; below is what can bite later and how to stay within constraints or adapt.

| Constraint | Limit (typical) | How we meet it today | If we hit it later |
|------------|------------------|----------------------|--------------------|
| **Execution time** | Free ~10 s, Pro ~60 s (per request) | We 200 ACK immediately, then run `bot.handleUpdate(update)` in the same invocation. Handler stays short (commands, one AI call, etc.). | Keep work under the limit: short AI calls, or **offload** — e.g. handler enqueues the update (SQS, Inngest, etc.) and a worker (or your AI backend) does the work and sends the reply via Telegram API. Or move heavy flows to a **long-running service** (e.g. JS gateway forwards to Dart/Televerse or a worker). |
| **Cold start** | ~1–3 s first request after idle | Accepted for a bot; no change needed. | Optional: keep-warm ping or accept the delay. |
| **Memory** | e.g. 1 GB | Grammy + handlers are light. | If you add heavy deps or big in-memory work, trim or move that work to an API. |
| **No long-running process** | Request in, response out; no persistent connection | We use webhook only; no polling on Vercel. | Stays the same. Polling or WebSockets require a different host. |
| **Payload size** | Request/response body limits | We cap Telegram body with `TELEGRAM_BODY_LIMIT_BYTES`. | Keep cap; reject oversized with 413. |
| **Stateless** | No shared in-process state between requests | We use env vars and external APIs only. | Use DB or external store for any state; no change to approach. |

**Summary:** You can keep meeting serverless constraints by (1) **keeping the handler fast** (short AI/API calls, or trigger-and-return), (2) **offloading long work** to your AI backend or a queue + worker, and (3) **moving only the heavy or long-lived parts** to a long-running host (e.g. Televerse on Railway) if needed, while the webhook stays on Vercel. The current 200-ACK-then-handle pattern is already aligned with these limits; future growth is mainly about where the work runs (same function vs API vs worker), not changing the webhook contract.

---

## Recommendation

**Preferred: JS webhook (Vercel) + Televerse (Dart) for logic.**

1. **JS gateway** in **`front/api/bot/`**: receive webhook POST → forward body to `BOT_LOGIC_URL` → return 200; on timeout or error, send a minimal fallback reply (e.g. “Service temporarily unavailable” or static /start) via Telegram API and return 200. GET for health.
2. **Dart service** in **`front/bot/`**: HTTP server that receives the forwarded Update JSON and calls **`bot.handleUpdate(update)`**. All commands (/start, /help, /ping), AI, and API calls are implemented in **Televerse (Dart)**.
3. Set Telegram webhook to **`https://<vercel-domain>/api/bot`**. Env: `BOT_TOKEN` on both sides; **`BOT_LOGIC_URL`** on Vercel.

**Practical path**

- Add **`front/api/bot/route.js`** (or **`route.ts`**): POST = read body → `fetch(BOT_LOGIC_URL, { method: 'POST', body })` with timeout (e.g. 8s); on failure, call Telegram API to send fallback message, then return 200. GET = health JSON.
- Add **`front/bot/`**: Dart package with Televerse; small HTTP server (e.g. shelf, dart_frog, or raw `HttpServer`) that parses POST body and runs `bot.handleUpdate(Update.fromJson(jsonDecode(body)))`. Implement /start, /help, /ping and later AI/unified in Dart.
- Env: **`BOT_TOKEN`** (Vercel + Dart); **`BOT_LOGIC_URL`** (Vercel only). In `vercel.json`, route **`/api/bot`** to the JS function.

**Alternative (Vercel-only, unified deploy):** Use **Grammy** in **`front/api/bot/`** for the full bot. App + API routes + bot deploy together on Vercel. See section "Vercel-only: Grammy + unified deploy".

---

## MVP scope (concrete)

**Recommended (JS webhook + Televerse logic):**

1. **Folders**  
   - **`front/api/bot/`** — Vercel: `route.js` or `route.ts` (POST = receive → forward to `BOT_LOGIC_URL`; on failure, fallback reply; GET = health).  
   - **`front/bot/`** — Dart: HTTP server that receives POST body and calls `bot.handleUpdate(Update.fromJson(...))`; all logic in Televerse.

2. **JS webhook (Vercel)**  
   - **POST** → read body, `fetch(BOT_LOGIC_URL, { body })` with timeout; if OK, return 200. If timeout/fail, send minimal reply via Telegram API (e.g. "Service temporarily unavailable"), return 200.  
   - **GET** → `{ "status": "ok", "message": "Telegram bot webhook endpoint is running" }`.

3. **Dart / Televerse (logic)**  
   - `/start` → welcome + link to mini app.  
   - `/help` → short list of commands.  
   - (Optional) `/ping` → Pong.  
   - Later: call unified/AI/auth from Televerse handlers.

4. **Config**  
   - **Vercel:** `BOT_TOKEN`, **`BOT_LOGIC_URL`** (Dart service). Webhook set to `https://<vercel-domain>/api/bot`.  
   - **Dart service:** `BOT_TOKEN`.

5. **Later steps**  
   - Optional: secret token in webhook URL or header; add more commands and API calls in Televerse.

**MVP scope (Vercel-only, Grammy, unified deploy):**

1. **Folder:** **`front/api/bot/`** only — `route.js` or `route.ts` with Grammy. No `front/bot/`.
2. **Handler:** POST = pass request to Grammy `webhookCallback(bot, "std/http")`; GET = health JSON. Use Grammy for commands: `/start`, `/help`, `/ping`; optionally call unified/AI/auth via `fetch` from handlers.
3. **Config:** `BOT_TOKEN` in Vercel. Webhook = `https://<vercel-domain>/api/bot`. No `BOT_LOGIC_URL`.
4. **Deploy:** Same Vercel project as app and `api/config.js`, `api/ai.js`. One deploy updates everything.

---

## Using a Dart bot framework instead of Grammy

Yes, you can use a **Dart Telegram bot framework** instead of Grammy. The trade-off is where the bot runs.

| Choice | Bot runtime | Where it runs | Folder in repo |
|--------|-------------|---------------|----------------|
| **Grammy (Node/TS)** | TypeScript/Node | **Vercel** (same deploy as app) | `front/api/bot/` |
| **Dart framework** | Dart | **Railway / Fly.io / Cloud Run** (Dart VM) | `front/bot/` |

**Why:** Vercel serverless does **not** support the Dart runtime (only Node, Python, Go, Ruby). A Dart-based bot cannot run on Vercel. It must run on a host that supports Dart: Railway, Fly.io, Cloud Run, or a VPS. There you run a long-lived process (polling with `bot.start()`) or an HTTP server that receives forwarded updates and calls `bot.handleUpdate(update)`. No webhook is required if you use polling.

### Recommended Dart framework: Televerse

- **Package:** [televerse](https://pub.dev/packages/televerse) on pub.dev (`televerse: ^3.2.0`).
- **Features:** Telegram Bot API 9.4, Dart 3, type-safe. Supports **polling** (no webhook) and **webhook** (optional).
- **Docs:** [Televerse](https://pub.dev/packages/televerse).

**You don’t need a webhook.** Televerse can use **long polling** by default: call `await bot.start();` and the bot fetches updates from Telegram. No webhook URL or HTTPS endpoint required. Deploy the Dart process (e.g. on Railway, Fly, Cloud Run) and it runs as long as the process is up.

**Example (polling — simplest, no webhook):**

```dart
import 'package:televerse/televerse.dart';

final bot = Bot('BOT_TOKEN');

bot.command('start', (ctx) async => ctx.reply('Welcome! Open the app: ...'));
bot.command('help', (ctx) async => ctx.reply('Commands: /start, /help, /ping'));

await bot.start();  // Long polling — no webhook needed
```

**Optional — webhook** (e.g. for one public URL or future serverless): use `bot.startWebhook(webhookUrl: 'https://...', port: 8080)` or, in a serverless-style handler, `bot.handleUpdate(Update.fromJson(jsonDecode(event.body)))`. Only use webhook if you need the push model or multiple instances behind a load balancer.

**If you choose the Dart framework:**

- Put the bot in **`front/bot/`**: `pubspec.yaml` (add `televerse`), `bin/bot.dart`, `lib/bot/` (handlers). Same folder as the frontend, same repo.
- Use **polling** (`await bot.start();`) — no webhook to set; the process just runs and fetches updates.
- Deploy the bot to **Railway**, **Fly.io**, or **Cloud Run** (run `dart run bin/bot.dart` or a small Docker image). Keep the process running; no public webhook URL required.
- App and other API routes stay on **Vercel**; only the bot process runs on the other host.

So: **Grammy = bot on Vercel, one deploy. Dart framework (Televerse) = bot in Dart, same repo under `front/bot/`, deploy bot elsewhere.**

---

## Setting the webhook (Vercel-only)

For **Vercel-only** deployment, the webhook is set **once** via the Telegram Bot API. The endpoint that receives POSTs is your **Node/JS** handler in `front/api/bot/` — **not** Televerse (Televerse needs a long-running process and does not run inside Vercel serverless).

**How to set the webhook:**

1. **One-time:** Tell Telegram where to send updates:
   ```bash
   curl "https://api.telegram.org/bot<BOT_TOKEN>/setWebhook?url=https://<your-vercel-domain>/api/bot"
   ```
   Or from Node/script:
   ```js
   await fetch(`https://api.telegram.org/bot${process.env.BOT_TOKEN}/setWebhook?url=${encodeURIComponent('https://your-domain.vercel.app/api/bot')}`);
   ```
2. **Handler:** The code that runs when Telegram POSTs an update is **always JS/Node** on Vercel (e.g. Grammy or raw `fetch` to parse the Update and call `sendMessage`). There is no “set webhook through Televerse” on Vercel — Televerse is Dart and runs elsewhere.

**Recommended setup:** The handler in **`front/api/bot/`** is JS that **forwards** the request body to `BOT_LOGIC_URL` (Dart service). All logic runs in Televerse on the Dart host; JS does not implement commands. See "JS webhook + Televerse for logic (forwarding)".

---

## Vercel gateway + Televerse full bot (antifragile)

**Constraint:** Televerse needs a long-running process (or an HTTP server receiving forwarded updates); it cannot run inside Vercel serverless.

**Recommended strategy (JS webhook + Televerse for logic):**

1. **Vercel gateway** in **`front/api/bot/`** — JS only: receive webhook POST, **forward** body to **`BOT_LOGIC_URL`** (Dart service), return 200. On timeout/failure, send a **fallback** reply (e.g. "Service temporarily unavailable" or static /start) and return 200. Safe prod entry; Telegram only knows the Vercel URL.
2. **Dart service** in **`front/bot/`** — HTTP server that receives the forwarded Update and calls **`bot.handleUpdate(update)`**. All logic (/start, /help, /ping, AI, APIs) lives in **Televerse (Dart)**.
3. **If the Dart host goes down,** the JS gateway still responds with the fallback; the bot stays alive and the webhook stays valid.

So: **Vercel = thin receiver + forwarder + fallback; Televerse = all logic.** One webhook URL; no duplicate command logic in JS.

---

## JS webhook + Televerse for logic (forwarding)

**Yes.** You can have the **webhook in JS (Vercel)** and **write all bot logic in Televerse (Dart)** by making the JS handler a thin **forwarder**:

1. **Telegram** → POSTs the Update to **Vercel** (`/api/bot`).
2. **JS (Vercel)** receives the body, then **forwards** the same JSON to a **Dart service** (e.g. `https://your-bot-service.up.railway.app/update`). No business logic in JS — just validate, forward, return 200.
3. **Dart service** (Railway/Fly/Cloud Run) runs a small HTTP server that:
   - Receives the POST body (Telegram Update JSON).
   - Calls **`bot.handleUpdate(Update.fromJson(jsonDecode(body)))`** (Televerse’s serverless-style API).
   - All **logic** (commands, conversations, AI, etc.) lives in **Televerse (Dart)**.
4. **Fallback:** If the Dart service is down or times out, the JS gateway replies with a minimal response (e.g. “Service temporarily unavailable” or a simple /start message) and still returns 200 to Telegram so the webhook stays valid.

**Flow:**

```text
Telegram → [Vercel JS webhook] → HTTP forward → [Dart service: Televerse handleUpdate]
                ↓ (if Dart down)
           Minimal fallback reply
```

**JS (Vercel) — only receive and forward:**

```js
// front/api/bot/route.js (or bot.js)
const BOT_LOGIC_URL = process.env.BOT_LOGIC_URL; // Dart service URL

export async function POST(req) {
  const body = await req.text();
  if (!BOT_LOGIC_URL) return fallbackReply(body);
  try {
    const res = await fetch(BOT_LOGIC_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return fallbackReply(body);
  } catch {
    return fallbackReply(body);
  }
  return new Response(null, { status: 200 });
}
// fallbackReply: send a minimal reply via Telegram API (e.g. /start text) and return 200
```

**Dart (Televerse) — all logic:**

```dart
// On Railway/Fly/Cloud Run: HTTP server that receives forwarded updates
import 'package:televerse/televerse.dart';

final bot = Bot(Platform.environment['BOT_TOKEN']!);
bot.command('start', (ctx) async => ctx.reply('Welcome! ...'));
bot.command('help', (ctx) async => ctx.reply('...'));
// ... all other logic in Televerse

// In your HTTP handler (e.g. shelf, dart_frog, or raw HttpServer):
// final update = Update.fromJson(jsonDecode(request.body));
// bot.handleUpdate(update);
```

**Summary:** One webhook URL (Vercel). JS = receive + forward + fallback; Televerse = all logic on a Dart host. Env: `BOT_TOKEN` on both; `BOT_LOGIC_URL` on Vercel pointing to the Dart service.

---

## Key decisions (encounterings)

| Decision | Outcome |
|----------|---------|
| **Recommended approach** | **JS webhook (Vercel) + Televerse (Dart) for logic.** JS in `front/api/bot/` only receives and forwards to `BOT_LOGIC_URL`; all logic in `front/bot/` via `bot.handleUpdate(update)`. Fallback in JS if Dart is down. |
| **Bot in same folder as frontend** | Yes: `front/api/bot/` (JS gateway) and `front/bot/` (Televerse). Same repo, same `front/` tree. |
| **Webhook** | One URL: `https://<vercel-domain>/api/bot`. Telegram never hits the Dart host; JS forwards. |
| **Where is the logic?** | Televerse (Dart) only. JS has no command logic — forward + fallback only. |
| **Deploys** | Vercel (gateway + app); Railway/Fly/Cloud Run (Dart service). |
| **Vercel-only / unified deploy** | Use **Grammy** in `front/api/bot/`. **No forwarding** — same route receives and handles via `webhookCallback(bot, ...)` in-process. One deploy. See "Vercel-only: Grammy + unified deploy". |
| **Forwarding only when logic is elsewhere** | We **do not** forward from JS to Grammy on the same Vercel. Forwarding is only for the **JS → Dart/Televerse** setup (Dart on another host). |

---

## Summary table

| Question | Answer |
|----------|--------|
| Where does the bot live? | **Vercel-only:** `front/api/bot/` only (Grammy). **JS+Televerse:** `front/api/bot/` (forward) + `front/bot/` (Dart). Same folder as frontend. |
| Who receives the webhook? | **Vercel.** Set webhook to `https://<vercel-domain>/api/bot`. Vercel-only: Grammy handles in same route. JS+Televerse: JS forwards to Dart. |
| Where is the logic? | **Vercel-only:** Grammy in `front/api/bot/`. **JS+Televerse:** Televerse in `front/bot/`; JS only forwards. |
| Deploy bot on Vercel? | **Vercel-only:** Yes — Grammy in `front/api/bot/`, unified deploy with app. **JS+Televerse:** Gateway on Vercel; logic on Railway/Fly/Cloud Run. |
| Can Televerse run on Vercel? | **No.** For Vercel-only unified deploy, use **Grammy** in `front/api/bot/`. |
| Finish Python first? | Optional; this MVP can run in parallel. |

**Next steps (Vercel-only, Grammy, unified deploy):**  
1. Add **`front/api/bot/route.js`** (or **`route.ts`**) with Grammy: `webhookCallback(bot, "std/http")` in POST; GET = health. Implement /start, /help, /ping.  
2. Wire **`/api/bot`** in **`vercel.json`**. Set **`BOT_TOKEN`** in Vercel. Set webhook to `https://<vercel-domain>/api/bot`.  
3. Deploy: app + api + bot go out in one Vercel deploy.

**Next steps (JS webhook + Televerse logic):**  
1. Add **`front/api/bot/route.js`**: POST → forward body to `BOT_LOGIC_URL`, fallback on failure; GET = health.  
2. Add **`front/bot/`**: Televerse; HTTP server with `bot.handleUpdate(Update.fromJson(...))`. Deploy to Railway/Fly/Cloud Run. Set **`BOT_LOGIC_URL`** on Vercel.
