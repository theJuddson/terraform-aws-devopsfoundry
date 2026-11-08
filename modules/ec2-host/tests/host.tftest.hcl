# The instance, its network and IAM, the data volume that outlives it and the
# snapshot schedule, by default and with each input changed. Plans only,
# against a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-mock", availability_zone = "us-east-1a" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-fromssm", value = "ami-fromssm" }
  }
  # Known at plan so the instance's security group list can be checked.
  mock_resource "aws_security_group" {
    override_during = plan
    defaults        = { id = "sg-host" }
  }
}

variables {
  name      = "demo"
  subnet_id = "subnet-a"
}

run "defaults" {
  command = plan

  assert {
    condition     = length(data.aws_ssm_parameter.ami) == 1 && data.aws_ssm_parameter.ami[0].name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    error_message = "Without ami_id the AMI must come from the al2023 arm64 SSM parameter."
  }
  assert {
    condition     = aws_instance.this.ami == "ami-fromssm"
    error_message = "Without ami_id the instance must use the AMI the SSM parameter holds."
  }
  assert {
    condition     = aws_instance.this.instance_type == "t4g.small" && aws_instance.this.subnet_id == "subnet-a"
    error_message = "The instance must default to t4g.small in subnet_id."
  }
  assert {
    condition     = aws_instance.this.associate_public_ip_address == false && aws_instance.this.monitoring == false
    error_message = "No public IP and no billed detailed monitoring by default."
  }
  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required" && aws_instance.this.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "IMDSv2 must be required with a hop limit of 1, out of containers' reach."
  }
  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted && aws_instance.this.root_block_device[0].volume_size == 20 && aws_instance.this.root_block_device[0].volume_type == "gp3"
    error_message = "The root volume must be an encrypted 20 GiB gp3 volume."
  }
  assert {
    condition     = aws_instance.this.vpc_security_group_ids == toset(["sg-host"])
    error_message = "By default the instance has only its own security group."
  }
  assert {
    condition     = aws_instance.this.tags["Name"] == "demo" && aws_instance.this.iam_instance_profile == "demo-host"
    error_message = "The instance must be named var.name and use the module's instance profile."
  }
  assert {
    condition     = aws_security_group.this.name == "demo-host" && aws_security_group.this.vpc_id == "vpc-mock"
    error_message = "The security group must be named after var.name and live in the subnet's VPC."
  }
  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.this)) == toset(["0.0.0.0/0"]) && aws_vpc_security_group_egress_rule.this["0.0.0.0/0"].ip_protocol == "-1"
    error_message = "By default the host may reach anywhere, on any protocol."
  }
  assert {
    condition     = aws_iam_role.this.name == "demo-host" && aws_iam_role_policy_attachment.ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The instance role must carry the SSM core policy, or Session Manager cannot reach the host."
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.extra) == 0 && length(aws_iam_role_policy.extra) == 0
    error_message = "No extra policies by default."
  }
  assert {
    condition     = aws_ebs_volume.data.availability_zone == "us-east-1a" && aws_ebs_volume.data.size == 50 && aws_ebs_volume.data.iops == 3000 && aws_ebs_volume.data.throughput == 125
    error_message = "The data volume must be 50 GiB, 3000 IOPS, 125 MiB/s, in the subnet's zone."
  }
  assert {
    condition     = aws_ebs_volume.data.encrypted && aws_ebs_volume.data.final_snapshot && aws_ebs_volume.data.type == "gp3"
    error_message = "The data volume must be encrypted gp3 and snapshotted on deletion by default."
  }
  assert {
    condition     = aws_ebs_volume.data.tags["dlm-snapshot"] == "demo" && aws_ebs_volume.data.tags["Name"] == "demo-data"
    error_message = "The data volume must carry the tag the snapshot policy targets."
  }
  assert {
    condition     = aws_volume_attachment.data.device_name == "/dev/sdf" && aws_volume_attachment.data.stop_instance_before_detaching
    error_message = "The data volume must attach at /dev/sdf and detach only from a stopped instance."
  }
  assert {
    condition     = aws_dlm_lifecycle_policy.data.policy_details[0].target_tags == tomap({ "dlm-snapshot" = "demo" })
    error_message = "The snapshot policy must target this host's data volume tag."
  }
  assert {
    condition     = aws_dlm_lifecycle_policy.data.policy_details[0].schedule[0].create_rule[0].interval == 24 && aws_dlm_lifecycle_policy.data.policy_details[0].schedule[0].create_rule[0].times == tolist(["03:00"]) && aws_dlm_lifecycle_policy.data.policy_details[0].schedule[0].retain_rule[0].count == 14
    error_message = "Snapshots must be daily from 03:00 UTC, keeping 14."
  }
  assert {
    condition     = aws_iam_role.dlm.name == "demo-dlm" && aws_iam_role_policy_attachment.dlm.policy_arn == "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
    error_message = "The snapshot policy needs its own role with the DLM service policy."
  }
}

