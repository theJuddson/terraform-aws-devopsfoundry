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
  # No platform descriptors published: hosts are found by naming convention.
  mock_data "aws_ssm_parameters_by_path" {
    defaults = { names = [], values = [] }
  }
  # A host built with a NAT gateway: its private subnets route 0.0.0.0/0 out.
  mock_data "aws_route_table" {
    defaults = { routes = [{ cidr_block = "0.0.0.0/0", nat_gateway_id = "nat-mock" }] }
  }
}

variables {
  platform_name = "host"
  name          = "demo"
}

run "defaults_find_host_by_naming_convention" {
  command = plan

  assert {
    condition     = output.platform_source == "naming" && data.aws_ssm_parameters_by_path.platforms.path == "/devopsfoundry/platform"
    error_message = "Without a descriptor the platform must be found by naming convention, after checking /devopsfoundry/platform."
  }

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

run "host_with_nat_lets_tasks_run_in_private_subnets" {
  command = plan

  assert {
    condition     = output.private_subnets_have_egress
    error_message = "Private subnets with a 0.0.0.0/0 route must count as having egress."
  }
  assert {
    condition     = toset(keys(data.aws_route_table.private)) == toset(["subnet-a", "subnet-b"])
    error_message = "Every private subnet's route table must be checked, not just one."
  }
}

# A host built with enable_nat_gateway = false: no default route in its private subnets.
run "host_without_nat_rejects_tasks_in_private_subnets" {
  command = plan

  override_data {
    target = data.aws_route_table.private
    values = { routes = [] }
  }

  expect_failures = [aws_security_group.api]
}

run "host_without_nat_accepts_tasks_in_public_subnets" {
  command = plan

  variables {
    tasks_in_public_subnets = true
  }

  override_data {
    target = data.aws_route_table.private
    values = { routes = [] }
  }

  assert {
    condition     = output.private_subnets_have_egress == false
    error_message = "Private subnets without a default route must be reported as having no egress."
  }
}

run "a_local_route_alone_is_not_egress" {
  command = plan

  override_data {
    target = data.aws_route_table.private
    values = { routes = [{ cidr_block = "10.0.0.0/16", gateway_id = "local" }] }
  }

  expect_failures = [aws_security_group.api]
}

# ── Platform descriptors (/devopsfoundry/platform/<name>) ──

run "a_published_descriptor_is_used_by_id" {
  command = plan

  variables {
    platform_name = "shared-web"
  }

  # Another platform's descriptor first, and one whose name merely starts with
  # this one's, so a wrong index or a prefix match would pick the wrong IDs.
  override_data {
    target = data.aws_ssm_parameters_by_path.platforms
    values = {
      names = ["/devopsfoundry/platform/other", "/devopsfoundry/platform/shared-web-2", "/devopsfoundry/platform/shared-web"]
      values = [
        "{\"version\":1,\"host\":\"x\",\"vpc_id\":\"vpc-wrong\",\"public_subnet_ids\":[],\"private_subnet_ids\":[],\"alb_security_group_id\":\"sg-wrong\",\"alb_arn\":\"arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/wrong/1\",\"ecs_cluster_name\":\"wrong\"}",
        "{\"version\":1,\"host\":\"y\",\"vpc_id\":\"vpc-wrong2\",\"public_subnet_ids\":[],\"private_subnet_ids\":[],\"alb_security_group_id\":\"sg-wrong2\",\"alb_arn\":\"arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/wrong2/1\",\"ecs_cluster_name\":\"wrong2\"}",
        "{\"version\":1,\"host\":\"first-app-com\",\"vpc_id\":\"vpc-host\",\"public_subnet_ids\":[\"subnet-pub-1\",\"subnet-pub-2\"],\"private_subnet_ids\":[\"subnet-priv-1\",\"subnet-priv-2\"],\"alb_security_group_id\":\"sg-host-alb\",\"alb_arn\":\"arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/first-app-com-alb/abc\",\"ecs_cluster_name\":\"first-app-com-cluster\"}",
      ]
    }
  }

  assert {
    condition     = output.platform_source == "descriptor"
    error_message = "A published descriptor must be preferred over naming conventions."
  }
  assert {
    condition     = data.aws_vpc.platform.id == "vpc-host" && length(data.aws_vpc.platform.filter) == 0
    error_message = "The VPC must be looked up by the descriptor's vpc_id, not by a <platform>-vpc tag."
  }
  assert {
    condition = (
      toset(one([for f in data.aws_subnets.public.filter : f.values if f.name == "subnet-id"])) == toset(["subnet-pub-1", "subnet-pub-2"]) &&
      toset(one([for f in data.aws_subnets.private.filter : f.values if f.name == "subnet-id"])) == toset(["subnet-priv-1", "subnet-priv-2"])
    )
    error_message = "Subnets must be looked up by the descriptor's IDs, each tier from its own list."
  }
  assert {
    condition = alltrue([
      for d in [data.aws_subnets.public, data.aws_subnets.private] :
      length([for f in d.filter : f if f.name == "tag:Name"]) == 0 &&
      toset(one([for f in d.filter : f.values if f.name == "vpc-id"])) == toset([data.aws_vpc.platform.id])
    ])
    error_message = "Descriptor subnets must still be confined to the platform VPC, and not filtered by name."
  }
  assert {
    condition     = data.aws_security_group.platform_alb.id == "sg-host-alb" && length(data.aws_security_group.platform_alb.filter) == 0
    error_message = "The ALB security group must be the descriptor's alb_security_group_id."
  }
  assert {
    condition     = data.aws_lb.platform.arn == "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/first-app-com-alb/abc" && data.aws_lb.platform.name != "shared-web-alb"
    error_message = "The ALB must be the descriptor's alb_arn, not <platform>-alb."
  }
  assert {
    condition     = data.aws_ecs_cluster.platform.cluster_name == "first-app-com-cluster"
    error_message = "The cluster must be the descriptor's ecs_cluster_name, not <platform>-cluster."
  }
  assert {
    condition     = data.aws_lb_listener.https.load_balancer_arn == data.aws_lb.platform.arn && data.aws_lb_listener.https.port == 443
    error_message = "The HTTPS listener must still be found on the descriptor's ALB."
  }
}

run "another_platforms_descriptor_is_ignored" {
  command = plan

  override_data {
    target = data.aws_ssm_parameters_by_path.platforms
    values = {
      names  = ["/devopsfoundry/platform/host-2"]
      values = ["{\"version\":1}"]
    }
  }

  assert {
    condition     = output.platform_source == "naming" && data.aws_lb.platform.name == "host-alb"
    error_message = "Only /devopsfoundry/platform/<platform_name> itself may be used; otherwise naming conventions apply."
  }
}

run "an_unknown_descriptor_version_stops_the_plan" {
  command = plan

  override_data {
    target = data.aws_ssm_parameters_by_path.platforms
    values = {
      names  = ["/devopsfoundry/platform/host"]
      values = ["{\"version\":2,\"host\":\"h\",\"vpc_id\":\"vpc-1\",\"public_subnet_ids\":[],\"private_subnet_ids\":[],\"alb_security_group_id\":\"sg-1\",\"alb_arn\":\"arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/h/1\",\"ecs_cluster_name\":\"c\"}"]
    }
  }

  expect_failures = [data.aws_vpc.platform]
}

run "a_descriptor_missing_a_field_stops_the_plan" {
  command = plan

  override_data {
    target = data.aws_ssm_parameters_by_path.platforms
    values = {
      names  = ["/devopsfoundry/platform/host"]
      values = ["{\"version\":1,\"host\":\"h\",\"vpc_id\":\"vpc-1\",\"public_subnet_ids\":[],\"private_subnet_ids\":[],\"alb_security_group_id\":\"sg-1\",\"ecs_cluster_name\":\"c\"}"]
    }
  }

  expect_failures = [data.aws_vpc.platform]
}

run "a_descriptor_that_is_not_json_stops_the_plan" {
  command = plan

  override_data {
    target = data.aws_ssm_parameters_by_path.platforms
    values = {
      names  = ["/devopsfoundry/platform/host"]
      values = ["vpc-123"]
    }
  }

  expect_failures = [data.aws_vpc.platform]
}
