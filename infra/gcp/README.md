# Google Cloud — wallet envelope KMS (KEK)

This folder documents **Cloud KMS** resources aligned with [`texts/auth-and-centralized-encrypted-keys-plan.md`](../../texts/auth-and-centralized-encrypted-keys-plan.md): a **symmetric KEK** outside the database, used to wrap per-user DEKs (envelope encryption). Ciphertext and `wrapped_dek` stay in **Supabase** (or your DB); **KEK material stays in KMS**.

## Provisioned project: `hyperlinksspacebot`

| Resource | Value |
|----------|--------|
| API | `cloudkms.googleapis.com` (enabled) |
| Key ring | `wallet-envelope` |
| Location | `us-central1` |
| Crypto key (KEK) | `wallet-kek` |
| Protection level | **HSM** (Cloud HSM) |
| Purpose | Symmetric encrypt/decrypt |
| Service account | `wallet-kms-unwrap@hyperlinksspacebot.iam.gserviceaccount.com` |
| SA role on key | `roles/cloudkms.cryptoKeyEncrypterDecrypter` |

**Full key resource name** (use in application config):

```text
projects/hyperlinksspacebot/locations/us-central1/keyRings/wallet-envelope/cryptoKeys/wallet-kek
```

### Environment variables (backend / Edge Function)

Copy [`kms.env.example`](kms.env.example) and set secrets in your host (Vercel, Supabase secrets, etc.):

- `GCP_PROJECT_ID` — `hyperlinksspacebot`
- `GCP_KMS_KEY_NAME` — full resource name above
- `GCP_KMS_SERVICE_ACCOUNT_EMAIL` — service account email above

The runtime must authenticate as that service account (JSON key, or **Workload Identity** on Cloud Run/GKE — preferred in production).

**Step-by-step:** how to create the key, set env vars, host on Vercel vs GCP, and call `encrypt`/`decrypt` in Node — see **[backend-authentication.md](backend-authentication.md)**.

### Service account key (dev / non-GCP hosting only)

Do **not** commit key JSON. Create locally:

```bash
gcloud iam service-accounts keys create ./wallet-kms-unwrap-sa-key.json \
  --iam-account=wallet-kms-unwrap@hyperlinksspacebot.iam.gserviceaccount.com \
  --project=hyperlinksspacebot
```

Point `GOOGLE_APPLICATION_CREDENTIALS` at that file only on secure servers. Prefer Workload Identity or OIDC for production.

### Verify from CLI

```bash
gcloud kms keys describe wallet-kek \
  --location=us-central1 \
  --keyring=wallet-envelope \
  --project=hyperlinksspacebot
```

### Reproduce on another project

Use Terraform in [`terraform/`](terraform/README.md) or run:

```bash
PROJECT=your-project-id
REGION=us-central1

gcloud services enable cloudkms.googleapis.com --project="$PROJECT"

gcloud kms keyrings create wallet-envelope --location="$REGION" --project="$PROJECT"

gcloud kms keys create wallet-kek \
  --location="$REGION" \
  --keyring=wallet-envelope \
  --purpose=encryption \
  --protection-level=hsm \
  --project="$PROJECT"

gcloud iam service-accounts create wallet-kms-unwrap \
  --display-name="Wallet envelope KMS unwrap" \
  --project="$PROJECT"

gcloud kms keys add-iam-policy-binding wallet-kek \
  --location="$REGION" \
  --keyring=wallet-envelope \
  --member="serviceAccount:wallet-kms-unwrap@${PROJECT}.iam.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
  --project="$PROJECT"
```

Use `--protection-level=software` for cheaper non-HSM dev keys.

## Scope

- **In scope here:** KMS key ring + KEK + SA + IAM for encrypt/decrypt.
- **Not created here:** Supabase project, tables, or app code that calls KMS — those follow the auth plan phases.
