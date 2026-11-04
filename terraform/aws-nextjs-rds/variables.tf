# ---------------------------------------------------------------------------
# Naming / placement
# ---------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix applied to every resource name. Torque passes 'nextjs-<envId>' so parallel environments never collide."
  type        = string
  default     = "nextjs-demo"

  validation {
    # RDS identifiers are the strictest consumer: lowercase, start with a
    # letter, and '<prefix>-db' must stay under 63 chars.
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-42 chars, lowercase letters/digits/hyphens, start with a letter and end with a letter or digit."
  }
}

variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR for the dedicated VPC. Two public /24s (EC2) and two private /24s (RDS) are carved out of it."
  type        = string
  default     = "10.42.0.0/16"
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach the web app on app_port. 0.0.0.0/0 is fine for a throwaway demo; narrow it to your IP otherwise. The Torque agent's egress IP must be included when wait_for_app is true."
  type        = string
  default     = "0.0.0.0/0"
}

variable "additional_tags" {
  description = "Extra tags merged into the provider default_tags."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type. x86_64 only (the AMI and Node.js download are x86_64). t3.small (2 GiB) builds most Next.js apps comfortably; t3.micro works for the demo app thanks to the swap file but builds slowly."
  type        = string
  default     = "t3.small"

  validation {
    condition     = can(regex("^t3a?\\.(micro|small|medium)$", var.instance_type))
    error_message = "instance_type must be one of t3/t3a micro, small or medium to keep costs low."
  }
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB (gp3). node_modules + .next for larger apps can exceed the 8 GiB AMI default."
  type        = number
  default     = 20
}

variable "node_version" {
  description = "Node.js version downloaded from nodejs.org at boot."
  type        = string
  default     = "22.11.0"
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = contains(["db.t4g.micro", "db.t3.micro", "db.t4g.small", "db.t3.small"], var.db_instance_class)
    error_message = "db_instance_class must be a micro or small burstable class to keep costs low."
  }
}

variable "db_engine_version" {
  description = "PostgreSQL major version. RDS picks the current default minor version."
  type        = string
  default     = "16"
}

variable "db_allocated_storage_gb" {
  description = "Allocated RDS storage in GiB (gp3). 20 is the minimum."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username. The password is generated and stored in SSM Parameter Store, never passed as an input."
  type        = string
  default     = "appuser"
}

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

variable "app_repo_url" {
  description = "HTTPS git URL of a Next.js app to deploy. Empty deploys the built-in demo app (demo-app/), which proves EC2 -> RDS connectivity."
  type        = string
  default     = ""
}

variable "app_git_ref" {
  description = "Branch or tag to check out from app_repo_url (passed to 'git clone --branch')."
  type        = string
  default     = "main"
}

variable "app_subdir" {
  description = "Subdirectory of the repo containing the Next.js app (for monorepos). Empty means the repo root."
  type        = string
  default     = ""
}

variable "app_install_command" {
  description = "Dependency install command. Empty auto-detects from the lockfile (pnpm / yarn / npm ci / npm install)."
  type        = string
  default     = ""
}

variable "app_build_command" {
  description = "Build command. Empty runs '<package-manager> run build'."
  type        = string
  default     = ""
}

variable "app_migrate_command" {
  description = "Optional command run after the build and before first start, e.g. 'npx prisma migrate deploy'. Has DATABASE_URL in its environment."
  type        = string
  default     = ""
}

variable "app_start_command" {
  description = "Start command. Empty runs '<package-manager> run start' ('next start' honours PORT)."
  type        = string
  default     = ""
}

variable "app_port" {
  description = "Port the app listens on and the security group opens. 80 is bound via CAP_NET_BIND_SERVICE, so no reverse proxy is needed."
  type        = number
  default     = 80
}

variable "app_extra_env" {
  description = "Extra environment variables for the app (build and runtime), e.g. auth secrets a chosen open-source project needs. From Torque pass JSON: '{\"KEY\":\"value\"}'."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

variable "wait_for_app" {
  description = "Block the apply until the app answers HTTP 2xx/3xx on health_check_path, so the Torque environment only turns Active once the full stack works. Requires the Torque agent to reach the instance (see allowed_cidr)."
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Path polled by the health check. Empty uses /api/health for the demo app (which also round-trips to RDS) and / for a custom repo."
  type        = string
  default     = ""
}

variable "health_check_timeout_minutes" {
  description = "How long to keep polling before failing the deployment. First boot installs Node, dependencies and runs 'next build'."
  type        = number
  default     = 20
}
