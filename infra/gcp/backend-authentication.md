# How to connect your backend to Cloud KMS (step by step)

Your KMS key (`wallet-kek`) only allows **one specific identity** to call encrypt/decrypt: the service account  
`wallet-kms-unwrap@hyperlinksspacebot.iam.gserviceaccount.com`.

So the “next step” is: **make your server run as that identity** (or pass credentials that represent it). Google’s client libraries then talk to KMS automatically.

There is **no password** for KMS itself—you either attach the service account to the runtime, or you use a **key file** that proves you are that service account.

---

## 1. Create a service account key file (simplest for local dev)

Run on a machine where `gcloud` is logged in and can manage the project:

```bash
gcloud iam service-accounts keys create ./wallet-kms-unwrap-sa-key.json \
  --iam-account=wallet-kms-unwrap@hyperlinksspacebot.iam.gserviceaccount.com \
  --project=hyperlinksspacebot
```

This creates **one long-lived secret file**. Anyone with this file can call KMS as that service account—**treat it like a password**, never commit it, never paste it into chat.

**Tell Node (and most Google libraries) to use it:**

- **Linux / macOS / Git Bash:**

  ```bash
  export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/wallet-kms-unwrap-sa-key.json"
  ```

- **Windows (cmd):**

  ```cmd
  set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\wallet-kms-unwrap-sa-key.json
  ```

- **Windows (PowerShell):**

  ```powershell
  $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\wallet-kms-unwrap-sa-key.json"
  ```

After this, code that uses the default credential chain (`new KeyManagementServiceClient()` in Node) will **automatically** use that file.