run "ami_id_skips_ssm_lookup" {
  command = plan

  variables {
    ami_id = "ami-pinned"
  }

  assert {
    condition     = length(data.aws_ssm_parameter.ami) == 0
    error_message = "With ami_id set, the SSM parameter must not be read."
  }
  assert {
    condition     = aws_instance.this.ami == "ami-pinned"
    error_message = "With ami_id set, the instance must use that AMI."
  }
}

run "custom_settings_reach_their_resources" {
  command = plan

  variables {
    ami_ssm_parameter           = "/aws/service/custom"
    instance_type               = "t4g.large"
    associate_public_ip_address = true
    detailed_monitoring         = true
    metadata_hop_limit          = 2
    extra_security_group_ids    = ["sg-db"]
    egress_cidr_blocks          = ["10.0.0.0/16", "192.168.0.0/24"]
    user_data                   = "#!/bin/sh\necho hi"
    user_data_replace_on_change = false
    root_volume_size_gib        = 30
    data_volume_size_gib        = 100
    data_volume_iops            = 4000
    data_volume_throughput      = 250
    data_volume_final_snapshot  = false
    data_device_name            = "/dev/sdg"
    kms_key_arn                 = "arn:aws:kms:us-east-1:111111111111:key/mock"
  }

  assert {
    condition     = data.aws_ssm_parameter.ami[0].name == "/aws/service/custom"
    error_message = "ami_ssm_parameter must choose the parameter read."
  }
  assert {
    condition     = aws_instance.this.instance_type == "t4g.large" && aws_instance.this.associate_public_ip_address && aws_instance.this.monitoring
    error_message = "instance_type, associate_public_ip_address and detailed_monitoring must reach the instance."
  }
  assert {
    condition     = aws_instance.this.metadata_options[0].http_put_response_hop_limit == 2
    error_message = "metadata_hop_limit must reach the instance."
  }
  assert {
    condition     = aws_instance.this.vpc_security_group_ids == toset(["sg-host", "sg-db"])
    error_message = "Extra security groups must be added to the module's own."
  }
  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.this)) == toset(["10.0.0.0/16", "192.168.0.0/24"]) && aws_vpc_security_group_egress_rule.this["10.0.0.0/16"].cidr_ipv4 == "10.0.0.0/16"
    error_message = "Egress must be limited to egress_cidr_blocks."
  }
  assert {
    condition     = aws_instance.this.user_data_replace_on_change == false
    error_message = "user_data_replace_on_change must reach the instance."
  }
  assert {
    condition     = aws_instance.this.root_block_device[0].volume_size == 30 && aws_instance.this.root_block_device[0].kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/mock"
    error_message = "Root volume size and key must follow the inputs."
  }
  assert {
    condition     = aws_ebs_volume.data.size == 100 && aws_ebs_volume.data.iops == 4000 && aws_ebs_volume.data.throughput == 250 && aws_ebs_volume.data.final_snapshot == false
    error_message = "Data volume size, IOPS, throughput and final snapshot must follow the inputs."
  }
  assert {
    condition     = aws_ebs_volume.data.kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/mock"
    error_message = "kms_key_arn must encrypt the data volume."
  }
  assert {
    condition     = aws_volume_attachment.data.device_name == "/dev/sdg"
    error_message = "data_device_name must reach the attachment."
  }
}

run "extra_policies_attach_to_instance_role" {
  command = plan

  variables {
    managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    inline_policy_jsons = { "read-secrets" = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  assert {
    condition     = keys(aws_iam_role_policy_attachment.extra) == ["arn:aws:iam::aws:policy/ReadOnlyAccess"] && aws_iam_role_policy_attachment.extra["arn:aws:iam::aws:policy/ReadOnlyAccess"].role == "demo-host"
    error_message = "managed_policy_arns must be attached to the instance role."
  }
  assert {
    condition     = keys(aws_iam_role_policy.extra) == ["read-secrets"] && aws_iam_role_policy.extra["read-secrets"].name == "read-secrets"
    error_message = "inline_policy_jsons must become inline policies named by their keys."
  }
}

run "snapshot_schedule_follows_inputs" {
  command = plan

  variables {
    snapshot_interval_hours = 12
    snapshot_time_utc       = "01:30"
    snapshot_retain_count   = 7
  }

  assert {
    condition     = aws_dlm_lifecycle_policy.data.policy_details[0].schedule[0].create_rule[0].interval == 12 && aws_dlm_lifecycle_policy.data.policy_details[0].schedule[0].create_rule[0].times == tolist(["01:30"])
    error_message = "Snapshot interval and start time must follow the inputs."
  }
  assert {
    condition     = aws_dlm_lifecycle_policy.data.policy_details[0].schedule[0].retain_rule[0].count == 7
    error_message = "snapshot_retain_count must set how many snapshots are kept."
  }
}
