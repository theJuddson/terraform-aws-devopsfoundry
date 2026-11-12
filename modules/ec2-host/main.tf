# One EC2 instance reached through SSM Session Manager (no SSH, no inbound
# ports), with its data on a separate EBS volume that outlives the instance,
# and a Data Lifecycle Manager policy that snapshots that volume on a schedule.

data "aws_partition" "current" {}

data "aws_subnet" "this" {
  id = var.subnet_id
}

data "aws_ssm_parameter" "ami" {
  count = var.ami_id == null ? 1 : 0
  name  = var.ami_ssm_parameter
}

locals {
  partition    = data.aws_partition.current.partition
  ami_id       = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.ami[0].insecure_value
  snapshot_tag = { "dlm-snapshot" = var.name }
}

# ── Network ───────────────────────────────────────────
resource "aws_security_group" "this" {
  #checkov:skip=CKV_AWS_382:The host reaches package mirrors and APIs on arbitrary hosts; narrow egress_cidr_blocks to restrict
  name        = "${var.name}-host"
  description = "No inbound; outbound to egress_cidr_blocks"
  vpc_id      = data.aws_subnet.this.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-host" })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each          = toset(var.egress_cidr_blocks)
  security_group_id = aws_security_group.this.id
  description       = "Outbound to ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "-1"
}

# ── IAM ───────────────────────────────────────────────
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-host"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each   = toset(var.managed_policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "extra" {
  for_each = var.inline_policy_jsons
  name     = each.key
  role     = aws_iam_role.this.id
  policy   = each.value
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-host"
  role = aws_iam_role.this.name
  tags = var.tags
}

# ── Instance ──────────────────────────────────────────
resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_88:Public IP is off by default; callers turn it on for outbound traffic without a NAT gateway, inbound stays closed
  #checkov:skip=CKV_AWS_126:Detailed monitoring is billed; opt in with detailed_monitoring = true
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = concat([aws_security_group.this.id], var.extra_security_group_ids)
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = var.associate_public_ip_address
  ebs_optimized               = true
  monitoring                  = var.detailed_monitoring
  user_data                   = var.user_data
  user_data_replace_on_change = var.user_data_replace_on_change

  # IMDSv2 only. A hop limit of 1 keeps the metadata service out of reach of
  # containers on bridge networks.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.metadata_hop_limit
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gib
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
  }

  tags        = merge(var.tags, { Name = var.name })
  volume_tags = merge(var.tags, { Name = "${var.name}-root" })

  # A newer AMI from the SSM parameter would otherwise replace the instance on
  # the next apply. Roll forward on purpose with `terraform apply -replace`.
  # volume_tags tags the root volume at launch only. After that the provider reads
  # it back from every attached volume, including the data volume, so without this
  # each apply would strip the data volume's dlm-snapshot tag and silently stop
  # its snapshots.
  lifecycle {
    ignore_changes = [ami, volume_tags]
  }
}

# ── Data volume ───────────────────────────────────────
# Its own resource, so replacing the instance detaches and re-attaches it
# instead of deleting it.
resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.this.availability_zone
  type              = "gp3"
  size              = var.data_volume_size_gib
  iops              = var.data_volume_iops
  throughput        = var.data_volume_throughput
  encrypted         = true
  kms_key_id        = var.kms_key_arn
  final_snapshot    = var.data_volume_final_snapshot
  tags              = merge(var.tags, local.snapshot_tag, { Name = "${var.name}-data" })
}

resource "aws_volume_attachment" "data" {
  device_name                    = var.data_device_name
  volume_id                      = aws_ebs_volume.data.id
  instance_id                    = aws_instance.this.id
  stop_instance_before_detaching = true
}

# ── Snapshots ─────────────────────────────────────────
data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name               = "${var.name}-dlm"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "data" {
  description        = "Snapshots of ${var.name}-data"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = local.snapshot_tag

    schedule {
      name      = "every ${var.snapshot_interval_hours}h keep ${var.snapshot_retain_count}"
      copy_tags = true

      create_rule {
        interval      = var.snapshot_interval_hours
        interval_unit = "HOURS"
        times         = [var.snapshot_time_utc]
      }

      retain_rule {
        count = var.snapshot_retain_count
      }

      tags_to_add = { "snapshot-of" = "${var.name}-data" }
    }
  }

  tags = var.tags
}
