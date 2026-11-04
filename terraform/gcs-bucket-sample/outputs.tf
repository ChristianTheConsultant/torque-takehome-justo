output "bucket_name" {
  description = "The fully-qualified name of the created GCS bucket (prefix + random suffix)."
  value       = google_storage_bucket.this.name
}

output "bucket_url" {
  description = "The gs:// URL of the bucket."
  value       = google_storage_bucket.this.url
}

output "bucket_self_link" {
  description = "The GCS API self-link to the bucket, useful for downstream automation."
  value       = google_storage_bucket.this.self_link
}

output "bucket_location" {
  description = "The location (region) the bucket was created in."
  value       = google_storage_bucket.this.location
}
