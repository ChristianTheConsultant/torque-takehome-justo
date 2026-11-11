locals {
  labels = merge(
    {
      managed_by = "torque"
      blueprint  = "k8s-as-a-service"
      iac        = "terraform"
    },
    var.additional_labels,
  )
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # The node pool is managed as its own resource below, so GKE's default
  # pool is created only to satisfy the API and then removed.
  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.subnet.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.subnet.secondary_ip_range[1].range_name
  }

  release_channel {
    channel = "REGULAR"
  }

  # Ephemeral cluster: Torque has to be able to destroy it when the
  # environment ends.
  deletion_protection = false

  resource_labels = local.labels
}

resource "google_container_node_pool" "primary" {
  name       = "primary"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_type    = "pd-standard"
    disk_size_gb = 50

    # Nodes run as the project's default compute service account.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
