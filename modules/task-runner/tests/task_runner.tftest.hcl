# The cluster, task definitions, roles and controller policy the task runner
# plans, how per-definition settings fall back to module-wide ones, and the
# checks on its inputs. Plans only, against a mocked provider: no AWS account
# is touched.

# Mocked providers return random strings for computed values. Give the
# account, partition and region realistic values so the ARNs the policies are
# built from can be checked, and a JSON policy the provider will accept.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
}

variables {
  name   = "jobs"
  vpc_id = "vpc-123"
  task_definitions = {
    report = { image = "example/report:1" }
  }
}

run "defaults_cluster_task_definition_and_no_optional_policies" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.this.name == "jobs" && one(aws_ecs_cluster.this.setting).value == "disabled"
    error_message = "The cluster must be named after var.name, with Container Insights off by default."
  }
  assert {
    condition     = aws_ecs_cluster_capacity_providers.this.capacity_providers == toset(["FARGATE", "FARGATE_SPOT"])
    error_message = "Both FARGATE and FARGATE_SPOT must be available to RunTask."
  }
  assert {
    condition = [for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : {
      p = s.capacity_provider, w = s.weight, b = s.base
    }] == [{ p = "FARGATE", w = 1, b = 0 }]
    error_message = "RunTask calls without a strategy must default to on-demand FARGATE."
  }
  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/ecs/jobs" && aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "Task logs must go to /ecs/<name> and be kept 30 days by default."
  }
  assert {
    condition     = aws_security_group.this.name == "jobs-tasks" && aws_security_group.this.vpc_id == "vpc-123"
    error_message = "The tasks' security group must be in the given VPC."
  }
  assert {
    condition     = keys(aws_vpc_security_group_egress_rule.this) == ["0.0.0.0/0"] && aws_vpc_security_group_egress_rule.this["0.0.0.0/0"].ip_protocol == "-1"
    error_message = "By default tasks may reach anywhere, on any protocol."
  }
  assert {
    condition     = aws_iam_role.execution.name == "jobs-exec" && aws_iam_role.task.name == "jobs-task"
    error_message = "The roles must be named <name>-exec and <name>-task."
  }
  assert {
    condition     = aws_iam_role_policy_attachment.execution.policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    error_message = "The execution role needs the managed policy to pull images and write logs."
  }
  assert {
    condition     = length(aws_iam_role_policy.execution_secrets) == 0 && length(aws_iam_role_policy.task_efs) == 0 && length(aws_iam_role_policy.task_extra) == 0
    error_message = "Without secrets, EFS volumes or extra policies, no inline policies must be planned."
  }
  assert {
    condition     = keys(aws_ecs_task_definition.this) == ["report"] && output.task_definition_families == { report = "jobs-report" }
    error_message = "Each task definition must be registered as family <name>-<key>."
  }
  assert {
    condition = (
      aws_ecs_task_definition.this["report"].cpu == "1024" && aws_ecs_task_definition.this["report"].memory == "2048" &&
      aws_ecs_task_definition.this["report"].requires_compatibilities == toset(["FARGATE"]) && aws_ecs_task_definition.this["report"].network_mode == "awsvpc"
    )
    error_message = "By default a task definition must be a 1 vCPU / 2 GiB Fargate task in awsvpc mode."
  }
  assert {
    condition = (
      one(aws_ecs_task_definition.this["report"].runtime_platform).cpu_architecture == "ARM64" &&
      one(aws_ecs_task_definition.this["report"].ephemeral_storage).size_in_gib == 50 &&
      length(aws_ecs_task_definition.this["report"].volume) == 0
    )
    error_message = "By default tasks must run on ARM64 with 50 GiB of ephemeral storage and no volumes."
  }
  assert {
    condition     = output.run_task_network_configuration.awsvpcConfiguration.assignPublicIp == "DISABLED" && length(output.run_task_network_configuration.awsvpcConfiguration.subnets) == 0
    error_message = "By default RunTask must not assign a public IP."
  }
  assert {
    condition     = output.container_name == "task"
    error_message = "The container must be called task by default, the name RunTask overrides refer to."
  }
}

