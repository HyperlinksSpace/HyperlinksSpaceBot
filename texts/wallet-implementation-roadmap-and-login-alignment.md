# Wallet implementation roadmap — align with the final security model and login UI

This document describes **what exists today**, **what to change** to match [`final-security-model.md`](final-security-model.md), and how that fits the **product login model** (Welcome screen: **Google, GitHub, Apple, Telegram, email**), consistent with [`login-and-telegram-messages-architecture.md`](login-and-telegram-messages-architecture.md).

---

## 1. Current implementation (baseline)

| Area | Today |
|------|--------|
| **Database** | Neon Postgres; `users` / `wallets` created in [`database/start.ts`](../database/start.ts). |
| **Wallet rows** | Public metadata: `wallet_address`, `wallet_blockchain`, `wallet_net`, `type`, labels, etc. Keyed primarily by **`telegram_username`** for lookups. |
| **Secrets** | No **`ciphertext`**, **`wrapped_dek`**, or AEAD metadata columns in the shipped schema; no envelope encryption wired to product flows. |
| **API** | [`api/_handlers/wallet-register.ts`](../api/_handlers/wallet-register.ts) / `wallet-status.ts` — **Telegram `initData`** auth only; same DB helpers as the bot. |
| **KMS** | GCP KMS **KEK** and [`api/_lib/envelope-*.ts`](../api/_lib/envelope-crypto.ts) are **probed** from diagnostics routes; not yet the single path for persisting user wallet secrets. |

So: **infrastructure for KMS + envelope exists**; **product wallet storage is still “address + Telegram identity,”** not the full model.

---

## 2. Target: what “fully making the model” means

1. **Envelope encryption in Postgres:** each wallet record (or a sibling row) stores **`ciphertext`**, **`wrapped_dek`**, **algorithm id / version**, **nonce/IV**, **KMS key version**, timestamps — **never** plaintext mnemonic or private key in a column.
2. **KEK only in GCP KMS** — wrap/unwrap DEKs via the vault path already aligned with [`infra/gcp/backend-authentication.md`](../infra/gcp/backend-authentication.md).
3. **Separation of duties:** user-facing API uses a **restricted DB role**; a **vault** service (or module + role) performs KMS operations and reads/writes envelope columns — **no shared superuser** for both planes in production (see `final-security-model.md` §5).
4. **Explicit trust variant:** document whether you ship **passphrase-derived client encryption** (non-custodial hybrid) or **custodial** unwrap/signing — same envelope shape, different who sees plaintext.

---

## 3. Login model compliance (Welcome screen)

The **Welcome** flow offers **Continue with Google, GitHub, Apple, Telegram**, and **email**. The security model requires **one canonical user** for wallets regardless of entry point.

### 3.1 Rules (from architecture docs, applied to wallets)

| Surface | Identity source | Wallet linkage |
|--------|------------------|----------------|
| **Telegram Mini App** | Verified **`initData`** → stable `telegram_user_id` / username | Map to internal **`user_id`**; wallet APIs must not assume Telegram is the only key forever. |
| **Web / native (Welcome screen)** | **OAuth** (Google, GitHub, Apple) or **email OTP** | Same **`user_id`** after you implement `auth_identities` (or equivalent): `(provider, provider_subject)` → one user. |
| **Cross-linking** | User may connect more providers later | Wallets are keyed by **`user_id`**, not by `telegram_username` alone. |

### 3.2 Schema direction

- Introduce a stable **`user_id`** (UUID or bigint) as the **primary owner** of wallet rows.
- Store **linked identities** in a separate table (e.g. `auth_identities`: `user_id`, `provider`, `provider_subject`, verified flags).
- **Migrate** existing `wallets.telegram_username` usage to **`user_id`** (backfill from `users` where Telegram already created the row).
- **APIs:** new routes accept **session / JWT / cookie** from your chosen auth (or Supabase Auth later) for web; TMA keeps **`initData`** verification server-side, then resolves to the same **`user_id`**.

