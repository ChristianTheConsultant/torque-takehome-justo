# How a downstream Kubernetes grain reaches this cluster without a Torque
# agent installed in it:
#
#   1. A service account with cluster-admin is created in the new cluster,
#      together with a long-lived token for it.
#   2. A kubeconfig for that token is written as a Secret into the agent's
#      own cluster (default kubernetes provider, in-cluster config).
#   3. The Kubernetes grain names that Secret and the context in
#      agent.kubernetes.permissions, and the agent uses it to deploy.
#
# The kubeconfig deliberately does not carry the runner's Google access
# token: that expires after an hour, and Torque tears the Kubernetes grain
# down before this one, so an expired token would fail the teardown and
# leave the cluster running.

data "google_client_config" "current" {}

resource "kubernetes_namespace_v1" "app" {
  provider = kubernetes.cluster

  metadata {
    name = var.app_namespace
  }

  # Wait for the node pool so no cluster operation is still running when
  # the API is first called.
  depends_on = [google_container_node_pool.primary]
}

resource "kubernetes_service_account_v1" "deployer" {
  provider = kubernetes.cluster

  metadata {
    name      = "torque-deployer"
    namespace = "kube-system"
  }

  depends_on = [google_container_node_pool.primary]
}

# cluster-admin because the cluster is single-purpose and ephemeral, and the
# same kubeconfig is what an environment consumer downloads to work with it.
resource "kubernetes_cluster_role_binding_v1" "deployer" {
  provider = kubernetes.cluster

  metadata {
    name = "torque-deployer"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.deployer.metadata[0].name
    namespace = kubernetes_service_account_v1.deployer.metadata[0].namespace
  }
}

resource "kubernetes_secret_v1" "deployer_token" {
  provider = kubernetes.cluster

  metadata {
    name      = "torque-deployer-token"
    namespace = kubernetes_service_account_v1.deployer.metadata[0].namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.deployer.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

locals {
  kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = var.cluster_name
      cluster = {
        server                     = "https://${google_container_cluster.primary.endpoint}"
        certificate-authority-data = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
      }
    }]
    users = [{
      name = "torque-deployer"
      user = {
        token = kubernetes_secret_v1.deployer_token.data["token"]
      }
    }]
    # The context name is what the Kubernetes grain selects with
    # destination-context-name, so it matches the kubernetes_cluster_name
    # output.
    contexts = [{
      name = var.cluster_name
      context = {
        cluster   = var.cluster_name
        user      = "torque-deployer"
        namespace = kubernetes_namespace_v1.app.metadata[0].name
      }
    }]
    current-context = var.cluster_name
  })
}

resource "kubernetes_secret_v1" "kubeconfig" {
  metadata {
    name      = "${var.cluster_name}-kubeconfig"
    namespace = var.kubeconfig_secret_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "torque"
    }
  }

  # Torque's docs don't name the data key the agent reads, so the same
  # kubeconfig is stored under both common keys.
  data = {
    kubeconfig = local.kubeconfig
    config     = local.kubeconfig
  }
}