run "container_definition_wires_image_logs_and_settings" {
  command = plan

  variables {
    container_name           = "worker"
    readonly_root_filesystem = true
    task_definitions = {
      report = { image = "example/report:1", command = ["run", "--all"] }
    }
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this["report"].container_definitions)[0].name == "worker" && (
      jsondecode(aws_ecs_task_definition.this["report"].container_definitions)[0].image == "example/report:1"
    )
    error_message = "The container must take container_name and the definition's image."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["report"].container_definitions)[0].command == ["run", "--all"]
    error_message = "The container must run the definition's command."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["report"].container_definitions)[0].readonlyRootFilesystem == true
    error_message = "readonly_root_filesystem must reach the container."
  }
  assert {
    condition = jsondecode(aws_ecs_task_definition.this["report"].container_definitions)[0].logConfiguration == {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/jobs"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "report"
      }
    }
    error_message = "The container must log to the module's log group, in this region, under a prefix per definition."
  }
}

run "per_definition_settings_override_module_wide_ones" {
  command = plan

  variables {
    cpu         = 512
    memory      = 1024
    environment = { LEVEL = "info", REGION = "eu" }
    task_definitions = {
      small = { image = "example/a:1" }
      big = {
        image       = "example/b:1"
        cpu         = 4096
        memory      = 8192
        environment = { LEVEL = "debug" }
      }
    }
  }

  assert {
    condition     = aws_ecs_task_definition.this["small"].cpu == "512" && aws_ecs_task_definition.this["small"].memory == "1024"
    error_message = "A definition without cpu or memory must use the module-wide values."
  }
  assert {
    condition     = aws_ecs_task_definition.this["big"].cpu == "4096" && aws_ecs_task_definition.this["big"].memory == "8192"
    error_message = "A definition's own cpu and memory must win over the module-wide values."
  }
  assert {
    condition = toset(jsondecode(aws_ecs_task_definition.this["big"].container_definitions)[0].environment) == toset([
      { name = "LEVEL", value = "debug" }, { name = "REGION", value = "eu" },
    ])
    error_message = "A definition's environment must be merged over the module-wide one."
  }
  assert {
    condition = toset(jsondecode(aws_ecs_task_definition.this["small"].container_definitions)[0].environment) == toset([
      { name = "LEVEL", value = "info" }, { name = "REGION", value = "eu" },
    ])
    error_message = "A definition without environment must get the module-wide one."
  }
}

run "secrets_get_an_execution_policy_for_exactly_their_arns" {
  command = plan

  variables {
    secrets = { DB_URL = "arn:aws:secretsmanager:us-east-1:111111111111:secret:db-AbCdEf:url::" }
    task_definitions = {
      report = {
        image   = "example/report:1"
        secrets = { TOKEN = "arn:aws:ssm:us-east-1:111111111111:parameter/jobs/token" }
      }
    }
    secrets_kms_key_arns = ["arn:aws:kms:us-east-1:111111111111:key/abc"]
  }

  assert {
    condition     = length(aws_iam_role_policy.execution_secrets) == 1 && length(data.aws_iam_policy_document.execution_secrets) == 1
    error_message = "Secrets must give the execution role a policy to read them."
  }
  assert {
    condition = [for s in data.aws_iam_policy_document.execution_secrets[0].statement : { a = s.actions, r = s.resources }] == [
      { a = toset(["secretsmanager:GetSecretValue"]), r = toset(["arn:aws:secretsmanager:us-east-1:111111111111:secret:db-AbCdEf"]) },
      { a = toset(["ssm:GetParameters"]), r = toset(["arn:aws:ssm:us-east-1:111111111111:parameter/jobs/token"]) },
      { a = toset(["kms:Decrypt"]), r = toset(["arn:aws:kms:us-east-1:111111111111:key/abc"]) },
    ]
    error_message = "The execution role must read exactly the referenced secrets (selector stripped), parameters and keys."
  }
  assert {
    condition = toset(jsondecode(aws_ecs_task_definition.this["report"].container_definitions)[0].secrets) == toset([
      { name = "DB_URL", valueFrom = "arn:aws:secretsmanager:us-east-1:111111111111:secret:db-AbCdEf:url::" },
      { name = "TOKEN", valueFrom = "arn:aws:ssm:us-east-1:111111111111:parameter/jobs/token" },
    ])
    error_message = "Module-wide and per-definition secrets must both reach the container, with their selectors."
  }
}

