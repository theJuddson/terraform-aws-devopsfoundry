# The gateway function: in the given private subnets, HTTPS out only and nothing
# in, a role that may read only the one key parameter, and settings that hold no
# secret. Plans only, against a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-mock" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  subnet_ids = ["subnet-a", "subnet-b"]
  client_ip  = "203.0.113.10"
  api_user   = "exampleuser"
}

run "runs_in_the_private_subnets_with_https_out_only" {
  command = plan

  assert {
    condition     = toset(aws_lambda_function.fn.vpc_config[0].subnet_ids) == toset(["subnet-a", "subnet-b"])
    error_message = "The function must run in the given subnets, behind their NAT."
  }
  assert {
    condition     = aws_security_group.fn.vpc_id == "vpc-mock"
    error_message = "The security group must be in the subnets' VPC."
  }
  assert {
    condition     = length(aws_security_group.fn.ingress) == 0
    error_message = "Nothing may reach the function over the network."
  }
  assert {
    condition     = alltrue([for e in aws_security_group.fn.egress : e.from_port == 443 && e.to_port == 443 && e.protocol == "tcp"])
    error_message = "The function may only make HTTPS calls."
  }
}

run "settings_hold_no_secret" {
  command = plan

  assert {
    condition = jsonencode(aws_lambda_function.fn.environment[0].variables) == jsonencode({
      API_KEY_PARAMETER = "/devopsfoundry/namecheap/api-key"
      API_USER          = "exampleuser"
      USER_NAME         = "exampleuser"
      CLIENT_IP         = "203.0.113.10"
      SANDBOX           = "false"
      ALLOWED_DOMAINS   = ""
    })
    error_message = "The environment must name the key's parameter, never hold the key, and default USER_NAME to api_user."
  }
  assert {
    condition     = aws_lambda_function.fn.function_name == "devopsfoundry-namecheap"
    error_message = "The default name is devopsfoundry-namecheap, which namecheap-ns-gateway calls by default."
  }
  assert {
    condition     = aws_lambda_function.fn.runtime == "python3.13" && aws_lambda_function.fn.handler == "handler.handler"
    error_message = "The handler is lambda/handler.py on python3.13."
  }
}

run "the_role_may_read_only_the_key_parameter" {
  command = plan

  assert {
    condition     = local.parameter_arn == "arn:aws:ssm:us-east-1:123456789012:parameter/devopsfoundry/namecheap/api-key"
    error_message = "The role must be limited to the one parameter."
  }
}

run "a_customer_key_is_allowed_only_through_ssm" {
  command = plan

  variables {
    api_key_parameter   = "namecheap-key"
    api_key_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/abc"
    allowed_domains     = ["example.com", "example.org"]
    user_name           = "owner"
    sandbox             = true
  }

  assert {
    condition     = local.parameter_arn == "arn:aws:ssm:us-east-1:123456789012:parameter/namecheap-key"
    error_message = "A name without a leading slash must still give the right ARN."
  }
  assert {
    condition     = aws_lambda_function.fn.environment[0].variables.ALLOWED_DOMAINS == "example.com,example.org"
    error_message = "allowed_domains must reach the function."
  }
  assert {
    condition     = aws_lambda_function.fn.environment[0].variables.USER_NAME == "owner" && aws_lambda_function.fn.environment[0].variables.SANDBOX == "true"
    error_message = "user_name and sandbox must reach the function."
  }
}

run "refuses_a_bad_client_ip" {
  command = plan

  variables {
    client_ip = "not-an-ip"
  }

  expect_failures = [var.client_ip]
}
