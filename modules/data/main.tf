# Persistence for special-docker: one DynamoDB table with two GSIs, plus the log group.
# Keep the schema identical to special-docker/src/Storage/DynamoSchema.php (and docs/DYNAMODB.md there).

variable "name" {
  type = string
}

variable "table_name" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "log_retention_days" {
  type = number
}

variable "enable_pitr" {
  type = bool
}

variable "deletion_protection" {
  type = bool
}

locals {
  projected_attributes = [
    "etype", "id", "title", "description", "project_name", "status", "visibility", "revision",
    "created_by", "updated_by", "created_at", "updated_at", "deleted_at",
    "username", "role", "enabled", "version", "last_login_at",
    "user_id", "revoked_at", "consumed_at",
  ]
}

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  deletion_protection_enabled = var.deletion_protection

  dynamic "attribute" {
    for_each = ["pk", "sk", "gsi1pk", "gsi1sk", "gsi2pk", "gsi2sk"]
    content {
      name = attribute.value
      type = "S"
    }
  }

  dynamic "global_secondary_index" {
    for_each = ["gsi1", "gsi2"]
    content {
      name               = global_secondary_index.value
      hash_key           = "${global_secondary_index.value}pk"
      range_key          = "${global_secondary_index.value}sk"
      projection_type    = "INCLUDE"
      non_key_attributes = local.projected_attributes
    }
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.enable_pitr
  }

  tags = {
    Name = var.table_name
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name = var.log_group_name
  }
}

output "table_name" {
  value = aws_dynamodb_table.this.name
}

output "table_arn" {
  value = aws_dynamodb_table.this.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "log_group_arn" {
  value = aws_cloudwatch_log_group.app.arn
}
