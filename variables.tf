# ---- account / ecosystem (deployment specific: set these in terraform.tfvars, never commit it) ----

variable "aws_region" {
  type        = string
  description = "Region for every resource."
}

variable "aws_profile" {
  type        = string
  default     = null
  description = "AWS CLI/SSO profile to use. Null = default credential chain (environment, CI role, ...)."
}

variable "allowed_account_ids" {
  type        = list(string)
  default     = []
  description = "If non-empty, the provider refuses to run against any other account."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every taggable resource (provider default_tags). Your ecosystem's tagging strategy goes here; see templates/tags.auto.tfvars.example."
}

variable "required_tag_keys" {
  type        = list(string)
  default     = []
  description = "Tag keys that must be present in var.tags (organisation policy). Empty = no policy."
}

# ---- naming ----

variable "name" {
  type        = string
  default     = "special"
  description = "Base name for resources. Use a distinct name per environment sharing one account (e.g. special-dev)."
}

variable "table_name" {
  type        = string
  default     = null
  description = "DynamoDB table name. Defaults to var.name."
}

variable "log_group_name" {
  type        = string
  default     = null
  description = "CloudWatch log group. Defaults to /<name>/app."
}

# ---- the application ----

variable "domain_name" {
  type        = string
  description = "Public host name; create an A record pointing at the public_ip output. Caddy obtains a certificate for it."
}

variable "image_repository" {
  type        = string
  description = "Image repository WITHOUT tag, wherever special-docker releases are published, e.g. ghcr.io/<owner>/special-docker or <acct>.dkr.ecr.<region>.amazonaws.com/special. See docs/REGISTRY_OPTIONS.md. The tag or digest to run is chosen at deploy time, not here."
}

variable "registry_auth" {
  type        = string
  default     = "none"
  description = "How the host authenticates to the registry: none (public image), ssm (username/token read from SSM Parameter Store: <ssm_prefix>/registry-user and /registry-token), ecr (this account's ECR)."

  validation {
    condition     = contains(["none", "ssm", "ecr"], var.registry_auth)
    error_message = "registry_auth must be none, ssm or ecr."
  }
}

variable "ssm_prefix" {
  type        = string
  default     = "/special/prod"
  description = "SSM Parameter Store prefix. You create <prefix>/app-key (SecureString) and, for registry_auth = ssm, <prefix>/registry-user and <prefix>/registry-token by hand, so no secret ever enters Terraform state."

  validation {
    condition     = can(regex("^/[A-Za-z0-9_./-]+$", var.ssm_prefix))
    error_message = "ssm_prefix must start with / and contain only letters, digits and _ . / -"
  }
}

# ---- data ----

variable "enable_pitr" {
  type        = bool
  default     = true
  description = "DynamoDB point-in-time recovery."
}

variable "table_deletion_protection" {
  type        = bool
  default     = true
  description = "DynamoDB deletion protection. Turn off only to tear an environment down."
}

variable "log_retention_days" {
  type    = number
  default = 30
}

# ---- host ----

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "Must be x86_64 unless your published image is multi-arch."
}

variable "root_volume_gb" {
  type    = number
  default = 20
}

variable "ami_ssm_parameter" {
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  description = "SSM public parameter resolving to the AMI. The instance ignores later AMI changes; rebuild deliberately."
}

variable "compose_version" {
  type        = string
  default     = "v2.29.1"
  description = "Docker Compose release installed as a CLI plugin."
}

variable "http_ingress_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Who may reach ports 80/443. Narrow it for an internal-only deployment (Let's Encrypt HTTP-01 still needs port 80 open to the internet unless you bring your own certificate)."
}

variable "create_network" {
  type        = bool
  default     = true
  description = "Create a small dedicated VPC and public subnet. Set false to place the host in existing network (then vpc_id and subnet_id are required)."
}

variable "vpc_id" {
  type    = string
  default = null
}

variable "subnet_id" {
  type        = string
  default     = null
  description = "Public subnet (auto-assign public IPv4 not required; an Elastic IP is attached)."
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.42.1.0/24"
}
