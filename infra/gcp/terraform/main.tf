resource "google_project_service" "kms" {
  project = var.project_id
  service = "cloudkms.googleapis.com"
}

resource "google_kms_key_ring" "wallet" {
  name     = var.key_ring_id
  location = var.region

  depends_on = [google_project_service.kms]
}

resource "google_kms_crypto_key" "wallet_kek" {
  name     = var.crypto_key_id
  key_ring = google_kms_key_ring.wallet.id
  # Optional: rotation_period = "7776000s" (requires compatible provider; gcloud needs next_rotation_time)

  purpose = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = var.protection_level
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "kms_unwrap" {
  account_id   = var.service_account_id
  display_name = "Wallet envelope KMS unwrap"
}

resource "google_kms_crypto_key_iam_member" "unwrap" {
  crypto_key_id = google_kms_crypto_key.wallet_kek.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.kms_unwrap.email}"
}
