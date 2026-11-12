# A role limited to one project's tagged resources in a shared account.
# Plans only, mocked provider.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_iam_user" {
    defaults = { arn = "arn:aws:iam::111111111111:user/people/tayler" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/people/agents-collaborator" }
  }
}

variables {
  name               = "agents-collaborator"
  project_tag_values = ["agents"]
  log_group_prefixes = ["/agents/"]
  user_name          = "tayler"
}

run "defaults_ssm_logs_reads_and_an_mfa_user" {
  command = apply

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.AWS == ["arn:aws:iam::111111111111:user/people/tayler"]
    error_message = "The user must be the role's trusted principal."
  }
  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition == { Bool = { "aws:MultiFactorAuthPresent" = "true" } }
    error_message = "Assuming the role must need MFA."
  }
  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.project.policy).Statement : s.Sid] == ["ListAndDescribe", "ProjectEcsAndEcr", "SsmOnProjectInstances", "SsmDocuments", "OwnSessions", "ProjectLogs"]
    error_message = "By default: reads, project ECS/ECR, SSM and logs; no Cost Explorer."
  }
  assert {
    condition = one([for s in jsondecode(aws_iam_role_policy.project.policy).Statement : s if s.Sid == "SsmOnProjectInstances"]) == {
      Sid       = "SsmOnProjectInstances"
      Effect    = "Allow"
      Action    = ["ssm:StartSession", "ssm:SendCommand"]
      Resource  = "arn:aws:ec2:*:111111111111:instance/*"
      Condition = { StringEquals = { "ssm:resourceTag/project" = ["agents"] } }
    }
    error_message = "Shells and commands must be limited to instances tagged with the project."
  }
  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.project.policy).Statement : s.Condition if s.Sid == "ProjectEcsAndEcr"]) == { StringEquals = { "aws:ResourceTag/project" = ["agents"] } }
    error_message = "ECS and ECR reads must be limited to the project's tag."
  }
  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.project.policy).Statement : s.Resource if s.Sid == "ProjectLogs"]) == ["arn:aws:logs:*:111111111111:log-group:/agents/*", "arn:aws:logs:*:111111111111:log-group:/agents/*:log-stream:*"]
    error_message = "Log reads must be limited to the prefixes."
  }
  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.project.policy).Statement : s.Resource if s.Sid == "SsmDocuments"]) == ["arn:aws:ssm:*:111111111111:document/SSM-SessionManagerRunShell", "arn:aws:ssm:*::document/AWS-RunShellScript"]
    error_message = "Only the session document and the allowed command documents."
  }
  assert {
    condition     = !strcontains(aws_iam_role_policy.project.policy, "Tag") || !can(regex("\"(ec2|ecs|ecr|logs|ssm):(Create|Delete|Untag|Tag)", aws_iam_role_policy.project.policy))
    error_message = "The role must not be able to change tags."
  }
  assert {
    condition     = !strcontains(aws_iam_role_policy.project.policy, "DescribeTaskDefinition")
    error_message = "Task definitions show every project's environment; they must stay out."
  }
  assert {
    condition     = aws_iam_role.this.max_session_duration == 14400 && aws_iam_role.this.path == "/people/"
    error_message = "Four-hour sessions under /people/ by default."
  }
  assert {
    condition     = jsondecode(aws_iam_user_policy.this[0].policy).Statement[0] == { Sid = "AssumeTheProjectRoleWithMfa", Effect = "Allow", Action = "sts:AssumeRole", Resource = "arn:aws:iam::111111111111:role/people/agents-collaborator", Condition = { Bool = { "aws:MultiFactorAuthPresent" = "true" } } }
    error_message = "The user may only assume this role, with MFA."
  }
  assert {
    condition     = length(jsondecode(aws_iam_user_policy.this[0].policy).Statement) == 3
    error_message = "The user may do nothing else but manage its own password and MFA."
  }
  assert {
    condition     = output.switch_role_url == "https://signin.aws.amazon.com/switchrole?account=111111111111&roleName=agents-collaborator&displayName=agents-collaborator"
    error_message = "The switch-role link must name the account and role."
  }
}

run "options_turn_statements_on_and_off" {
  command = plan

  variables {
    allow_ssm           = false
    allow_cost_explorer = true
    log_group_prefixes  = []
    require_mfa         = false
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.project.policy).Statement : s.Sid] == ["ListAndDescribe", "ProjectEcsAndEcr", "CostExplorerShowsEveryProject"]
    error_message = "No SSM or logs when turned off; Cost Explorer when asked."
  }
  assert {
    condition     = !can(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition)
    error_message = "Without require_mfa the trust has no condition."
  }
}

run "another_principal_without_a_user" {
  command = plan

  variables {
    user_name              = null
    trusted_principal_arns = ["arn:aws:iam::111111111111:user/someone"]
    project_tag_values     = ["agents", "agents-spike"]
    extra_policy_json      = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }

  assert {
    condition     = length(aws_iam_user.this) == 0 && length(aws_iam_role_policy.extra) == 1
    error_message = "No user when user_name is null; the extra policy when given."
  }
  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.AWS == ["arn:aws:iam::111111111111:user/someone"]
    error_message = "The given principals are trusted."
  }
  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.project.policy).Statement : s.Condition if s.Sid == "SsmOnProjectInstances"]) == { StringEquals = { "ssm:resourceTag/project" = ["agents", "agents-spike"] } }
    error_message = "Every project tag value counts."
  }
}

run "nobody_trusted_is_refused" {
  command = plan

  variables {
    user_name = null
  }

  expect_failures = [aws_iam_role.this]
}

run "inputs_are_checked" {
  command = plan

  variables {
    project_tag_values = [" "]
    log_group_prefixes = ["/agents/*"]
    max_session_hours  = 13
  }

  expect_failures = [var.project_tag_values, var.log_group_prefixes, var.max_session_hours]
}
