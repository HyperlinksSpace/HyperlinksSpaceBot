# Login model: Telegram Mini App vs other platforms + Telegram messages for AI

This document describes a **unified auth and messaging architecture** for Hyperlinks Space Program:

- **Telegram Mini App (TMA):** **instant login** — no separate registration screen; identity comes from Telegram.
- **Web / iOS / Android (outside TMA):** **explicit registration / sign-in** using the multi-provider model (Google, GitHub, Apple, Telegram, email + OTP), consistent with the “Welcome to our program” flow.
- **One logical user** across methods via **linked identities** (see also [`auth-and-centralized-encrypted-keys-plan.md`](auth-and-centralized-encrypted-keys-plan.md)).
- **Chat area:** surface **Telegram-origin messages** for **AI analysis** on every platform — choose **Bot API** vs **TDLib / Telegram API** deliberately (see §5).

---

## 1) Product intent (short)

| Surface | Login UX | Why |
|--------|-----------|-----|
| **Inside Telegram (Mini App)** | Open app → already “logged in” using Telegram user | Telegram provides signed user context (`initData`); forcing email/OAuth here is poor UX. |
| **Web / native apps** | Full auth UI: OAuth + email OTP | Users are not inside Telegram; need standard accounts and recovery. |
| **All platforms** | Same **user record** when identities are linked | Wallet, settings, and AI features stay consistent. |

---

## 2) Instant login in the Telegram Mini App (no registration)

### What “instant” means

- On first open, the Mini App receives **Telegram.WebApp** with **`initData`** (or `initDataUnsafe` for display-only before verify).
- Your **backend verifies** the cryptographic signature of `initData` (Telegram Bot API / server-side HMAC). After verification, you trust: `telegram_user_id`, optional username, name, language, etc.
- **Account creation:** the first successful verification can **create** a user row if none exists — without a separate “Sign up” form. That is still “registration” in the database, but **invisible** to the user.

### What you do not do in TMA (by default)

- Do not require Google/GitHub/email **before** the user can use the app, unless you have a strong product reason (e.g. mandatory email for compliance). Those belong on **other platforms** or optional **linking** later.

### Linking other providers later

- From TMA, user can open “Connect Google / email” to attach more login methods to the **same** `user_id` — same as in the centralized auth plan (`auth_identities` / Supabase linking).

---

## 3) Other platforms: registration model (reference UI)

Outside Telegram, the app uses a **dedicated auth screen**:

- **Continue with Google, GitHub, Apple, Telegram**
- **Email address** + **Continue** (magic link / OTP)

This maps to:

- **OAuth** via Supabase (or your IdP) for Google / GitHub / Apple.
- **Telegram Login Widget** or **OAuth-style Telegram** on web (different from Mini App `initData` — still yields a stable `telegram_user_id` when configured).
- **Email OTP** (`signInWithOtp` or equivalent).

Same **identity linking** rules as [`auth-and-centralized-encrypted-keys-plan.md`](auth-and-centralized-encrypted-keys-plan.md): one primary `user_id`, multiple `(provider, provider_subject)` rows.

---

## 4) Unified login model (single mental model)

### Canonical user key

- **Primary key:** internal `user_id` (e.g. Supabase `auth.users.id` UUID).

### Provider rows (examples)

| Provider | Subject | Typical use |
|----------|---------|-------------|
| `telegram` | `telegram_user_id` | TMA + Telegram Login |
| `google` | Google `sub` | Web / mobile |
| `github` | GitHub numeric id | Web / mobile |
| `apple` | Apple `sub` | Mobile / web |
| `email` | verified email | OTP login |

### Rules

1. **First login** with any method → create `user_id` + first identity.
2. **Subsequent logins** match existing identity or go through **account linking** (verified flow) to merge with an existing `user_id`.
3. **Telegram Mini App** always resolves to the identity row with `provider = telegram` and `provider_subject = <telegram_user_id>`.

This gives **one wallet, one AI history, one settings object** per person once linking is complete.

---

## 5) Telegram messages in the app: three API layers (Bot vs Mini App vs TDLib)

The product idea: **chat section** shows **Telegram-sourced** threads so **AI can analyze** them on **all platforms**.

