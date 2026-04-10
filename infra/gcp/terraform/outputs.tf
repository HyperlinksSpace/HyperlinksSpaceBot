output "kms_key_name" {
  description = "Full resource name for GOOGLE KMS Decrypt/Encrypt API"
  value       = google_kms_crypto_key.wallet_kek.id
}

output "service_account_email" {
  value = google_service_account.kms_unwrap.email
}

output "key_ring_id" {
  value = google_kms_key_ring.wallet.id
}