Until **`user_id`** exists everywhere, **Google/GitHub/Apple/email** cannot attach wallets to the same logical account as TMA without ad-hoc merging — implement identity linking **before** or **in parallel with** envelope columns.

---

## 4. Phased roadmap (recommended order)

### Phase A — Identity foundation (blocks clean wallet crypto)

1. Add **`users.id`** as canonical **`user_id`** if not already the sole key; add **`auth_identities`** (or adopt Supabase Auth and map to your `user_id`).
2. Implement **Welcome** providers end-to-end for **at least one OAuth + email** on web, with the same **`user_id`** model as Telegram.
3. Refactor wallet DB access from **`telegram_username`**-only to **`user_id`** (keep username as display metadata).

### Phase B — Envelope schema + migrations (Neon)

1. Migration: add nullable **`ciphertext`**, **`wrapped_dek`**, **`envelope_version`**, **`kms_key_name` or version id**, **`nonce`**, **`aead_alg`** to the wallet record (or a dedicated `wallet_secrets` table with `user_id` + `wallet_id` FK).
2. Backfill: existing rows may have **address-only**; mark them **`envelope_status = legacy_plain_address`** or similar until user re-seeds or migrates.
3. **DB roles:** create **`app_rw`** (no envelope columns if split) vs **`vault_rw`** — or use **RLS** / column-level grants on one DB (see `final-security-model.md`).

### Phase C — Vault service boundary

1. Move KMS wrap/unwrap + read/write of **`wrapped_dek` / `ciphertext`** into a **dedicated module or microservice** invoked only after **authorization** (valid session + policy).
2. User service credentials: **cannot** `SELECT` envelope columns if using role split on one Postgres.
3. Logging: structured audit for every unwrap (user id, request id, outcome).

### Phase D — Client and API contracts

1. **Create wallet:** client generates or receives key material per your trust variant → encrypt with DEK → server receives ciphertext + requests KMS wrap of DEK → store **`wrapped_dek` + ciphertext**.
2. **Sign / reveal:** only through defined flows; rate-limit unwrap; optional **user passphrase** step for non-custodial variant.
3. Deprecate any path that sends **mnemonic in clear** over the wire except inside TLS to a documented custodial endpoint (if you ever allow that).

### Phase E — Optional Supabase migration

- If you adopt **Supabase Auth**, migrate **identity** tables or sync `auth.users` mapping to your **`user_id`**; **wallet envelope tables** remain ordinary Postgres tables in the same project or stay on Neon until you consolidate.

---

## 5. Compliance checklist (login model × security model)

- [ ] Every Welcome provider resolves to **`user_id`** used in wallet FKs.
- [ ] Telegram TMA and web OAuth users can **link** accounts so one person does not get duplicate wallets.
- [ ] Wallet APIs require **proven identity** (verified `initData` or valid OAuth/email session), not guessable usernames.
- [ ] **No** plaintext wallet secrets in Neon; **KEK** only in **GCP KMS**.
- [ ] **No** shared DB superuser between “profile API” and “vault” in production.
- [ ] Incident + rotation procedures documented (see `final-security-model.md` §7).

---

## 6. Related documents

- [`texts/final-security-model.md`](final-security-model.md) — KEK/DEK, Neon/Supabase, GCP, service split.
- [`texts/login-and-telegram-messages-architecture.md`](login-and-telegram-messages-architecture.md) — TMA vs Welcome screen, linking.
- [`texts/auth-and-centralized-encrypted-keys-plan.md`](auth-and-centralized-encrypted-keys-plan.md) — deeper envelope + multi-provider narrative (align DB naming with Neon when coding).
- [`infra/gcp/backend-authentication.md`](../infra/gcp/backend-authentication.md) — KMS env and verification.

---

## 7. One-sentence summary

**Evolve wallets from Telegram-keyed address rows to `user_id`-keyed envelope rows (ciphertext + wrapped_dek) under GCP KMS, introduce real multi-provider identity linking to match the Welcome screen, and enforce vault vs user-plane DB roles — that is how the current code path grows into the final security model.**
