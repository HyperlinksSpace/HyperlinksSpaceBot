variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "KMS location (must support Cloud HSM if protection_level is HSM)"
  default     = "us-central1"
}

variable "key_ring_id" {
  type    = string
  default = "wallet-envelope"
}

variable "crypto_key_id" {
  type    = string
  default = "wallet-kek"
}

variable "protection_level" {
  type        = string
  description = "HSM for production KEK; SOFTWARE for cheaper dev"
  default     = "HSM"

  validation {
    condition     = contains(["SOFTWARE", "HSM"], var.protection_level)
    error_message = "protection_level must be SOFTWARE or HSM."
  }
}

variable "service_account_id" {
  type    = string
  default = "wallet-kms-unwrap"
}