run "efs_volumes_mount_with_iam_and_write_only_where_allowed" {
  command = plan

  variables {
    efs_volumes = [
      { name = "data", file_system_id = "fs-rw", container_path = "/data", access_point_id = "fsap-1" },
      { name = "ref", file_system_id = "fs-ro", container_path = "/ref", root_directory = "/shared", read_only = true },
    ]
  }

  assert {
    condition     = length(aws_iam_role_policy.task_efs) == 1
    error_message = "EFS volumes must give the task role a policy to mount them."
  }
  assert {
    condition = [for s in data.aws_iam_policy_document.task_efs[0].statement : { a = s.actions, r = s.resources }] == [
      {
        a = toset(["elasticfilesystem:ClientMount"])
        r = toset(["arn:aws:elasticfilesystem:us-east-1:111111111111:file-system/fs-rw", "arn:aws:elasticfilesystem:us-east-1:111111111111:file-system/fs-ro"])
      },
      { a = toset(["elasticfilesystem:ClientWrite"]), r = toset(["arn:aws:elasticfilesystem:us-east-1:111111111111:file-system/fs-rw"]) },
    ]
    error_message = "Tasks must mount every file system but write only to those with a writable volume."
  }
  assert {
    condition = {
      for v in aws_ecs_task_definition.this["report"].volume : v.name => [
        coalesce(one(v.efs_volume_configuration).root_directory, "-"),
        coalesce(one(one(v.efs_volume_configuration).authorization_config).access_point_id, "-"),
        one(v.efs_volume_configuration).transit_encryption,
        one(one(v.efs_volume_configuration).authorization_config).iam,
      ]
    } == { data = ["-", "fsap-1", "ENABLED", "ENABLED"], ref = ["/shared", "-", "ENABLED", "ENABLED"] }
    error_message = "Volumes must mount over TLS with IAM authorization, through the access point when given and root_directory only when not."
  }
  assert {
    condition = jsondecode(aws_ecs_task_definition.this["report"].container_definitions)[0].mountPoints == [
      { sourceVolume = "data", containerPath = "/data", readOnly = false },
      { sourceVolume = "ref", containerPath = "/ref", readOnly = true },
    ]
    error_message = "Each volume must be mounted at its container_path, read-only when asked."
  }
}

run "read_only_efs_volumes_get_no_client_write" {
  command = plan

  variables {
    efs_volumes = [
      { name = "ref", file_system_id = "fs-ro", container_path = "/ref", read_only = true },
    ]
  }

  assert {
    condition = [for s in data.aws_iam_policy_document.task_efs[0].statement : s.actions] == [
      toset(["elasticfilesystem:ClientMount"]),
    ]
    error_message = "When every volume is read-only the task role must not be allowed to write to EFS."
  }
}

