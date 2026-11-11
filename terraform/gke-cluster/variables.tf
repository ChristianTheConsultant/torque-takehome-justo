variable "project_id" {
  description = "GCP project ID where the network and GKE cluster will be created."
  type        = string
}

variable "zone" {
  description = "GCP zone for the zonal GKE cluster (e.g., us-central1-a). The region for the subnet is derived from it."
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "zone must be a GCP zone such as us-central1-a."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Also used as the kubeconfig context name and as the prefix for the network, subnet and kubeconfig Secret. Must be unique per environment, e.g. gke-<envId>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-40 chars, lowercase letters/digits/hyphens, start with a letter and end with a letter or digit."
  }
}

variable "node_count" {
  description = "Number of nodes in the cluster's node pool."
  type        = number
  default     = 2
}

variable "machine_type" {
  description = "Machine type for the node pool."
  type        = string
  default     = "e2-standard-2"
}

variable "app_namespace" {
  description = "Namespace created in the new cluster for the application grain to deploy into."
  type        = string
  default     = "online-boutique"
}

variable "kubeconfig_secret_namespace" {
  description = "Namespace in the Torque agent's own cluster where the kubeconfig Secret is written. Must be a namespace the agent's runner service account can create Secrets in and the agent can read from, normally the agent's namespace."
  type        = string
  default     = "torque-sandboxes"
}

variable "additional_labels" {
  description = "Additional labels merged into the default label set on the cluster."
  type        = map(string)
  default     = {}
}
