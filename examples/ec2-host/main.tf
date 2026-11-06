# A Graviton host in a public subnet (outbound only, no NAT gateway), with a
# 200 GiB data volume snapshotted every 12 hours and kept for a week.
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "public_subnet_id" {
  type = string
}

module "host" {
  source                      = "../../modules/ec2-host"
  name                        = "example-worker"
  subnet_id                   = var.public_subnet_id
  instance_type               = "t4g.large"
  associate_public_ip_address = true
  data_volume_size_gib        = 200
  snapshot_interval_hours     = 12
  snapshot_retain_count       = 14

  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail
    dev=$(readlink -f /dev/sdf)
    blkid "$dev" || mkfs.xfs -L data "$dev"
    mkdir -p /data
    echo 'LABEL=data /data xfs defaults,nofail 0 2' >> /etc/fstab
    mount -a
  EOT
}

output "connect" {
  value = module.host.ssm_session_command
}
