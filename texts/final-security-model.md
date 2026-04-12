# Final security model — wallets, identity, Neon, Supabase, and GCP KMS

This document merges the approaches discussed for this program: **envelope encryption** with **Google Cloud KMS**, **PostgreSQL** for durable data (**Neon** today), optional **Supabase** later, and **strict separation** between “who the user is” and “where key material lives.”

It is a **target architecture**: implement in phases, but keep these boundaries so you do not paint yourself into a corner.

---

## 1. Security goals

1. **No plaintext wallet secrets at rest** in application databases (no mnemonic / private key in clear in Postgres).
2. **KEK never in the DB and never in app source** — only inside **GCP KMS** (or successor HSM-backed key).
3. **Separation of duties:** the components that **identify users** and serve product data should **not** be able to read key envelopes **by construction** (different credentials / roles / optional different stores), not only by “we don’t query that table.”
4. **Defense in depth:** KMS IAM + DB least privilege + unwrap policy (session, rate limits, audit) + envelope encryption (DEK vs KEK).
5. **Operational clarity:** one story for rotation, incidents, and audits.

---

## 2. Cryptographic model (envelope encryption)

| Concept | Role | Where it lives |
|--------|------|----------------|
| **KEK** (key encryption key) | Wraps the DEK | **GCP KMS** only (`wallet-kek` / resource name in config). |
| **DEK** (data encryption key) | Encrypts wallet payload (mnemonic / key material ciphertext) | **Never stored plaintext**; stored only as **wrapped_dek** (KMS encrypt output). |
| **Wallet ciphertext** | Payload encrypted with DEK (AEAD) | **PostgreSQL** (Neon or any Postgres). |
| **wrapped_dek** | DEK encrypted under KEK | **PostgreSQL** (same row or same logical store as ciphertext, per product design). |

**Why both `ciphertext` and `wrapped_dek`:** KMS is for wrapping **small** keys; bulk data uses the DEK. KEK rotation can re-wrap DEKs without re-encrypting all payloads in one shot (standard envelope pattern).

**Session vs keys:** Login (Telegram `initData`, future OAuth, email OTP) proves **identity**. It is **not** the KEK. The KEK stays in KMS; **authorization** (who may trigger unwrap) is enforced in your **vault** path.

---

## 3. Data plane: Neon today, Supabase optional later

### 3.1 Neon (current direction in this repo)

- **Single PostgreSQL** (Neon) can hold **users**, **sessions/metadata**, and **wallet envelope columns** (`ciphertext`, `wrapped_dek`, algorithm version, nonce, timestamps).
- Use **portable SQL** migrations so the schema can move to another Postgres host later.
- **Identity** is whatever you implement today (e.g. Telegram-verified users, internal `user_id`). This is **orthogonal** to KMS: same `user_id` links rows; KMS does not replace auth.

### 3.2 Supabase (optional future)

- **Supabase** is **Postgres + Auth + extras**. “Switching to Supabase later” usually means: **move the same database** to Supabase’s Postgres (or replicate), and optionally adopt **Supabase Auth** for Google/GitHub/email.
- **Wallet tables** stay standard Postgres; no requirement for a **second** database **only** for keys unless you have a compliance or isolation requirement (see §5).

### 3.3 Separate database only for keys?

- **Default:** one Neon (or one Supabase Postgres) for **both** app data and envelope rows, with **strict SQL roles** (see §5).
- **Split vault DB** adds real value when **different service**, **different credentials**, and **network isolation** mean the user-tier literally **cannot** connect to the vault DB. Otherwise two URLs in one `.env` often **collapse** the benefit (one breach → both strings).

---

## 4. Control plane: Google Cloud KMS and runtime identity

### 4.1 KEK in GCP KMS

- Single **symmetric KEK** (or versioned keys) in a dedicated **key ring** (e.g. `wallet-envelope` / `wallet-kek`).
- **IAM:** only designated service accounts (e.g. `wallet-kms-unwrap@...`) may **encrypt/decrypt** (wrap/unwrap) with that key. No broad editor access from app developers’ personal accounts in production.

### 4.2 Application credentials to GCP (implemented patterns)

- **Local / some servers:** `GOOGLE_APPLICATION_CREDENTIALS` → JSON key file (gitignored), or Workload Identity on GCP-hosted runtimes.
- **Vercel / serverless (Option B):** `GCP_SERVICE_ACCOUNT_JSON` — full JSON in a **secret** env var; client constructed as `new KeyManagementServiceClient({ credentials })` — **no** reliance on a temp file on disk.

