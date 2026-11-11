terraform {
  required_version = ">= 1.3.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}

# No credentials: on the Torque runner pod, Application Default Credentials
# resolve to the agent's service account through GKE Workload Identity.
provider "google" {
  project = var.project_id
  region  = local.region
}

# Default kubernetes provider: the cluster the Torque agent runs in. With no
# attributes set, the provider uses the runner pod's in-cluster service
# account. This is where the kubeconfig Secret for the new cluster is written.
provider "kubernetes" {}

# Aliased kubernetes provider: the new GKE cluster, authenticated with the
# runner's short-lived Google access token. Used only to bootstrap the
# long-lived service account the kubeconfig carries.
provider "kubernetes" {
  alias                  = "cluster"
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}