Telegram documents **more than the Bot API**. In [TDLib – Build Your Own Telegram](https://telegram.org/blog/tdlib) they describe:

- A **free, open Telegram API** for **user** clients that talk to the **Telegram cloud** (third-party apps that compete with official clients).
- **[TDLib](https://telegram.org/blog/tdlib) (Telegram Database Library)** — handles network, encryption, and **local** storage so apps can implement **full** Telegram features on many platforms; used at scale (e.g. Bot API infrastructure, official Android X example in that post).

So **a full messaging client experience is officially in scope** of the platform — but it uses **TDLib / MTProto user sessions**, not the Bot API alone.

### 5.1 Layer A — Bot API + Mini App (lighter weight)

**Telegram Bot API** and **Mini Apps** are **not** a substitute for a user client:

- **Bot:** you only see chats where **your bot** participates (DMs with the bot, groups that added the bot, etc.).
- **Mini App:** gives **verified user identity** (`initData`), not a dump of the user’s entire Telegram history.

**What you can build reliably here**

- **Private chat with the bot:** user ↔ bot messages via bot updates.
- **Groups** where the bot is added (subject to privacy mode / admin rights).
- **Mini App + user context:** correlate stored bot messages with `telegram_user_id`, sync to your DB for web/mobile after account linking.
- **AI:** send lawfully stored excerpts to your AI pipeline on any platform — same as [`ai_bot_messages.md`](ai_bot_messages.md) style persistence if you add it.

**Limitation:** you do **not** get “all DMs and all groups” through the Bot API alone.

### 5.2 Layer B — TDLib / Telegram API (“build your own Telegram”)

For **broad** access to the user’s Telegram data (normal chats, groups, channels the **user** can access), the documented path is a **user** session via the **Telegram API** stack, typically through **TDLib**:

- User signs in as a **Telegram user** (phone / session), not as your bot.
- TDLib exposes **documented** methods; local DB is **encrypted** with a user-provided key (per Telegram’s TDLib announcement).
- This is the basis of **alternative Telegram clients**; it is a **large** product/engineering commitment (bindings, session lifecycle, store policies, security reviews).

**Caveats (still true):**

- **Engineering:** native or FFI integration, ongoing TDLib updates, performance and storage on device/server.
- **Trust:** user must trust **your** app with their Telegram session; handle secrets like a password.
- **Policy:** follow Telegram’s terms for API clients and app store rules.

### 5.3 Choosing a path for “chat + AI”

| Goal | Typical approach |
|------|-------------------|
| Ingest only what the **bot** sees | Bot API + your DB + AI (simplest ops). |
| **Full** Telegram-like inbox for AI | TDLib (or equivalent MTProto client) + explicit user consent + secure sync design. |
| Hybrid | Bot-first MVP; optional “Connect full Telegram” later via TDLib on **native** clients first (where TDLib is most mature). |

### 5.4 Recommended roadmap (revised)

- **Phase 1:** Bot + Mini App identity + store bot-visible messages for AI (fast path).
- **Phase 2:** Optional **export / forward-to-bot** flows for extra context without TDLib.
- **Phase 3:** If product requires full history — **TDLib**-based pipeline (per [Telegram’s TDLib post](https://telegram.org/blog/tdlib)), with security, consent, and compliance review **before** launch.

---

## 6) Cross-platform: same Telegram content for AI

Once `user_id` is unified:

1. **Telegram Mini App:** user is identified → fetch **server-stored** messages linked to `telegram_user_id` / `user_id`.
2. **Web / mobile:** same session (`user_id`) → same API returns the **same** stored threads for AI (no need to be inside Telegram for read-only analysis of **already ingested** data).

Ingestion happens either where Telegram delivers updates to **your bot**, or — if you adopt **TDLib** — where **your** client syncs user-visible chats into **your** backend under user consent (separate architecture).

---

## 7) End-to-end flows (condensed)

### 7.1 User only uses Telegram Mini App

1. Open Mini App → verify `initData` → `user_id` + telegram identity.
2. Optional: later link email/Google on web for recovery — same account.

### 7.2 User starts on web

1. Register with Google or email OTP → `user_id`.
2. Later open Mini App → Telegram login creates **telegram** identity; **link** to existing `user_id` via verified email or explicit “link account” flow.

### 7.3 AI on all platforms

1. **Bot path:** bot stores allowed messages → DB keyed by `user_id` / `telegram_user_id`.
2. **TDLib path (if built):** your sync service stores normalized messages with the same keys after user opt-in.
3. Any client with valid session calls **your** API → AI reads **your** DB copy (not raw Telegram cloud from the browser unless you design that explicitly).

---

## 8) Security and privacy (must-haves)

- **Verify** all Mini App `initData` server-side; never trust unsigned client-only fields for auth.
- **Consent** for storing messages for AI; clear retention and deletion.
- **Minimize** data: only fields needed for features; avoid logging raw tokens.
- Align with **Telegram Bot API / Mini App** terms; if you ship **TDLib**-based features, align with **Telegram API / client** expectations and your privacy policy.

---

## 9) Summary answers to the “main question”

| Question | Answer |
|----------|--------|
| **Instant login in Telegram?** | Yes: verify `initData`, create/use `user_id` without a registration UI. |
| **Registration model elsewhere?** | Yes: OAuth + email OTP screen like the reference design. |
| **One combined model?** | Yes: single `user_id` + linked identities (`telegram`, `google`, `email`, …). |
| **Telegram messages + AI everywhere?** | Yes: expose **your** stored copy via **your** API to all clients. **Bot API** only sees bot-participating chats. **Full** user-level history requires **TDLib / Telegram API** ([Telegram on TDLib](https://telegram.org/blog/tdlib)) — a major build, not a config toggle. |

---

## 10) Related documents

- [`auth-and-centralized-encrypted-keys-plan.md`](auth-and-centralized-encrypted-keys-plan.md) — Supabase, providers, wallet envelopes.
- [`docs/wallet-keys-telegram.md`](../docs/wallet-keys-telegram.md) — TMA storage of wallet keys (separate concern from account login).
- Telegram: [TDLib – Build Your Own Telegram](https://telegram.org/blog/tdlib) — official overview of TDLib and third-party clients on Telegram’s cloud.
