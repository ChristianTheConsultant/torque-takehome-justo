# 8-char hex suffix keeps bucket names globally unique on re-launch
# without forcing the operator to invent a new name each time.
resource "random_id" "suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "this" {
  name     = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  force_destroy               = var.force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Keep storage costs bounded on a demo bucket: prune non-current versions
  # after 5 newer revisions exist.
  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  labels = merge(
    {
      managed_by = "torque"
      blueprint  = "simple-environment"
      iac        = "terraform"
    },
    var.additional_labels,
  )
}
