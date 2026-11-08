# The file system, its network access and the two policies it renders: the
# file system policy (mount rules, root squash) and the run-time policy for an
# app role (tag-limited access points, optionally whole file systems). Plans
# only, against a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  # The run-time policy builds ARNs from these.
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1", region = "us-east-1" }
  }
  # The file system policy names the file system ARN; knowing it at plan lets
  # the policy be read, so its statements can be checked.
  mock_resource "aws_efs_file_system" {
    override_during = plan
    defaults = {
      arn = "arn:aws:elasticfilesystem:us-east-1:111111111111:file-system/fs-mock"
      id  = "fs-mock"
    }
  }
}

variables {
  name                      = "demo"
  vpc_id                    = "vpc-mock"
  subnet_ids                = ["subnet-a", "subnet-b"]
  source_security_group_ids = ["sg-app", "sg-worker"]
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_efs_file_system.this.creation_token == "demo" && aws_efs_file_system.this.encrypted && aws_efs_file_system.this.throughput_mode == "elastic"
    error_message = "The file system must be named after var.name, encrypted, and use elastic throughput by default."
  }
  assert {
    condition     = length(aws_efs_file_system.this.lifecycle_policy) == 2 && aws_efs_file_system.this.lifecycle_policy[0].transition_to_ia == "AFTER_30_DAYS" && aws_efs_file_system.this.lifecycle_policy[1].transition_to_primary_storage_class == "AFTER_1_ACCESS"
    error_message = "By default files move to Infrequent Access after 30 days and back on first access."
  }
  assert {
    condition     = aws_efs_file_system.this.tags["managed-by"] == "demo" && aws_efs_file_system.this.tags["Name"] == "demo"
    error_message = "The file system must carry the run-time tag, valued with the name by default."
  }
  assert {
    condition     = aws_efs_backup_policy.this.backup_policy[0].status == "ENABLED"
    error_message = "AWS Backup must be on."
  }
  assert {
    condition     = aws_security_group.this.name == "demo-efs" && aws_security_group.this.vpc_id == "vpc-mock"
    error_message = "The mount-target security group must be named after var.name and live in vpc_id."
  }
  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.nfs)) == toset(["sg-app", "sg-worker"])
    error_message = "Each source security group must get its own NFS rule."
  }
  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.nfs : r.ip_protocol == "tcp" && r.from_port == 2049 && r.to_port == 2049])
    error_message = "Ingress must be NFS (TCP 2049) only."
  }
  assert {
    condition     = toset(keys(aws_efs_mount_target.this)) == toset(["subnet-a", "subnet-b"]) && alltrue([for k, mt in aws_efs_mount_target.this : mt.subnet_id == k])
    error_message = "Each subnet must get one mount target."
  }
  assert {
    condition     = !contains(data.aws_iam_policy_document.file_system.statement[0].actions, "elasticfilesystem:ClientRootAccess")
    error_message = "Root access must be off by default, so clients' root is squashed."
  }
  assert {
    condition     = one(data.aws_iam_policy_document.file_system.statement[0].principals).identifiers == toset(["arn:aws:iam::111111111111:root"])
    error_message = "Without client_role_arns, any principal in this account may mount."
  }
  assert {
    condition     = data.aws_iam_policy_document.file_system.statement[1].effect == "Deny" && one(data.aws_iam_policy_document.file_system.statement[1].condition).variable == "aws:SecureTransport"
    error_message = "The file system policy must refuse clients not using TLS."
  }
  assert {
    condition     = output.runtime_tag == { key = "managed-by", value = "demo" }
    error_message = "The runtime_tag output must name the default tag key and the name as value."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.runtime.statement) == 5
    error_message = "By default the run-time policy must not allow creating file systems."
  }
  assert {
    condition     = data.aws_iam_policy_document.runtime.statement[0].resources == toset(["arn:aws:elasticfilesystem:us-east-1:111111111111:file-system/*"])
    error_message = "Access points may be created only on file systems in this account and region."
  }
  assert {
    condition = toset([for c in data.aws_iam_policy_document.runtime.statement[0].condition : "${c.variable}=${join(",", c.values)}"]) == toset([
      "aws:RequestTag/managed-by=demo",
      "aws:ResourceTag/managed-by=demo",
    ])
    error_message = "Access points must carry the tag and be made only on file systems carrying it."
  }
}

run "transition_to_ia_null_keeps_standard_storage" {
  command = plan

  variables {
    transition_to_ia = null
  }

  assert {
    condition     = length(aws_efs_file_system.this.lifecycle_policy) == 0
    error_message = "transition_to_ia = null must leave every file in Standard storage."
  }
}

run "root_access_and_named_clients" {
  command = plan

  variables {
    allow_root_access = true
    client_role_arns  = ["arn:aws:iam::111111111111:role/app"]
    throughput_mode   = "bursting"
    kms_key_arn       = "arn:aws:kms:us-east-1:111111111111:key/mock"
  }

  assert {
    condition     = contains(data.aws_iam_policy_document.file_system.statement[0].actions, "elasticfilesystem:ClientRootAccess")
    error_message = "allow_root_access must grant ClientRootAccess."
  }
  assert {
    condition     = one(data.aws_iam_policy_document.file_system.statement[0].principals).identifiers == toset(["arn:aws:iam::111111111111:role/app"])
    error_message = "client_role_arns must replace the account-wide principal."
  }
  assert {
    condition     = aws_efs_file_system.this.throughput_mode == "bursting" && aws_efs_file_system.this.kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/mock"
    error_message = "throughput_mode and kms_key_arn must reach the file system."
  }
}

run "runtime_create_file_system_with_custom_tag" {
  command = plan

  variables {
    runtime_tag_key                  = "owner"
    runtime_tag_value                = "team-a"
    runtime_allow_create_file_system = true
  }

  assert {
    condition     = aws_efs_file_system.this.tags["owner"] == "team-a" && output.runtime_tag == { key = "owner", value = "team-a" }
    error_message = "A custom run-time tag must be on the file system and in the runtime_tag output."
  }
  assert {
    condition = [for s in data.aws_iam_policy_document.runtime.statement : s.sid] == [
      "CreateTaggedAccessPoints",
      "TagOnCreate",
      "KeepOthersOwnershipTag",
      "ManageOwnAccessPoints",
      "Describe",
      "CreateTaggedFileSystems",
      "ManageOwnFileSystems",
      "MountTargetNetworkInterfaces",
      "MountTargetDescribe",
    ]
    error_message = "runtime_allow_create_file_system must add the file-system statements."
  }
  assert {
    condition = toset([for c in data.aws_iam_policy_document.runtime.statement[5].condition : "${c.variable}=${join(",", c.values)}"]) == toset([
      "aws:RequestTag/owner=team-a",
      "elasticfilesystem:Encrypted=true",
    ])
    error_message = "Run-time file systems must carry the custom tag and be encrypted."
  }
  assert {
    condition = toset([for c in data.aws_iam_policy_document.runtime.statement[2].condition : "${c.variable}=${join(",", c.values)}"]) == toset([
      "aws:TagKeys=owner",
      "aws:ResourceTag/owner=false",
      "aws:ResourceTag/owner=team-a",
    ])
    error_message = "The app must not move the custom ownership tag off others' resources."
  }
  assert {
    condition     = contains(data.aws_iam_policy_document.runtime.statement[7].resources, "arn:aws:ec2:us-east-1:111111111111:subnet/*")
    error_message = "Mount targets need network interfaces in this account and region."
  }
}
