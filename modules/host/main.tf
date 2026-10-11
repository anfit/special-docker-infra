# A single EC2 docker host for special-docker: optional dedicated network, security group,
# least-privilege instance role, Elastic IP, and a first-boot script that installs Docker and the
# `special-deploy` command. No SSH; administration is through SSM Session Manager.

variable "name" { type = string }
variable "domain_name" { type = string }
variable "image_repository" { type = string }
variable "registry_auth" { type = string }
variable "ssm_prefix" { type = string }
variable "instance_type" { type = string }
variable "root_volume_gb" { type = number }
variable "ami_ssm_parameter" { type = string }
variable "http_ingress_cidrs" { type = list(string) }
variable "create_network" { type = bool }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "vpc_cidr" { type = string }
variable "subnet_cidr" { type = string }
variable "table_name" { type = string }
variable "table_arn" { type = string }
variable "log_group_name" { type = string }
variable "log_group_arn" { type = string }
variable "compose_version" { type = string }

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  vpc_id    = var.create_network ? aws_vpc.this[0].id : var.vpc_id
  subnet_id = var.create_network ? aws_subnet.public[0].id : var.subnet_id

  # "ghcr.io/org/img" -> "ghcr.io"; Docker Hub style "org/img" -> "" (docker login's default server).
  first_segment  = split("/", var.image_repository)[0]
  registry_host  = can(regex("[.:]", local.first_segment)) || local.first_segment == "localhost" ? local.first_segment : ""
}

# ------------------------------------------------------------------ network (optional)

resource "aws_vpc" "this" {
  count                = var.create_network ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  count  = var.create_network ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  tags   = { Name = var.name }
}

resource "aws_subnet" "public" {
  count                   = var.create_network ? 1 : 0
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public" }
}

resource "aws_route_table" "public" {
  count  = var.create_network ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  tags   = { Name = "${var.name}-public" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }
}

resource "aws_route_table_association" "public" {
  count          = var.create_network ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "special-docker web traffic (80 for ACME and redirect, 443 for HTTPS)"
  vpc_id      = local.vpc_id
  tags        = { Name = var.name }

  ingress {
    description = "HTTP and ACME challenge"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.http_ingress_cidrs
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.http_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------ identity

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "runtime" {
  statement {
    sid = "TableAccess"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:ConditionCheckItem",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
    ]
    # The trailing * also covers tables restored from a backup under a derived name (<table>-restore).
    resources = [
      "arn:${local.partition}:dynamodb:${local.region}:${local.account_id}:table/${var.table_name}*",
      "arn:${local.partition}:dynamodb:${local.region}:${local.account_id}:table/${var.table_name}*/index/*",
    ]
  }

  statement {
    sid       = "ReadAppSecrets"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter${var.ssm_prefix}/*"]
  }

  statement {
    sid       = "ShipLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${var.log_group_arn}:*"]
  }
}

resource "aws_iam_role" "this" {
  name_prefix        = "${var.name}-host-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "runtime" {
  name   = "${var.name}-runtime"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.runtime.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  count      = var.registry_auth == "ecr" ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.this.name
}

# ------------------------------------------------------------------ compute

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  # IMDSv2 only. Hop limit 2 lets containers reach the instance role credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    domain_name      = var.domain_name
    region           = local.region
    table_name       = var.table_name
    image_repository = var.image_repository
    log_group_name   = var.log_group_name
    ssm_prefix       = var.ssm_prefix
    registry_auth    = var.registry_auth
    registry_host    = local.registry_host
    compose_version  = var.compose_version
  })

  tags = { Name = var.name }

  # The host is cattle: user data runs once and AMIs move on. Rebuild on purpose with
  #   terraform apply -replace='module.host.aws_instance.this'
  lifecycle {
    ignore_changes = [user_data, ami]
  }

  depends_on = [aws_route_table_association.public]
}

resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.this.id
  tags     = { Name = var.name }
}

output "public_ip" {
  value = aws_eip.this.public_ip
}

output "instance_id" {
  value = aws_instance.this.id
}
