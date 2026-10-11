output "instance_id" {
  value = module.host.instance_id
}

output "private_ip" {
  description = "Target address for the edge team's load balancer (HTTP port 80, health check /health)."
  value       = module.host.private_ip
}

output "security_group_id" {
  description = "Instance security group: the edge team's load balancer security group must be allowed on TCP 80 (or pass ingress_security_group_ids)."
  value       = module.host.security_group_id
}

output "edge_integration" {
  description = "Everything to put in the request to the team that owns the load balancer; see docs/EDGE_INTEGRATION.md."
  value = {
    public_base_url   = var.public_base_url
    instance_id       = module.host.instance_id
    private_ip        = module.host.private_ip
    vpc_id            = module.host.vpc_id
    security_group_id = module.host.security_group_id
    target_protocol   = "HTTP"
    target_port       = 80
    health_check      = "GET /health -> 200"
    trusted_proxies   = var.trusted_proxy_hops
  }
}

output "table_name" {
  value = module.data.table_name
}

output "log_group_name" {
  value = module.data.log_group_name
}

output "port_forward_command" {
  description = "Reach the app on http://localhost:8080 through SSM, with no network exposure (pre-TLS, setup, administration)."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${module.host.instance_id} --document-name AWS-StartPortForwardingSession --parameters portNumber=80,localPortNumber=8080"
}

output "connect_command" {
  description = "Shell on the host through SSM Session Manager (no SSH)."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${module.host.instance_id}"
}

output "deploy_command" {
  description = "Deploy a release from your workstation or CI; replace <tag> with a version tag or sha256:<digest>."
  value       = "aws ssm send-command --region ${var.aws_region} --instance-ids ${module.host.instance_id} --document-name AWS-RunShellScript --parameters 'commands=[\"special-deploy <tag>\"]'"
}
