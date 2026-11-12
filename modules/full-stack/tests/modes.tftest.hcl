# Which parts of the stack each mode builds. Plans only, against mocked
# providers: no AWS or Namecheap account is touched.

# Mocked providers return random strings for computed values. Give the few
# the configuration parses or iterates over realistic shapes.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  # Shared-platform lookups: the provider validates these as ARNs.
  mock_data "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/host/mock" }
  }
  mock_data "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/host/mock/https" }
  }
  mock_data "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:us-east-1:111111111111:cluster/host", cluster_name = "host" }
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
mock_provider "aws" {
  alias = "us_east_1"

  # route53-zone-security runs on this provider and checks it is us-east-1.
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    override_during = plan
    defaults        = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:/aws/route53/example.com" }
  }
  mock_resource "aws_kms_key" {
    override_during = plan
    defaults        = { arn = "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555" }
  }

  # Real plans only know the validation records once the certificate exists
  # (bin/new-app applies the zone first); here they are known up front.
  mock_resource "aws_acm_certificate" {
    override_during = plan
    defaults = {
      arn = "arn:aws:acm:us-east-1:111111111111:certificate/mock"
      domain_validation_options = [{
        domain_name           = "example.com"
        resource_record_name  = "_mock.example.com."
        resource_record_type  = "CNAME"
        resource_record_value = "_mock.acm-validations.aws."
      }]
    }
  }
}
mock_provider "namecheap" {}
mock_provider "random" {}

variables {
  name        = "demo"
  domain_name = "example.com"
}

run "defaults_own_zone_and_delegate_nameservers" {
  command = plan

  assert {
    condition     = length(module.route53_zone) == 1 && length(module.namecheap_ns) == 1
    error_message = "By default the stack creates its zone and delegates the domain to it."
  }
  assert {
    condition     = length(module.networking) == 1 && length(module.shared_platform) == 0
    error_message = "By default the stack builds its own network."
  }
  assert {
    condition     = length(module.database) == 0 && length(module.cache) == 0 && length(module.email) == 0
    error_message = "Database, cache and email are off by default."
  }
  assert {
    condition     = length(aws_secretsmanager_secret.redis_auth) == 0
    error_message = "No Redis auth secret without the cache."
  }
}

run "manage_nameservers_false_keeps_zone_skips_delegation" {
  command = plan

  variables {
    manage_nameservers = false
  }

  assert {
    condition     = length(module.route53_zone) == 1
    error_message = "The zone must stay when only the delegation is unmanaged."
  }
  assert {
    condition     = length(module.namecheap_ns) == 0
    error_message = "manage_nameservers = false must not plan any Namecheap records."
  }
}

run "existing_zone_creates_no_zone_and_never_touches_registrar" {
  command = plan

  variables {
    existing_zone_name = "example.com"
    subdomain          = "app"
  }

  assert {
    condition     = length(module.route53_zone) == 0 && length(module.namecheap_ns) == 0
    error_message = "With existing_zone_name set, no zone is created and the registrar is never touched."
  }
}

run "existing_zone_rejects_email" {
  command = plan

  variables {
    existing_zone_name = "example.com"
    subdomain          = "app"
    enable_email       = true
    dmarc_rua_email    = "dmarc@example.com"
  }

  expect_failures = [data.aws_route53_zone.existing]
}

run "existing_zone_must_be_parent_of_hostname" {
  command = plan

  variables {
    existing_zone_name = "other.com"
    subdomain          = "app"
  }

  expect_failures = [data.aws_route53_zone.existing]
}

run "existing_zone_rejects_apex" {
  command = plan

  variables {
    existing_zone_name = "example.com"
    subdomain          = ""
  }

  expect_failures = [data.aws_route53_zone.existing]
}

run "existing_zone_rejects_apex_given_as_at" {
  command = plan

  variables {
    existing_zone_name = "example.com"
    subdomain          = "@"
  }

  expect_failures = [data.aws_route53_zone.existing]
}

run "existing_zone_name_must_be_a_dns_name" {
  command = plan

  variables {
    existing_zone_name = "Example.com/zone"
  }

  expect_failures = [var.existing_zone_name]
}

