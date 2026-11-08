# How an app attaches to a host platform: the naming conventions used to find
# the host's VPC, subnets, ALB, listener and cluster, the app's own security
# groups inside that VPC, and the database/cache toggles. Plans only, against a
# mocked AWS provider: no account is touched.

mock_provider "aws" {
  # The listener lookup takes this as load_balancer_arn, which the provider
  # validates as an ARN.
  mock_data "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/host-alb/mock" }
  }
  mock_data "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/host-alb/mock/https" }
  }
  mock_data "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:us-east-1:111111111111:cluster/host-cluster" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-a", "subnet-b"] }
  }
}

variables {
  platform_name = "host"
  name          = "demo"
}

run "defaults_find_host_by_naming_convention" {
  command = plan

  assert {
    condition     = toset(one([for f in data.aws_vpc.platform.filter : f.values if f.name == "tag:Name"])) == toset(["host-vpc"])
    error_message = "The host VPC must be found by its <platform>-vpc Name tag, as modules/networking tags it."
  }
  assert {
    condition     = toset(one([for f in data.aws_subnets.public.filter : f.values if f.name == "tag:Name"])) == toset(["host-public-*"])
    error_message = "Public subnets must be found by the <platform>-public-<az> Name tag."
  }
  assert {
    condition     = toset(one([for f in data.aws_subnets.private.filter : f.values if f.name == "tag:Name"])) == toset(["host-private-*"])
    error_message = "Private subnets must be found by the <platform>-private-<az> Name tag."
  }
  assert {
    condition = alltrue([
      for d in [data.aws_subnets.public, data.aws_subnets.private] :
      toset(one([for f in d.filter : f.values if f.name == "vpc-id"])) == toset([data.aws_vpc.platform.id])
    ])
    error_message = "Subnet lookups must be confined to the host VPC, or another VPC's subnets could match."
  }
  assert {
    condition     = toset(one([for f in data.aws_security_group.platform_alb.filter : f.values if f.name == "tag:Name"])) == toset(["host-alb-sg"])
    error_message = "The host ALB security group must be found by its <platform>-alb-sg Name tag."
  }
  assert {
    condition     = data.aws_lb.platform.name == "host-alb" && data.aws_ecs_cluster.platform.cluster_name == "host-cluster"
    error_message = "The host ALB and cluster must be found as <platform>-alb and <platform>-cluster."
  }
  assert {
    condition     = data.aws_lb_listener.https.port == 443 && data.aws_lb_listener.https.load_balancer_arn == data.aws_lb.platform.arn
    error_message = "The HTTPS listener must be looked up on port 443 of the host ALB."
  }
  assert {
    condition     = aws_security_group.api.name == "demo-api-sg" && aws_security_group.api.tags.Name == "demo-api-sg" && aws_security_group.api.vpc_id == data.aws_vpc.platform.id
    error_message = "The app needs its own <name>-api-sg in the host VPC, not the host's group."
  }
  assert {
    condition     = aws_security_group_rule.api_ingress_from_alb.source_security_group_id == data.aws_security_group.platform_alb.id
    error_message = "Tasks must admit traffic only from the host ALB's security group."
  }
  assert {
    condition     = aws_security_group_rule.api_ingress_from_alb.from_port == 8080 && aws_security_group_rule.api_ingress_from_alb.to_port == 8080
    error_message = "Tasks must admit the default container port from the host ALB."
  }
  assert {
    condition     = length(aws_security_group.rds) == 0 && length(aws_security_group_rule.rds_ingress_from_api) == 0
    error_message = "No database security group unless the database is enabled."
  }
  assert {
    condition     = length(aws_security_group.redis) == 0 && length(aws_security_group_rule.redis_ingress_from_api) == 0
    error_message = "No cache security group unless the cache is enabled."
  }
  assert {
    condition     = output.rds_security_group_id == null && output.redis_security_group_id == null
    error_message = "Disabled data-tier security group outputs must be null, as in modules/networking."
  }
}

run "outputs_pass_host_resources_through" {
  command = plan

  # Distinct ids per tier, so a swapped public/private output shows.
  override_data {
    target = data.aws_subnets.public
    values = { ids = ["subnet-public-a", "subnet-public-b"] }
  }
  override_data {
    target = data.aws_subnets.private
    values = { ids = ["subnet-private-a", "subnet-private-b"] }
  }

  assert {
    condition     = output.vpc_id == data.aws_vpc.platform.id && output.alb_security_group_id == data.aws_security_group.platform_alb.id
    error_message = "The VPC and ALB security group outputs must be the host's."
  }
  assert {
    condition     = tolist(output.public_subnet_ids) == tolist(["subnet-public-a", "subnet-public-b"]) && tolist(output.private_subnet_ids) == tolist(["subnet-private-a", "subnet-private-b"])
    error_message = "Public and private subnet outputs must be the host's subnets of that tier; a swap would put tasks or the database on the wrong tier."
  }
  assert {
    condition     = output.alb_arn == data.aws_lb.platform.arn && output.alb_dns_name == data.aws_lb.platform.dns_name && output.alb_zone_id == data.aws_lb.platform.zone_id
    error_message = "container-service needs the host ALB's ARN, DNS name and zone id."
  }
  assert {
    condition     = output.https_listener_arn == data.aws_lb_listener.https.arn
    error_message = "container-service attaches its listener rule to the host's HTTPS listener."
  }
  assert {
    condition     = output.ecs_cluster_arn == "arn:aws:ecs:us-east-1:111111111111:cluster/host-cluster" && output.ecs_cluster_name == "host-cluster"
    error_message = "container-service runs the service on the host's cluster."
  }
}

run "custom_ports_follow_variables" {
  command = plan

  variables {
    container_port      = 3000
    https_listener_port = 8443
  }

  assert {
    condition     = aws_security_group_rule.api_ingress_from_alb.from_port == 3000 && aws_security_group_rule.api_ingress_from_alb.to_port == 3000
    error_message = "Tasks must admit container_port from the host ALB."
  }
  assert {
    condition     = data.aws_lb_listener.https.port == 8443
    error_message = "https_listener_port must select which host listener to attach to."
  }
}

run "database_and_cache_get_app_owned_security_groups" {
  command = plan

  variables {
    enable_database = true
    enable_cache    = true
    db_port         = 5433
    cache_port      = 6380
  }

  assert {
    condition     = length(aws_security_group.rds) == 1 && aws_security_group.rds[0].name == "demo-rds-sg" && aws_security_group.rds[0].vpc_id == data.aws_vpc.platform.id
    error_message = "enable_database must create the app's own <name>-rds-sg in the host VPC."
  }
  assert {
    condition     = length(aws_security_group_rule.rds_ingress_from_api) == 1 && aws_security_group_rule.rds_ingress_from_api[0].from_port == 5433 && aws_security_group_rule.rds_ingress_from_api[0].to_port == 5433
    error_message = "The database must admit db_port from this app's tasks."
  }
  assert {
    condition     = length(aws_security_group.redis) == 1 && aws_security_group.redis[0].name == "demo-redis-sg" && aws_security_group.redis[0].vpc_id == data.aws_vpc.platform.id
    error_message = "enable_cache must create the app's own <name>-redis-sg in the host VPC."
  }
  assert {
    condition     = length(aws_security_group_rule.redis_ingress_from_api) == 1 && aws_security_group_rule.redis_ingress_from_api[0].from_port == 6380 && aws_security_group_rule.redis_ingress_from_api[0].to_port == 6380
    error_message = "The cache must admit cache_port from this app's tasks."
  }
}
