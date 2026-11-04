terraform {
  # Torque's Terraform runner tops out at 1.5.5; nothing here needs newer.
  required_version = ">= 1.3.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    # Used for the post-deploy health check; 'retry' needs >= 3.2.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# Credentials come from the standard AWS env vars (AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY), injected by the Torque grain from the Parameter
# Store, or from the agent's IAM role if the grain uses 'authentication'.
provider "aws" {
  region = var.region

  default_tags {
    tags = merge(
      {
        managed_by = "torque"
        blueprint  = "aws-nextjs-rds"
        iac        = "terraform"
        env_name   = var.name_prefix
      },
      var.additional_tags,
    )
  }
}
