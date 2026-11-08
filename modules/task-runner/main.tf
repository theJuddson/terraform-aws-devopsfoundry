# One-off tasks on ECS Fargate: a cluster with FARGATE and FARGATE_SPOT
# capacity, task definitions meant to be started with RunTask (no service, no
# load balancer), task and execution roles, a log group, an egress-only
# security group, and an IAM policy document for the controller that starts
# and stops the tasks.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
# The region attribute is "region" on aws provider 6.x and "name" on 5.x (deprecated
# in 6.x). Reading it by key works on both without a deprecation warning.
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = lookup(data.aws_region.current, "region", lookup(data.aws_region.current, "name", null))
  ecs_arn    = "arn:${local.partition}:ecs:${local.region}:${local.account_id}"

  efs_file_system_ids = distinct([for v in var.efs_volumes : v.file_system_id])

  # Each task definition falls back to the module-wide settings.
  task_definitions = {
    for k, t in var.task_definitions : k => {
      family      = "${var.name}-${k}"
      image       = t.image
      command     = t.command
      cpu         = coalesce(t.cpu, var.cpu)
      memory      = coalesce(t.memory, var.memory)
      environment = merge(var.environment, t.environment)
      secrets     = merge(var.secrets, t.secrets)
    }
  }

  # Decided from the keys, which are known at plan time, so `count` never
  # depends on secret ARNs that only exist after apply.
  has_secrets = length(flatten([for t in local.task_definitions : keys(t.secrets)])) > 0

  # valueFrom is a Secrets Manager ARN (maybe with a ":<json-key>:<stage>:<version>"
  # selector) or an SSM parameter ARN. Reduce each to the ARN IAM needs.
  all_secret_values = distinct(flatten([for t in local.task_definitions : values(t.secrets)]))
  sm_secret_arns    = distinct([for v in local.all_secret_values : regex("^(arn:[^:]+:secretsmanager:[^:]+:[^:]+:secret:[^:]+)", v)[0] if can(regex(":secretsmanager:", v))])
  ssm_param_arns    = [for v in local.all_secret_values : v if can(regex(":ssm:", v))]
}

# ── Cluster ───────────────────────────────────────────
resource "aws_ecs_cluster" "this" {
  #checkov:skip=CKV_AWS_65:Container Insights is billed per metric; opt in with container_insights = true
  name = var.name
  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }
  tags = merge(var.tags, { Name = var.name })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.key
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}

# ── Logs ──────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_338:Retention is the caller's choice (log_retention_days); one-off task logs rarely need a year
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn
  tags              = merge(var.tags, { Name = "${var.name}-logs" })
}

# ── Network ───────────────────────────────────────────
# No ingress rules: nothing can connect to a task. Egress goes wherever
# egress_cidr_blocks allow, which by default is anywhere.
resource "aws_security_group" "this" {
  #checkov:skip=CKV2_AWS_5:Attached at run time, by the controller's RunTask call
  #checkov:skip=CKV_AWS_382:Tasks reach arbitrary internet hosts by design; narrow egress_cidr_blocks to restrict
  name        = "${var.name}-tasks"
  description = "Egress-only security group for ${var.name} tasks"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-tasks" })
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
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  count = local.has_secrets ? 1 : 0
  dynamic "statement" {
    for_each = length(local.sm_secret_arns) > 0 ? [1] : []
    content {
      actions   = ["secretsmanager:GetSecretValue"]
      resources = local.sm_secret_arns
    }
  }
  dynamic "statement" {
    for_each = length(local.ssm_param_arns) > 0 ? [1] : []
    content {
      actions   = ["ssm:GetParameters"]
      resources = local.ssm_param_arns
    }
  }
  dynamic "statement" {
    for_each = length(var.secrets_kms_key_arns) > 0 ? [1] : []
    content {
      actions   = ["kms:Decrypt"]
      resources = var.secrets_kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count  = local.has_secrets ? 1 : 0
  name   = "read-task-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# Mounting with IAM authorization needs ClientMount (and ClientWrite unless
# every volume using that file system is read-only).
data "aws_iam_policy_document" "task_efs" {
  count = length(local.efs_file_system_ids) > 0 ? 1 : 0
  statement {
    actions   = ["elasticfilesystem:ClientMount"]
    resources = [for id in local.efs_file_system_ids : "arn:${local.partition}:elasticfilesystem:${local.region}:${local.account_id}:file-system/${id}"]
  }
  dynamic "statement" {
    for_each = length([for v in var.efs_volumes : v if !v.read_only]) > 0 ? [1] : []
    content {
      actions   = ["elasticfilesystem:ClientWrite"]
      resources = [for id in distinct([for v in var.efs_volumes : v.file_system_id if !v.read_only]) : "arn:${local.partition}:elasticfilesystem:${local.region}:${local.account_id}:file-system/${id}"]
    }
  }
}

resource "aws_iam_role_policy" "task_efs" {
  count  = length(local.efs_file_system_ids) > 0 ? 1 : 0
  name   = "mount-efs"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_efs[0].json
}

resource "aws_iam_role_policy" "task_extra" {
  for_each = var.task_role_policy_jsons
  name     = each.key
  role     = aws_iam_role.task.id
  policy   = each.value
}

# ── Task definitions ──────────────────────────────────
resource "aws_ecs_task_definition" "this" {
  for_each = local.task_definitions

  family                   = each.value.family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  ephemeral_storage {
    size_in_gib = var.ephemeral_storage_gib
  }

  dynamic "volume" {
    for_each = var.efs_volumes
    content {
      name = volume.value.name
      efs_volume_configuration {
        file_system_id     = volume.value.file_system_id
        root_directory     = volume.value.access_point_id == null ? volume.value.root_directory : null
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = "ENABLED"
        }
      }
    }
  }

  container_definitions = jsonencode([{
    name                   = var.container_name
    image                  = each.value.image
    essential              = true
    command                = each.value.command
    readonlyRootFilesystem = var.readonly_root_filesystem
    environment            = [for k, v in each.value.environment : { name = k, value = v }]
    secrets                = [for k, v in each.value.secrets : { name = k, valueFrom = v }]
    mountPoints = [for v in var.efs_volumes : {
      sourceVolume  = v.name
      containerPath = v.container_path
      readOnly      = v.read_only
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = local.region
        awslogs-stream-prefix = each.key
      }
    }
  }])

  tags = merge(var.tags, { Name = each.value.family })
}

# ── Controller policy ─────────────────────────────────
# For whatever starts the tasks (an API, a queue worker): run, stop, describe
# and tag tasks in this cluster only, and pass exactly these two roles.
data "aws_iam_policy_document" "controller" {
  statement {
    sid       = "RunTaskDefinitionsInThisCluster"
    actions   = ["ecs:RunTask"]
    resources = [for t in local.task_definitions : "${local.ecs_arn}:task-definition/${t.family}:*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.this.arn]
    }
  }

  statement {
    sid       = "ManageTasksInThisCluster"
    actions   = ["ecs:StopTask", "ecs:DescribeTasks"]
    resources = ["${local.ecs_arn}:task/${aws_ecs_cluster.this.name}/*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.this.arn]
    }
  }

  # Tags passed to RunTask are authorized as ecs:TagResource on the new task.
  statement {
    sid       = "TagTasksInThisCluster"
    actions   = ["ecs:TagResource"]
    resources = ["${local.ecs_arn}:task/${aws_ecs_cluster.this.name}/*"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.task.arn, aws_iam_role.execution.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}
