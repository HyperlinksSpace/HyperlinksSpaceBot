# Wallet v1 – Instant Non-Custodial Creation (App Integration)

## Scope

Add wallet functionality to the existing app **without changing current UX/navigation**.  
We introduce a wallet layer: address generation, local encrypted storage, deploy flow, and DLLR status.

---

## State Machine

### State 0 — No Wallet
- Show "Create Wallet"
- Show "Restore Wallet" (if local blob exists)

### State 1 — Generating
- Spinner: "Creating wallet..."

### State 2 — Created (Instant)
- Display address immediately
- Copy button + QR
- Status: "Deploying..."

### State 3 — Deploying
- Poll deployment status
- Prevent duplicate deploy calls

### State 4 — Ready
- Address displayed
- DLLR status:
  - Allocated
  - Locked
  - Available
- Optional: Backup reminder

### State 5 — Restored
- Loaded from local storage
- Same as Ready/Deploying depending on status

---

## Local Storage Rules

Encrypted wallet blob:
- key: `awallet_v1`

Metadata:
- `wallet_address`
- `created_at`
- `last_seen_at`
- `deploy_status`

No plaintext private key exposure in UI.

---

## Required Backend Hooks

POST /wallet/create  
→ { address, encrypted_blob, public_key }

POST /wallet/deploy  
→ { address }  
← { status }

GET /wallet/status?address=...  
← { deployed, dllr_status, balances }

POST /wallet/restore  
→ { encrypted_blob }  
← { address }

---

## UI Additions (Minimal)

- Wallet widget panel (address + deploy + DLLR status)
- Reset wallet (clear local storage) with confirmation modal
