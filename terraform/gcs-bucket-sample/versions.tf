terraform {
  required_version = ">= 1.3.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# credentials = null falls back to Application Default Credentials, which on
# the Torque runner pod resolve to the agent's service account (Workload
# Identity).
provider "google" {
  project     = var.project_id
  region      = var.region
  credentials = var.gcp_credentials_json
}
