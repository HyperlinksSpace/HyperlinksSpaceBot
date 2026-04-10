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

### Option B — Pass JSON in code (no `GOOGLE_APPLICATION_CREDENTIALS`)

Install the client:

```bash
npm install @google-cloud/kms
```

```javascript
import { KeyManagementServiceClient } from "@google-cloud/kms";

const credentials = JSON.parse(process.env.GCP_SERVICE_ACCOUNT_JSON);

const kms = new KeyManagementServiceClient({ credentials });
```

Put **`GCP_SERVICE_ACCOUNT_JSON`** in the dashboard as a **secret** (the full JSON, one line or minified).

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

## Further reading

- [Authenticate to Cloud KMS](https://cloud.google.com/kms/docs/reference/libraries#authenticate_to_cloud_kms) (official)
- Main resource list: [`README.md`](README.md)
