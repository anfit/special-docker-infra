output "public_ip" {
  description = "Create a DNS A record for domain_name pointing here."
  value       = module.host.public_ip
}

output "url" {
  value = "https://${var.domain_name}"
}

output "instance_id" {
  value = module.host.instance_id
}

output "table_name" {
  value = module.data.table_name
}

output "log_group_name" {
  value = module.data.log_group_name
}

output "connect_command" {
  description = "Shell on the host through SSM Session Manager (no SSH)."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${module.host.instance_id}"
}

output "deploy_command" {
  description = "Deploy a release from your workstation or CI; replace <tag> with a version tag or sha256:<digest>."
  value       = "aws ssm send-command --region ${var.aws_region} --instance-ids ${module.host.instance_id} --document-name AWS-RunShellScript --parameters 'commands=[\"special-deploy <tag>\"]'"
}
