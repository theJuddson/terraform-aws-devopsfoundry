# An app root whose delegation Terraform doesn't manage (bin/new-app
# --existing-zone, or released by bin/release-nameservers) plans with no
# Namecheap credentials: its namecheap.tf configures the provider with
# placeholders, and nothing calls Namecheap. The Namecheap provider is real
# here, not mocked, and tests/app-root/run.sh unsets NAMECHEAP_*, so a root
# that needed credentials fails this plan. AWS and random are mocked.

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
mock_provider "random" {}

variables {
  name               = "example-com"
  domain_name        = "example.com"
  subdomain          = "api"
  existing_zone_name = "example.com"
}

run "plans_without_namecheap_credentials" {
  command = plan

  assert {
    condition     = length(module.app.name_servers) == 0
    error_message = "An existing-zone app creates no zone of its own."
  }
}

# The same placeholders serve an app whose own zone's delegation
# bin/release-nameservers handed off: no Namecheap resource is planned.
run "a_released_app_plans_without_namecheap_credentials" {
  command = plan

  variables {
    existing_zone_name = ""
    manage_nameservers = false
  }

  # The plan succeeding with the real Namecheap provider is the test.
}