**Rotate:** If the key leaks, delete it in [IAM → Service Accounts → Keys](https://console.cloud.google.com/iam-admin/serviceaccounts) and create a new one.

---

## 2. Hosting without a file path (Vercel, Railway, Fly, etc.)

Many hosts **do not** give you a stable disk path for secrets. Two common patterns:

### Option A — Secret file at build or startup

- Store the **contents** of `wallet-kms-unwrap-sa-key.json` in the host’s **secret env** (e.g. `GCP_SERVICE_ACCOUNT_JSON` as the full JSON string).
- At process startup, **write** that string to a temp file and set `GOOGLE_APPLICATION_CREDENTIALS` to that path, **or**
- Skip the file and pass credentials in code (Option B).

### Option B — Pass JSON in code (no `GOOGLE_APPLICATION_CREDENTIALS`) — **implemented in this repo**

`api/_lib/envelope-client.ts` calls `parseGcpServiceAccountJson()` from `envelope-env.ts`, then:

`new KeyManagementServiceClient({ credentials, fallback: /* REST by default */ })`.

- Set **`GCP_SERVICE_ACCOUNT_JSON`** in the host dashboard (Vercel → Project → Settings → Environment Variables) for **Production** (and Preview if needed). Value = **full contents** of `wallet-kms-unwrap-sa-key.json` (paste as one line or minified JSON). **Do not** commit it; **do not** set `GOOGLE_APPLICATION_CREDENTIALS` on Vercel for this path.
- If the variable is set but malformed, KMS routes throw at first client use with a clear error; **`GET /api/kmsping?diag=1`** returns `credentialSource`, `gcpServiceAccountJson`, and `gcpServiceAccountJsonError` without calling KMS.
- Redeploy after changing secrets so serverless functions pick up the new env.

**Vercel production check:**

```bash
curl -s "https://YOUR_DEPLOYMENT/api/kmsping?diag=1"
# Expect credentialSource: "json_env", gcpServiceAccountJson: "ok"

curl -s --max-time 120 -H "x-kms-ping-secret: YOUR_SECRET_IF_SET" \
  "https://YOUR_DEPLOYMENT/api/kms-roundtrip?roundtrip=1"
```

---

## 3. Backend runs on Google Cloud (Cloud Run / GKE / Cloud Functions)

Prefer **no JSON key file**:

1. Deploy the service with **that service account attached** as the runtime identity (e.g. Cloud Run: “Service account” = `wallet-kms-unwrap@...`).
2. Do **not** set `GOOGLE_APPLICATION_CREDENTIALS`.
3. Use the default client: libraries read credentials from the **metadata server** automatically.

This is what people mean by **Workload Identity** on GKE, or “run as service account” on Cloud Run.

---

## 4. Calling encrypt / decrypt (what “unwrap API” means in code)

You need the **full key name** (already in [`README.md`](README.md)):

```text
projects/hyperlinksspacebot/locations/us-central1/keyRings/wallet-envelope/cryptoKeys/wallet-kek
```

Symmetric key: use **Encrypt** to wrap a small blob (e.g. DEK), **Decrypt** to unwrap.

Example (Node.js) — **encrypt** plaintext (must be raw bytes, e.g. a 32-byte DEK):

```javascript
import { KeyManagementServiceClient } from "@google-cloud/kms";

const name =
  process.env.GCP_KMS_KEY_NAME ||
  "projects/hyperlinksspacebot/locations/us-central1/keyRings/wallet-envelope/cryptoKeys/wallet-kek";

const kms = new KeyManagementServiceClient();

/** @param {Buffer} plaintext */
export async function kmsEncrypt(plaintext) {
  const [result] = await kms.encrypt({
    name,
    plaintext,
  });
  return result.ciphertext; // Buffer — store this as wrapped_dek (e.g. base64 in DB)
}

/** @param {Buffer} ciphertext */
export async function kmsDecrypt(ciphertext) {
  const [result] = await kms.decrypt({
    name,
    ciphertext,
  });
  return result.plaintext;
}
```

- **Authentication** is implicit: the client uses `GOOGLE_APPLICATION_CREDENTIALS` or attached SA or `{ credentials }` as above.
- Your **HTTP “unwrap API”** is just a route that: checks the user session, loads `wrapped_dek` from the DB, calls `kmsDecrypt`, then continues (or returns material per your security model).

Set in your host:

- `GCP_KMS_KEY_NAME` = the full resource name string above (optional if hardcoded for one env).

---

## 5. Quick checklist

| Step | Action |
|------|--------|
| 1 | Create JSON key **or** attach SA on GCP **or** put JSON in a secret env |
| 2 | Ensure runtime uses that identity (env var or `KeyManagementServiceClient({ credentials })`) |
| 3 | Set `GCP_KMS_KEY_NAME` if you read it from env |
| 4 | Call `encrypt` / `decrypt` with the full key resource name |

If something fails with **403 Permission denied**, the running identity is not `wallet-kms-unwrap@...` or IAM on the key was changed.

---

## Verify from this repo (local)

With `GOOGLE_APPLICATION_CREDENTIALS` pointing at your `wallet-kms-unwrap-sa-key.json`, start the API (`npm run dev:vercel`). **`npm run dev:vercel` sets `SKIP_DB_MIGRATE=1`** so the initial build does not fail when `DATABASE_URL` / Neon is unreachable (production builds still run migrations via `vercel.json` `buildCommand`).

```bash
# Zero imports — if this fails, the dev server / port is wrong (see HeadersTimeoutError below)
curl -s "http://localhost:3000/api/kmsprobe"

# Public URLs (rewrites → route keys `wallet-envelope-*` in `api/[...path].ts` — see vercel.json)
curl -s "http://localhost:3000/api/kmsping?probe=1"
curl -s "http://localhost:3000/api/kmsping?diag=1"

# Instant usage JSON (no KMS call)
curl -s "http://localhost:3000/api/kmsping"

# KMS encrypt/decrypt — handler `wallet-envelope-roundtrip` in api/_handlers/ (via api/[...path].ts); slow first call — use max-time
curl -s --max-time 120 "http://localhost:3000/api/kms-roundtrip?roundtrip=1"
curl -s --max-time 120 "http://localhost:3000/api/kms-roundtrip?quick=1"

# Legacy paths
curl -s "http://localhost:3000/api/kms/ping?probe=1"
```

**Implementation:** one Vercel function **`api/[...path].ts`** dispatches to **`api/_handlers/wallet-envelope-*.ts`**, with shared **`api/_lib/envelope-env.ts`**, **`envelope-client.ts`**, **`envelope-crypto.ts`** (underscore-prefixed folders are not separate serverless routes). Avoid **`api/**/kms*.ts`** paths in filenames — `vercel dev` can hang with 0-byte responses. Public URLs stay **`/api/kmsping`**, etc., via **`vercel.json` rewrites**.

`GET /api/kmsping?quick=1` or `?roundtrip=1` returns **422** JSON pointing at **`/api/kms-roundtrip`**.

If `vercel dev` prints **“port 3000 is already in use”**, it listens on **3001** (or another port) — use that URL instead.

Expect **`"usage": true`** and a **`handler`** field mentioning **`wallet-envelope-ping`** from bare `/api/kmsping`. Full KMS: **`"roundtrip": true`** from **`/api/kms-roundtrip?roundtrip=1`** when IAM is correct. **`KMS_PING_SECRET`** applies to **`/api/kms-roundtrip`**, not to bare `/api/kmsping` / `?probe=1` / `?diag=1`.

**HeadersTimeoutError / `startsWith` crash:** KMS routes are implemented under **`api/_handlers/wallet-envelope-*.ts`** (rewritten to public **`/api/kmsping`**, etc.). Legacy **`/api/kms/ping`** and **`/api/kms-ping`** hit the same ping handler.

**Debugging:** `GET /api/kmsping?diag=1` returns configuration only. Watch **`[wallet-envelope-roundtrip]`** logs for **`/api/kms-roundtrip`**. **REST to KMS** is default; set `GCP_KMS_USE_GRPC=1` only if needed.

**“Still running after 10s”:** Heavy work is only on **`/api/kms-roundtrip`**. Bare **`/api/kmsping`** should be instant. Use **`curl --max-time 120`** for KMS calls.

**`curl` gets 0 bytes while `/api/ping` works:** Wallet KMS handlers mirror **`ping.ts`**: they support **legacy Node `res`** (`res.end`) as well as Web **`Response`**, because **`vercel dev`** may invoke API routes with `res` and never flush a returned `Response`.

If the request **hangs**: (1) set `GOOGLE_APPLICATION_CREDENTIALS` to an **absolute** Windows path, or put `wallet-kms-unwrap-sa-key.json` in the **project root**; (2) use `curl --max-time` so the shell does not wait forever; (3) restart `vercel dev` after changing env so the KMS client picks up credentials.

In production, set **`KMS_PING_SECRET`** in the environment and call (usage vs full KMS test):

```bash
curl -s -H "x-kms-ping-secret: YOUR_SECRET" "https://your-deployment/api/kmsping"
curl -s --max-time 120 -H "x-kms-ping-secret: YOUR_SECRET" "https://your-deployment/api/kms-roundtrip?roundtrip=1"
```

## Further reading

- [Authenticate to Cloud KMS](https://cloud.google.com/kms/docs/reference/libraries#authenticate_to_cloud_kms) (official)
- Main resource list: [`README.md`](README.md)