run "shared_platform_borrows_network" {
  command = plan

  variables {
    shared_platform = "host"
  }

  assert {
    condition     = length(module.networking) == 0 && length(module.shared_platform) == 1
    error_message = "Shared-platform mode must not build a network of its own."
  }
}

run "backing_services_follow_their_toggles" {
  command = plan

  variables {
    enable_database = true
    enable_cache    = true
    enable_email    = true
    dmarc_rua_email = "dmarc@example.com"
  }

  assert {
    condition     = length(module.database) == 1 && length(module.cache) == 1 && length(module.email) == 1
    error_message = "Each enabled backing service must be planned."
  }
  assert {
    condition     = length(aws_secretsmanager_secret.redis_auth) == 1 && aws_secretsmanager_secret.redis_auth[0].name == "demo/redis/auth"
    error_message = "Enabling the cache must create the Redis auth secret."
  }
}

run "dmarc_report_zone_reaches_the_email_module" {
  command = plan

  variables {
    enable_email         = true
    dmarc_rua_email      = "dmarc@example.net"
    dmarc_report_zone_id = "Z999REPORTS"
  }

  assert {
    condition     = output.dmarc_report_authorization == { name = "example.com._report._dmarc.example.net", type = "TXT", value = "v=DMARC1", created = true }
    error_message = "dmarc_report_zone_id must reach the email module, and its authorization record must be output."
  }
}

run "no_dmarc_report_authorization_without_email" {
  command = plan

  assert {
    condition     = output.dmarc_report_authorization == null
    error_message = "Without email there is no report authorization record."
  }
}

run "flow_logs_reach_the_network_module" {
  command = plan

  variables {
    enable_flow_logs = true
  }

  assert {
    condition     = module.networking[0].flow_log_group_name == "/vpc/demo/flow-logs"
    error_message = "enable_flow_logs must be passed through to the networking module."
  }
}

run "guest_on_a_host_without_nat_can_run_tasks_in_public_subnets" {
  command = plan

  variables {
    shared_platform         = "host"
    tasks_in_public_subnets = true
  }

  override_data {
    target = module.shared_platform[0].data.aws_route_table.private
    values = { routes = [] }
  }

  # Without tasks_in_public_subnets reaching shared-platform, this plan would fail.
  assert {
    condition     = module.shared_platform[0].private_subnets_have_egress == false
    error_message = "The guest must see that the host's private subnets have no route out."
  }
}

run "kms_key_encrypts_the_redis_auth_secret" {
  command = plan

  variables {
    enable_cache = true
    kms_key_arn  = "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_secretsmanager_secret.redis_auth[0].kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "kms_key_arn must encrypt the Redis auth secret full-stack owns."
  }
}

run "dns_security_off_by_default" {
  command = plan

  assert {
    condition     = length(module.route53_zone_security) == 0 && output.dnssec_ds_record == null
    error_message = "DNSSEC and query logging must stay off unless asked for."
  }
}

run "dns_security_on_for_the_stacks_own_zone" {
  command = plan

  variables {
    enable_dnssec            = true
    enable_dns_query_logging = true
  }

  assert {
    condition     = length(module.route53_zone_security) == 1 && module.route53_zone_security[0].query_log_group_name == "/aws/route53/example.com"
    error_message = "enable_dnssec / enable_dns_query_logging must reach the zone security module for the stack's zone."
  }
}

run "dns_security_never_touches_an_existing_zone" {
  command = plan

  variables {
    existing_zone_name       = "example.com"
    subdomain                = "app"
    enable_dnssec            = true
    enable_dns_query_logging = true
  }

  assert {
    condition     = length(module.route53_zone_security) == 0
    error_message = "A zone this stack didn't create must never be signed or logged by it."
  }
}

run "cpu_architecture_reaches_the_service" {
  command = plan

  variables {
    cpu_architecture = "ARM64"
  }

  assert {
    condition     = output.cpu_architecture == "ARM64"
    error_message = "cpu_architecture must reach container-service and come back as an output for deploy-app."
  }
}

run "no_platform_descriptor_by_default" {
  command = plan

  assert {
    condition     = length(aws_ssm_parameter.platform_descriptor) == 0 && output.platform_descriptor_name == null
    error_message = "A stack must publish no platform descriptor unless platform_name is set."
  }
}

