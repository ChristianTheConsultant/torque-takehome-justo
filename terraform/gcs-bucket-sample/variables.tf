variable "project_id" {
  description = "GCP project ID where the bucket will be created."
  type        = string
}

variable "region" {
  description = "GCP region used as the bucket location (e.g., us-central1)."
  type        = string
  default     = "us-central1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the bucket name. An 8-character random hex suffix is appended for global uniqueness."
  type        = string
  default     = "torque-demo"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,53}[a-z0-9]$", var.bucket_name_prefix))
    error_message = "bucket_name_prefix must be 3-55 chars, lowercase letters/digits/hyphens, and start/end with a letter or digit."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to destroy the bucket even if it contains objects. Safe for ephemeral demo environments; should be false in production."
  type        = bool
  default     = true
}

variable "additional_labels" {
  description = "Additional labels merged into the default label set on the bucket."
  type        = map(string)
  default     = {}
}

variable "gcp_credentials_json" {
  description = "Full JSON contents of a GCP service account key. Wired directly into the Google provider's 'credentials' argument to bypass any env-var injection ambiguity. Sourced from Torque's Parameter Store; never paste into tfvars."
  type        = string
  sensitive   = true
}
