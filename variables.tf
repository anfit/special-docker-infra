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

variable "public_base_url" {
  type        = string
  description = "The final public URL, e.g. https://special.corp.example (scheme + host, no path). The DNS name, certificate and load balancer are the edge team's; agree the name with them early because OAuth tokens, MCP bindings and share links derive from it."

  validation {
    condition     = can(regex("^https?://[A-Za-z0-9.-]+(:[0-9]+)?$", var.public_base_url))
    error_message = "public_base_url must look like https://host (no path, no trailing slash)."
  }
}

variable "insecure_http" {
  type        = bool
  default     = true
  description = "Allow plain HTTP and non-secure cookies. True until the edge team's TLS-terminating load balancer is attached (reach the app through an SSM port-forward meanwhile); set false afterwards so the application insists on HTTPS."
}

variable "trusted_proxy_hops" {
  type        = number
  default     = 1
  description = "Trusted proxies in front of the app that append to X-Forwarded-For (a single ALB = 1)."
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

variable "ingress_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups (typically the edge team's load balancer) allowed to reach TCP 80. Default: none, i.e. the host is closed and reachable only through SSM."
}

variable "ingress_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDR ranges allowed to reach TCP 80 (alternative to ingress_security_group_ids)."
}

variable "target_group_arns" {
  type        = list(string)
  default     = []
  description = "Target groups created by the edge team that the instance should be registered with (port 80). Leave empty if they register it themselves."
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
