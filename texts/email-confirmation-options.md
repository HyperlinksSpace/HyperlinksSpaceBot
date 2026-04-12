# Email confirmation for your app: patterns and free (or nearly free) options

This document explains what “email confirmation” usually means in a product, how to implement it safely, and which providers fit a small budget. It is written to align with a stack that may already use **Supabase** for auth and a **serverless** or **Node** backend.

---

## 1) What you are actually building

**Email confirmation** (also called **email verification**) proves that the person who signed up controls the inbox they claimed. Typical goals:

- Reduce fake signups and spam accounts.
- Provide a recovery channel (password reset, “magic link” login) tied to a real address.
- Meet compliance or partner expectations (some APIs require verified users).

Two common UX patterns:

1. **Confirm before access** — user cannot use protected features until they click a link or enter a code from email.
2. **Soft verification** — limited access immediately; full access after verification (or reminders until verified).

Pick one and keep it consistent in your UI and API rules.

---

## 2) The standard technical flow

Regardless of provider, the core pieces are the same:

1. **Create user** (or pending user) in your auth system with `email_verified = false` (or equivalent).
2. **Generate a secret** — a random token (high entropy) or a short-lived signed JWT. Store only a **hash** of the token server-side if you persist it, or rely on the auth provider’s built-in tables.
3. **Send email** containing a link like `https://yourapp.com/confirm?token=...` or a **6-digit code** the user types in-app.
4. **Verify endpoint** validates the token/code, marks the account verified, and optionally starts a session.
5. **Expire** tokens quickly (often **15 minutes to 48 hours** depending on risk). Allow **resend** with rate limits.

Security notes:

- Use **HTTPS** everywhere for confirmation links.
- **Rate-limit** signup, resend, and verify endpoints (per IP and per email).
- Do not leak whether an email is registered in public error messages if that matters for your threat model (often you still want a generic “If an account exists, we sent instructions”).

---

## 3) “Free” solutions — what that really means

Truly unlimited free transactional email is rare. Most “free” tiers are **limited sends per day/month**, **developer-only**, or **require your own domain** for good deliverability. Plan for:

- **Domain + DNS** (SPF, DKIM, often DMARC) so messages do not land in spam.
- A **bounce/complaint** story as you grow (even if minimal at first).

Below are practical options grouped by how much you own the stack.

---

## 4) Auth platforms with built-in email confirmation (often the fastest path)

### Supabase Auth

If you already use **Supabase** for authentication, **email confirmation is a first-class feature**: configurable templates, redirect URLs, and user fields like `email_confirmed_at`. You still need an email **delivery** path; Supabase can send via their infrastructure on hosted projects (subject to plan limits and project settings), or you can integrate **SMTP** / providers for custom domains.

**Why consider it:** Less custom token plumbing; aligns with Row Level Security and user tables you may already use.

### Firebase Authentication

**Firebase Auth** supports email verification flows and integrates with Google’s stack. The **Spark** (free) plan has quotas; check current limits for your region and usage.

**Why consider it:** Mature client SDKs; good if you are already on Firebase.

### Clerk, Auth0, Cognito, etc.

Many hosted auth vendors include verification emails. **Free tiers vary** and often cap **monthly active users** or **branding**. Evaluate pricing when you are no longer in prototype phase.

---

## 5) Transactional email APIs (bring your own auth, or pair with your backend)

Use these when **your app** (or Supabase SMTP) must send “Confirm your email”, “Reset password”, “Invoice #123”.

| Provider | Typical free tier (check current docs) | Notes |
|----------|----------------------------------------|--------|
| **Resend** | Free monthly quota for small projects | Developer-friendly API; custom domain setup is straightforward. |
| **Brevo** (formerly Sendinblue) | Daily free send limit on free plan | Full marketing + transactional; watch branding and limits. |
| **SendGrid** | Limited free tier | Very common; verify sender and DNS records early. |
| **Mailjet** | Free tier with caps | Similar to SendGrid/Brevo in role. |
| **Amazon SES** | Not “free” forever, but **very low cost** at scale | Great if you are already on AWS; requires domain verification. |

**Integration pattern:** Your API creates the user + verification token, sends email through the provider’s API, and marks verified when the user completes the step.

---

## 6) SMTP from your VPS or “just use Gmail”?

You can send via **any SMTP** (company mail, self-hosted Postfix, etc.). **Google Workspace / Gmail SMTP** is possible for testing but is **not** a good long-term production strategy for bulk signup mail: strict rate limits, deliverability issues, and policy risk.

Prefer a **transactional provider** with APIs, webhooks for bounces, and clear DNS authentication steps.

---

## 7) Recommended decision paths (practical)

1. **Already on Supabase Auth**  
   Turn on email confirmation in the Supabase dashboard, configure **site URL and redirect URLs**, set up **custom SMTP** or provider as needed, and enforce `email_confirmed_at` (or JWT claims) in your API and RLS policies.

2. **Custom backend, minimal vendor lock-in**  
   Use **Resend**, **Brevo**, or **SendGrid** on the free tier for transactional mail; store verification state in your DB; implement rate limits and expiry.

3. **You need the cheapest reliable production path at scale**  
   Consider **Amazon SES** (low cost) plus your own token tables, or Supabase + SES SMTP depending on architecture.

---

## 8) Checklist before you ship

- [ ] HTTPS confirmation links; no tokens in browser `referrer` leaks if you use third-party analytics (prefer POST flows or one-time redeem).
- [ ] Token **expiry** and **one-time use** (or signed JWT with `exp`).
- [ ] **Resend** throttling; CAPTCHA on signup if abused.
- [ ] **SPF/DKIM** on your sending domain; test inbox placement (Gmail, Outlook).
- [ ] Logged-out user can **request a new email** if the first expires.

---

## 9) How this relates to other login methods

Email confirmation binds identity to an **email address**. It does not replace **strong authentication** for sensitive actions (e.g. changing email, disabling 2FA, moving funds). If you also support **OAuth** (Google, GitHub) or **Telegram**, define whether you require a verified email for certain actions or treat OAuth emails as pre-verified per provider policy.

---

## 10) References to verify (URLs change)

Look up the latest quotas and setup steps in each vendor’s documentation:

- Supabase: Auth → Email templates and SMTP configuration  
- Firebase: Authentication → Email link / verification  
- Resend, Brevo, SendGrid, Mailjet, AWS SES: “Getting started” and DNS records for sending domain

---

*Last updated: 2026-04-12*
