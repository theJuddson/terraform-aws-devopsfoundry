output "url" {
  description = "The collector's URL: the dashboard for people, and the collector address for agents."
  value       = "https://${var.hostname}"
}

output "public_ip" {
  description = "The fixed public address. Point `hostname` at it when `zone_id` is null."
  value       = aws_eip.this.public_ip
}

output "instance_id" {
  description = "The collector's instance."
  value       = module.host.instance_id
}

output "security_group_id" {
  description = "The collector's security group (443 in, from `ingress_cidr_blocks`)."
  value       = module.host.security_group_id
}

output "role_name" {
  description = "The instance role, to attach more policies to."
  value       = module.host.role_name
}

output "data_volume_id" {
  description = "The data volume that outlives the instance."
  value       = module.host.data_volume_id
}

output "ssm_session_command" {
  description = "Opens a shell on the collector, for `watchtower admin` commands."
  value       = module.host.ssm_session_command
}

output "first_admin_command" {
  description = "Run in an SSM session on the collector to print a one-time sign-in link for the first admin."
  value       = "sudo -u watchtower /usr/local/bin/watchtower admin --data /var/lib/watchtower/collector --origin https://${var.hostname} invite <email> admin"
}

output "collector_flags" {
  description = "The flags the collector runs with (no secrets: mail goes through the instance role)."
  value       = local.flags
}
