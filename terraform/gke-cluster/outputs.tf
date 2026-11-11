# The three outputs the Kubernetes grain plugs into
# agent.kubernetes.permissions. The hyphenated names match the Torque docs
# example this module recreates.

output "kubernetes_cluster_name" {
  description = "Name of the GKE cluster, which is also the context name in the kubeconfig Secret."
  value       = google_container_cluster.primary.name
}

output "secret-name" {
  description = "Name of the Secret in the agent's cluster that holds the kubeconfig for the new cluster."
  value       = kubernetes_secret_v1.kubeconfig.metadata[0].name
}

output "secret-namespace" {
  description = "Namespace of that Secret in the agent's cluster."
  value       = kubernetes_secret_v1.kubeconfig.metadata[0].namespace
}
