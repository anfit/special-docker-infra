provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # Guard rail against applying to the wrong account. Empty list = no restriction.
  allowed_account_ids = length(var.allowed_account_ids) > 0 ? var.allowed_account_ids : null

  default_tags {
    tags = var.tags
  }
}

# Organisation tag policy hook: list the tag keys your ecosystem mandates in required_tag_keys and the
# plan fails early if var.tags does not provide them. Nothing is enforced by default.
resource "terraform_data" "tag_policy" {
  lifecycle {
    precondition {
      condition     = alltrue([for key in var.required_tag_keys : contains(keys(var.tags), key)])
      error_message = "var.tags is missing required tag keys: ${join(", ", [for key in var.required_tag_keys : key if !contains(keys(var.tags), key)])}."
    }
  }
}

module "data" {
  source = "./modules/data"

  name                = var.name
  table_name          = coalesce(var.table_name, var.name)
  log_group_name      = coalesce(var.log_group_name, "/${var.name}/app")
  log_retention_days  = var.log_retention_days
  enable_pitr         = var.enable_pitr
  deletion_protection = var.table_deletion_protection

  depends_on = [terraform_data.tag_policy]
}

module "host" {
  source = "./modules/host"

  name                = var.name
  domain_name         = var.domain_name
  image_repository    = var.image_repository
  registry_auth       = var.registry_auth
  ssm_prefix          = var.ssm_prefix
  instance_type       = var.instance_type
  root_volume_gb      = var.root_volume_gb
  ami_ssm_parameter   = var.ami_ssm_parameter
  http_ingress_cidrs  = var.http_ingress_cidrs
  create_network      = var.create_network
  vpc_id              = var.vpc_id
  subnet_id           = var.subnet_id
  vpc_cidr            = var.vpc_cidr
  subnet_cidr         = var.subnet_cidr
  table_name          = module.data.table_name
  table_arn           = module.data.table_arn
  log_group_name      = module.data.log_group_name
  log_group_arn       = module.data.log_group_arn
  compose_version     = var.compose_version
}
