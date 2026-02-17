# Wallet v1 API Contract (Stub for SMC/Backend Integration)

## Purpose

Define stable HTTP contracts for Wallet v1 so frontend and SMC/backend can integrate without ambiguity.
This document covers only API shape and semantics (no encryption or on-chain implementation details).

---

## Conventions

- Base path: `/wallet`
- Content type: `application/json`
- Auth: same internal auth model already used by services (`X-API-Key`) unless service owner decides otherwise
- Address format: TON user-friendly address string
- Time format: ISO-8601 UTC (`YYYY-MM-DDTHH:mm:ss.sssZ`)
- Idempotency:
  - `POST /wallet/create` should be idempotent per user context
  - `POST /wallet/deploy` should be idempotent per wallet address

---

## Enums

### `deploy_status`

- `not_started`
- `pending`
- `deployed`
- `failed`

### `dllr_status`

- `allocated` - amount credited in treasury logic
- `locked` - currently non-transferable
- `available` - released/unlocked for user use
- `none` - no DLLR state yet

---

## 1) POST `/wallet/create`

Create wallet identity and return encrypted local blob payload.

### Request

```json
{
  "user_id": "string-optional",
  "device_id": "string-optional"
}
```

### Success `200`

```json
{
  "address": "EQ...",
  "public_key": "hex-or-base64",
  "encrypted_blob": "base64-string",
  "created_at": "2026-02-17T17:00:00.000Z",
  "deploy_status": "not_started"
}
```

### Error codes

- `400` `invalid_request` - malformed body
- `401` `unauthorized` - missing/invalid auth
- `409` `wallet_already_exists` - if service chooses strict non-idempotent mode
- `500` `internal_error`

---

## 2) POST `/wallet/deploy`

Begin or continue deployment for a previously created wallet.

### Request

```json
{
  "address": "EQ..."
}
```

### Success `200`

```json
{
  "address": "EQ...",
  "deploy_status": "pending",
  "tx_hash": "optional-string",
  "updated_at": "2026-02-17T17:01:00.000Z"
}
```

### Error codes

- `400` `invalid_address`
- `401` `unauthorized`
- `404` `wallet_not_found`
- `409` `deploy_in_progress` - optional; can also return `200` + `pending` for idempotency
- `422` `wallet_not_ready_for_deploy`
- `500` `internal_error`
- `503` `smc_unavailable`

---

## 3) GET `/wallet/status?address=...`

Return deploy state and DLLR/balance summary for UI polling.

### Response `200`

```json
{
  "address": "EQ...",
  "deployed": true,
  "deploy_status": "deployed",
  "dllr_status": "available",
  "balances": {
    "ton": "0.420000000",
    "dllr": {
      "allocated": "10.00",
      "locked": "2.00",
      "available": "8.00"
    }
  },
  "last_synced_at": "2026-02-17T17:02:00.000Z"
}
```

### Error codes

- `400` `invalid_address`
- `401` `unauthorized`
- `404` `wallet_not_found`
- `500` `internal_error`
- `503` `smc_unavailable`

---

## 4) POST `/wallet/restore`

Restore wallet context from encrypted blob.

### Request

```json
{
  "encrypted_blob": "base64-string"
}
```

### Success `200`

```json
{
  "address": "EQ...",
  "public_key": "hex-or-base64",
  "restored_at": "2026-02-17T17:03:00.000Z",
  "deploy_status": "pending"
}
```

### Error codes

- `400` `invalid_blob`
- `401` `unauthorized`
- `404` `wallet_not_found`
- `422` `blob_decryption_failed`
- `500` `internal_error`

---

## Standard Error Body

All non-2xx responses should return:

```json
{
  "error": {
    "code": "machine_readable_code",
    "message": "Human readable message",
    "details": {}
  }
}
```

---

## Frontend Polling Guidance (Wallet Widget)

- After `create`: show address immediately, then call `deploy`
- While `deploy_status` is `pending`: poll `GET /wallet/status` every 2-3 seconds
- Stop polling when:
  - `deploy_status` is `deployed` or `failed`
- If `failed`: show retry action that calls `POST /wallet/deploy` again (idempotent)