run "platform_name_publishes_the_stacks_own_infrastructure" {
  command = plan

  variables {
    platform_name = "shared-web"
  }

  # Known module outputs, so the descriptor's JSON is known at plan.
  override_module {
    target = module.networking[0]
    outputs = {
      vpc_id                  = "vpc-demo"
      public_subnet_ids       = ["subnet-pub-1", "subnet-pub-2"]
      private_subnet_ids      = ["subnet-priv-1", "subnet-priv-2"]
      alb_security_group_id   = "sg-demo-alb"
      api_security_group_id   = "sg-demo-api"
      rds_security_group_id   = null
      redis_security_group_id = null
      flow_log_group_name     = null
    }
  }
  override_module {
    target = module.container_service
    outputs = {
      alb_arn            = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/demo-alb/abc"
      ecs_cluster_name   = "demo-cluster"
      ecr_repository_url = "111111111111.dkr.ecr.us-east-1.amazonaws.com/demo"
      ecs_service_name   = "demo"
      service_fqdn       = "example.com"
      service_url        = "https://example.com"
      alb_dns_name       = "demo-alb.example"
      log_group          = "/ecs/demo"
      task_role_arn      = "arn:aws:iam::111111111111:role/demo-task"
      waf_web_acl_arn    = ""
      cpu_architecture   = "X86_64"
    }
  }

  assert {
    condition     = aws_ssm_parameter.platform_descriptor[0].name == "/devopsfoundry/platform/shared-web" && output.platform_descriptor_name == "/devopsfoundry/platform/shared-web"
    error_message = "The descriptor must be published at /devopsfoundry/platform/<platform_name>, where modules/shared-platform looks."
  }
  assert {
    condition = jsondecode(aws_ssm_parameter.platform_descriptor[0].insecure_value) == {
      version               = 1
      host                  = "demo"
      vpc_id                = "vpc-demo"
      public_subnet_ids     = ["subnet-pub-1", "subnet-pub-2"]
      private_subnet_ids    = ["subnet-priv-1", "subnet-priv-2"]
      alb_security_group_id = "sg-demo-alb"
      alb_arn               = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/demo-alb/abc"
      ecs_cluster_name      = "demo-cluster"
    }
    error_message = "The descriptor must carry the stack's own network, ALB and cluster IDs in modules/shared-platform's version 1 schema."
  }
  assert {
    condition     = aws_ssm_parameter.platform_descriptor[0].type == "String"
    error_message = "Guests read the descriptor without KMS grants, so it must be a plain String."
  }
}

run "a_guest_cannot_publish_a_platform" {
  command = plan

  variables {
    shared_platform = "host"
    platform_name   = "shared-web"
  }

  expect_failures = [aws_ssm_parameter.platform_descriptor]
}

run "platform_name_must_be_a_slug" {
  command = plan

  variables {
    platform_name = "Shared_Web"
  }

  expect_failures = [var.platform_name]
}

run "rotation_state_reaches_the_cache_and_email_modules" {
  command = plan

  variables {
    enable_cache                     = true
    enable_email                     = true
    dmarc_rua_email                  = "dmarc@example.com"
    cache_auth_token_generation      = 2
    cache_auth_token_update_strategy = "SET"
    smtp_active_key                  = "b"
    smtp_standby_key                 = "inactive"
  }

  assert {
    condition     = module.cache[0].auth_token_rotation == { generation = 2, strategy = "SET" }
    error_message = "The Redis rotation inputs must reach the cache module."
  }
  assert {
    condition     = module.email[0].smtp_keys == { active = "b", status = { a = "Inactive", b = "Active" } }
    error_message = "The SMTP key slots must reach the email module."
  }
}

run "alarm_emails_reach_the_service_and_the_database" {
  command = plan

  variables {
    enable_database = true
    desired_count   = 1
    alarm_emails    = ["ops@example.com"]
  }

  assert {
    condition     = length(module.container_service.alarm_names) == 4 && length(module.database[0].alarm_names) >= 2
    error_message = "alarm_emails must turn on the service's and the database's alarms."
  }
}

run "no_alarms_unless_asked" {
  command = plan

  variables {
    enable_database = true
  }

  assert {
    condition     = length(module.container_service.alarm_names) == 0 && length(module.database[0].alarm_names) == 0
    error_message = "Without alarm_emails or alarm_sns_topic_arns, no alarms."
  }
}