### 4.3 What must never happen

- KEK material **not** in a database column.
- **Not** “KMS-ready” by putting a long-lived SA JSON in a public repo or pasting into chat.

---

## 5. Service boundaries: “user plane” vs “vault plane”

This is the model you preferred: **the service that knows users should not know keys.**

### 5.1 Two logical planes

| Plane | Knows | Should not know |
|-------|--------|------------------|
| **User / app API** | Users, profiles, sessions, product data | Key table contents, KMS unwrap except via a **narrow** internal contract |
| **Vault / crypto API** | `wrapped_dek`, ciphertext, KMS calls | Unnecessary PII beyond what is needed to authorize an operation |

### 5.2 Enforcing separation (not only “we don’t SELECT”)

- **Different DB roles:** e.g. `app_user` — `SELECT`/`INSERT`/`UPDATE` on `users`, … — **no** `SELECT` on `wallet_envelopes`. `vault_user` — only key-related tables (or only vault DB). **Never** run both planes with the **same superuser** in production.
- **Different secrets:** user API gets `DATABASE_URL` for restricted role; vault service gets **only** vault role (or second DB URL). Avoid one mega-`.env` with **both** full-power URLs for every worker.
- **Internal contract:** user service issues a **short-lived, scoped** proof (e.g. signed internal token, session id validated once) that vault checks before unwrap; vault does **not** trust arbitrary client input as sole proof.

### 5.3 What “loses” separation

- Same DB **superuser** for everything.
- Same deployment env with **both** unrestricted DB URLs + KMS SA for every route.
- Vault logic embedded in every API handler without role separation (works for MVP, **not** the final model).

---

## 6. Trust variants (product choice)

Document explicitly which you ship:

- **Non-custodial / hybrid:** user **passphrase** → KDF (e.g. Argon2id) → client-side encryption of sensitive payload; server stores ciphertext + wrapped_dek; KMS unwraps DEK only in defined flows. **Plaintext seed never sent** to server if you commit to that.
- **Custodial:** server holds unwrap path end-to-end; simplest operationally, strongest regulatory/custody implications.

The **KMS + envelope** structure is the same; **who** sees plaintext changes.

---

## 7. Operational security

- **Audit:** log KMS unwrap attempts (user id, request id, outcome) in vault service; monitor anomalies.
- **Rate limits** on unwrap and wallet operations.
- **Rotation:** KEK versioning + re-wrap DEKs; version columns in DB.
- **Incident:** disable SA key or IAM binding before chasing app bugs if KMS abuse is suspected.

---

## 8. Summary diagram (mental model)

```text
User auth (Telegram / future OAuth / OTP)
        │
        ▼
┌───────────────────┐     scoped intent      ┌───────────────────┐
│  User / app API   │ ──────────────────────► │  Vault service    │
│  (Neon: users…)   │                         │  (key rows + KMS) │
└───────────────────┘                         └─────────┬─────────┘
                                                        │
                                                        ▼
                                               ┌─────────────────┐
                                               │   GCP KMS (KEK)  │
                                               └─────────────────┘
        Postgres (Neon or Supabase Postgres)
        stores ciphertext + wrapped_dek (+ metadata)
        — not plaintext keys
```

---

## 9. Related docs in this repo

- [`texts/wallet-implementation-roadmap-and-login-alignment.md`](wallet-implementation-roadmap-and-login-alignment.md) — gap from current wallet code to this model + **Welcome** login (Google, GitHub, Apple, Telegram, email).
- [`infra/gcp/backend-authentication.md`](../infra/gcp/backend-authentication.md) — GCP SA, `GCP_SERVICE_ACCOUNT_JSON`, local verification curls.
- [`infra/gcp/kms.env.example`](../infra/gcp/kms.env.example) — env variable names.
- [`texts/auth-and-centralized-encrypted-keys-plan.md`](auth-and-centralized-encrypted-keys-plan.md) — deeper envelope + multi-provider auth narrative (Supabase-named; align with Neon when implementing).
- [`texts/login-and-telegram-messages-architecture.md`](login-and-telegram-messages-architecture.md) — TMA vs web identity.

---

## 10. One-line stance

**Neon (or later Supabase Postgres) holds encrypted wallet envelopes and user rows; GCP KMS holds the KEK; application code splits user plane and vault plane with separate DB privileges and secrets; no shared “god” credential across both planes in production.**
