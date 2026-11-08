# What the task, service and supporting resources are built from: names,
# container definition (image, PORT, env, secrets, logs), secrets-read policy,
# subnet placement and health checks. Plans only, against a mocked provider:
# no AWS account is touched.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
}

variables {
  name                  = "demo"
  domain_name           = "example.com"
  zone_id               = "Z0000000000MOCK"
  certificate_arn       = "arn:aws:acm:us-east-1:111111111111:certificate/mock"
  vpc_id                = "vpc-mock"
  public_subnet_ids     = ["subnet-pub-a", "subnet-pub-b"]
  private_subnet_ids    = ["subnet-priv-a", "subnet-priv-b"]
  alb_security_group_id = "sg-alb"
  api_security_group_id = "sg-api"
}

run "defaults_names_private_subnets_no_secrets" {
  command = plan

  assert {
    condition = (
      module.ecr.repository_name == "demo-app" &&
      aws_cloudwatch_log_group.app.name == "/ecs/demo-app" &&
      aws_ecs_task_definition.app.family == "demo-app" &&
      aws_ecs_service.app.name == "demo-app" &&
      aws_iam_role.task_execution.name == "demo-app-exec" &&
      aws_iam_role.task.name == "demo-app-task" &&
      aws_lb_target_group.app.name == "demo-app-tg"
    )
    error_message = "Resources must be named <name>-<service_name>; scripts look them up by these names."
  }
  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 14
    error_message = "Logs must be kept 14 days by default."
  }
  assert {
    condition = (
      aws_ecs_service.app.network_configuration[0].subnets == toset(var.private_subnet_ids) &&
      aws_ecs_service.app.network_configuration[0].assign_public_ip == false &&
      aws_ecs_service.app.network_configuration[0].security_groups == toset(["sg-api"])
    )
    error_message = "By default tasks must run in the private subnets without public IPs, behind the API security group."
  }
  assert {
    condition     = aws_ecs_service.app.desired_count == 1 && aws_ecs_service.app.health_check_grace_period_seconds == 120
    error_message = "By default one task runs, with a 120 s health-check grace period."
  }
  assert {
    condition = (
      aws_lb_target_group.app.port == 8080 &&
      aws_lb_target_group.app.health_check[0].path == "/health" &&
      aws_lb_target_group.app.health_check[0].matcher == "200" &&
      one(aws_ecs_service.app.load_balancer).container_port == 8080 &&
      one(aws_ecs_service.app.load_balancer).container_name == "app"
    )
    error_message = "The target group and service must route to the container on port 8080 and check /health."
  }
  assert {
    condition     = aws_ecs_task_definition.app.cpu == "512" && aws_ecs_task_definition.app.memory == "1024"
    error_message = "Tasks must default to 512 CPU units and 1024 MiB."
  }
  assert {
    condition = (
      length(data.aws_iam_policy_document.task_execution_secrets) == 0 &&
      length(aws_iam_role_policy.task_execution_secrets) == 0
    )
    error_message = "Without secrets the execution role must get no secrets-read policy."
  }
}

run "container_definition_from_inputs" {
  command = plan

  variables {
    service_name   = "web"
    container_port = 3000
    # A fixed image keeps the container definition known at plan; the default
    # uses the repository URL, which is only known after apply.
    container_image = "public.ecr.aws/nginx/nginx:1.27"
    env             = { APP_ENV = "prod" }
    secrets         = { DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:111111111111:secret:db-AbCdEf:password::" }
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].name == "web"
    error_message = "The container must be named after service_name, which the service's load balancer block targets."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].image == "public.ecr.aws/nginx/nginx:1.27"
    error_message = "A caller-supplied image must replace the module's own repository."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].portMappings == [{ containerPort = 3000, protocol = "tcp" }]
    error_message = "The container must expose container_port."
  }
  assert {
    condition = toset(jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment) == toset([
      { name = "PORT", value = "3000" },
      { name = "APP_ENV", value = "prod" },
    ])
    error_message = "The container must receive PORT plus the caller's env."
  }
  assert {
    condition = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].secrets == [
      { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:us-east-1:111111111111:secret:db-AbCdEf:password::" },
    ]
    error_message = "Secrets must be injected with their full valueFrom, JSON-key selector included."
  }
  assert {
    condition = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].logConfiguration.options == {
      awslogs-group         = "/ecs/demo-web"
      awslogs-region        = "us-east-1"
      awslogs-stream-prefix = "web"
    }
    error_message = "Container logs must go to the module's log group in the current region."
  }
  assert {
    condition     = aws_lb_target_group.app.port == 3000 && one(aws_ecs_service.app.load_balancer).container_port == 3000
    error_message = "The target group and service must follow container_port."
  }
  assert {
    condition     = length(aws_iam_role_policy.task_execution_secrets) == 1
    error_message = "With secrets the execution role must be allowed to read them, or tasks fail to start."
  }
  assert {
    condition     = data.aws_iam_policy_document.task_execution_secrets[0].statement[0].resources == toset(["arn:aws:secretsmanager:us-east-1:111111111111:secret:db-AbCdEf"])
    error_message = "The secrets-read policy must grant the base secret ARN, without the JSON-key selector."
  }
}

run "env_port_overrides_injected_port" {
  command = plan

  variables {
    container_image = "public.ecr.aws/nginx/nginx:1.27"
    env             = { PORT = "9000" }
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment == [{ name = "PORT", value = "9000" }]
    error_message = "A PORT in the caller's env must override the injected one."
  }
}

run "tasks_in_public_subnets_get_public_ips" {
  command = plan

  variables {
    tasks_in_public_subnets = true
  }

  assert {
    condition = (
      aws_ecs_service.app.network_configuration[0].subnets == toset(var.public_subnet_ids) &&
      aws_ecs_service.app.network_configuration[0].assign_public_ip == true
    )
    error_message = "tasks_in_public_subnets must place tasks in the public subnets with public IPs, or they cannot reach ECR without NAT."
  }
}

run "zero_desired_count_drops_grace_period" {
  command = plan

  variables {
    desired_count = 0
  }

  assert {
    condition     = aws_ecs_service.app.desired_count == 0 && aws_ecs_service.app.health_check_grace_period_seconds == null
    error_message = "A bootstrap service with no tasks must be planned with desired_count 0 and no grace period."
  }
}
