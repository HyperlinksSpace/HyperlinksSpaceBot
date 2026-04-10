# How official @wallet in Telegram handles keys and secrets

This note summarizes **Wallet in Telegram** (the product opened via [@wallet](https://t.me/wallet) or Telegram Settings → Wallet), based on its **public FAQ and help center**. It is **not** a description of this repository’s Mini App.

**Sources:** [wallet.tg](https://wallet.tg/), [help.wallet.tg](https://help.wallet.tg/) (e.g. [security measures](https://help.wallet.tg/article/11-is-my-wallet-connected-to-telegram), [TON Wallet](https://help.wallet.tg/article/4-ton-space)).

---

## Two different wallets inside one product

Wallet in Telegram offers a **dual-wallet** experience:

| | **Crypto Wallet** | **TON Wallet** (formerly “TON Space”) |
|---|---------------------|----------------------------------------|
| **Model** | **Custodial** — the service manages keys for you | **Non-custodial (self-custodial)** — you control the keys |
| **Typical UX** | Marketed as **no seed phrases** for everyday use — “tap and go” | You get a **Secret Recovery Phrase**; only you should have it |
| **If you lose access** | Support can help **recover** the custodial wallet (subject to verification and policies) | If you lose the **Recovery Phrase** and have no other recovery path, **funds may be unrecoverable** (standard self-custodial rule) |

So “how keys work” depends on **which tab/product** you use: custodial vs self-custodial are fundamentally different.

---

## Crypto Wallet (custodial): keys and “secrets”

- **Private keys** for the custodial balances are **not** held only on your phone as a classic hot wallet file you export. Official wording states that Crypto Wallet **securely manages your private keys** as a custodial service ([wallet.tg FAQ](https://wallet.tg/)).
- **What protects your account in practice** is layered on top of Telegram and Wallet-specific controls:
  - **Telegram account security** (sessions, optional **two-step verification** for Telegram login).
  - **Crypto Wallet passcode** (4–6 digits), used for sensitive actions such as withdrawals or certain flows; can be reset via a **linked email** recovery flow.
  - **Biometrics** (Face ID / Touch ID) as an optional convenience layer; official docs state biometrics are **stored only on your device** ([help article](https://help.wallet.tg/article/11-is-my-wallet-connected-to-telegram)).
- **Link to Telegram:** Crypto Wallet is tied to your **Telegram user ID**. Changing phone number or username does **not** by itself break access; **deleting your Telegram account** can cause loss of access to that Crypto Wallet unless you follow their guidance (e.g. move funds, verification/support flows).

In short: **on-chain keys for custodial balances are operated by the service**; **your** “secrets” in daily use are mainly **Telegram login**, **Wallet passcode**, and **device biometrics**, plus **email** for passcode/flows where applicable.

---

## TON Wallet (non-custodial): keys and secrets

- TON Wallet is described as **non-custodial**: **private key and Secret Recovery Phrase are only for you**; support will **never** ask for your phrase ([TON Wallet help](https://help.wallet.tg/article/4-ton-space)).
- On creation you should **write down the Secret Recovery Phrase**; it allows access from **any** compatible interface/device, **independent of which Telegram account** you use — the phrase is the root secret.
- **Optional email recovery** can be connected for easier login/recovery, but official guidance still stresses **keeping the Recovery Phrase** as the universal backup.
- You can **import** other non-custodial TON seed wallets; custodial/exchange wallets without a seed you control **cannot** be imported as non-custodial keys.

Here the “key storage” story matches classic self-custody: **the phrase encodes the keys**; Wallet in Telegram is an **interface** that uses that secret **you** hold.

---

## One-line mental model

- **Crypto Wallet:** trust and recovery are **service-mediated** (custodial keys + account/passcode/email layers).
- **TON Wallet:** trust is **user-mediated** (Recovery Phrase + optional email recovery), aligned with **self-custody**.

---

## Disclaimer

Product names, regions, and features change. For authoritative, up-to-date rules use **[wallet.tg](https://wallet.tg/)** and **[help.wallet.tg](https://help.wallet.tg/)**. This file is descriptive only, not legal or investment advice.