run "options_reach_cluster_network_and_task_role" {
  command = plan

  variables {
    container_insights     = true
    cpu_architecture       = "X86_64"
    ephemeral_storage_gib  = 200
    egress_cidr_blocks     = ["10.0.0.0/8", "192.168.0.0/16"]
    subnet_ids             = ["subnet-a"]
    assign_public_ip       = true
    log_retention_days     = 7
    log_kms_key_arn        = "arn:aws:kms:us-east-1:111111111111:key/logs"
    task_role_policy_jsons = { s3 = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
    default_capacity_provider_strategy = {
      FARGATE_SPOT = { weight = 3 }
      FARGATE      = { weight = 1, base = 1 }
    }
  }

  assert {
    condition     = one(aws_ecs_cluster.this.setting).value == "enabled"
    error_message = "container_insights = true must turn on Container Insights."
  }
  assert {
    condition     = one(aws_ecs_task_definition.this["report"].runtime_platform).cpu_architecture == "X86_64" && one(aws_ecs_task_definition.this["report"].ephemeral_storage).size_in_gib == 200
    error_message = "cpu_architecture and ephemeral_storage_gib must reach the task definition."
  }
  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.this)) == toset(["10.0.0.0/8", "192.168.0.0/16"])
    error_message = "egress_cidr_blocks must replace the default open egress."
  }
  assert {
    condition     = output.run_task_network_configuration.awsvpcConfiguration.assignPublicIp == "ENABLED" && output.run_task_network_configuration.awsvpcConfiguration.subnets == tolist(["subnet-a"])
    error_message = "subnet_ids and assign_public_ip must reach the RunTask network configuration."
  }
  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 7 && aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/logs"
    error_message = "log_retention_days and log_kms_key_arn must reach the log group."
  }
  assert {
    condition     = keys(aws_iam_role_policy.task_extra) == ["s3"] && aws_iam_role_policy.task_extra["s3"].name == "s3"
    error_message = "Each task_role_policy_jsons entry must become an inline policy on the task role."
  }
  assert {
    condition = toset([for s in aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy : {
      p = s.capacity_provider, w = s.weight, b = s.base
    }]) == toset([{ p = "FARGATE_SPOT", w = 3, b = 0 }, { p = "FARGATE", w = 1, b = 1 }])
    error_message = "default_capacity_provider_strategy must set the cluster's default strategy."
  }
}

run "controller_may_run_only_this_modules_task_definitions" {
  command = plan

  variables {
    task_definitions = {
      report = { image = "example/report:1" }
      sync   = { image = "example/sync:1" }
    }
  }

  assert {
    condition = [for s in data.aws_iam_policy_document.controller.statement : s.sid] == [
      "RunTaskDefinitionsInThisCluster", "ManageTasksInThisCluster", "TagTasksInThisCluster", "PassTaskRoles",
    ]
    error_message = "The controller policy must let the controller run, manage and tag tasks and pass the task roles."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controller.statement :
      s.resources == toset([
        "arn:aws:ecs:us-east-1:111111111111:task-definition/jobs-report:*",
        "arn:aws:ecs:us-east-1:111111111111:task-definition/jobs-sync:*",
    ]) if s.sid == "RunTaskDefinitionsInThisCluster"])
    error_message = "The controller may run every revision of this module's task definitions, and no others."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controller.statement :
    s.resources == toset(["arn:aws:ecs:us-east-1:111111111111:task/jobs/*"]) if contains(["ManageTasksInThisCluster", "TagTasksInThisCluster"], s.sid)])
    error_message = "The controller may stop, describe and tag only tasks in this cluster."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.controller.statement :
    one(s.condition).variable == "iam:PassedToService" && one(s.condition).values == tolist(["ecs-tasks.amazonaws.com"]) if s.sid == "PassTaskRoles"])
    error_message = "The controller may pass the task roles to ECS tasks only."
  }
}

run "cpu_architecture_must_be_arm64_or_x86_64" {
  command = plan

  variables {
    cpu_architecture = "arm64"
  }

  expect_failures = [var.cpu_architecture]
}

run "ephemeral_storage_below_21_gib_is_rejected" {
  command = plan

  variables {
    ephemeral_storage_gib = 20
  }

  expect_failures = [var.ephemeral_storage_gib]
}

run "ephemeral_storage_above_200_gib_is_rejected" {
  command = plan

  variables {
    ephemeral_storage_gib = 201
  }

  expect_failures = [var.ephemeral_storage_gib]
}
