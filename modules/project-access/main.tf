# A role for someone who works on one project in an account that other projects
# share: run commands on and open shells to the project's instances (SSM),
# read its logs, alarms, ECS and ECR, and optionally costs. "The project" is
# whatever carries project_tag_key = one of project_tag_values, plus log groups
# under log_group_prefixes. Optionally an IAM user to sign in with, which can do
# nothing but manage its own MFA and assume the role with MFA.
#
# What a tag boundary in a shared account can't hide, and a separate account
# (the organization and identity-center modules) does:
#   - List and Describe calls without resource-level permissions show the names
#     of every project's instances, clusters, services, alarms and log groups.
#   - Cost Explorer can't be limited to a tag: allow_cost_explorer shows every
#     project's costs.
#   - A command run through SSM runs as root on the instance, with whatever its
#     instance role can do. Grant SSM only to people trusted with the project.
# The role grants no tagging, so it can't move another project's resources into
# its own boundary.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account = data.aws_caller_identity.current.account_id
  p       = data.aws_partition.current.partition
  tag     = { (var.project_tag_key) = var.project_tag_values }

  log_arns = flatten([for prefix in var.log_group_prefixes : [
    "arn:${local.p}:logs:*:${local.account}:log-group:${prefix}*",
    "arn:${local.p}:logs:*:${local.account}:log-group:${prefix}*:log-stream:*",
  ]])

  statement_groups = {
    list = [{
      Sid    = "ListAndDescribe"
      Effect = "Allow"
      # These have no resource-level permissions: they list every project's names.
      Action = [
        "ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ec2:DescribeVolumes",
        "ecs:ListClusters", "ecs:ListServices", "ecs:ListTasks", "ecs:ListTaskDefinitions",
        "ecr:DescribeRepositories", "ecr:GetAuthorizationToken",
        "cloudwatch:DescribeAlarms", "cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics",
        "logs:DescribeLogGroups", "logs:GetQueryResults", "logs:DescribeQueries",
        "ssm:DescribeInstanceInformation", "ssm:ListCommands", "ssm:ListCommandInvocations",
        "ssm:GetCommandInvocation", "ssm:DescribeSessions",
      ]
      Resource = "*"
    }]
    ecs = [{
      Sid      = "ProjectEcsAndEcr"
      Effect   = "Allow"
      Action   = ["ecs:DescribeClusters", "ecs:DescribeServices", "ecs:DescribeTasks", "ecr:DescribeImages", "ecr:ListImages", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:DescribeImageScanFindings"]
      Resource = "*"
      # Task definitions are left out: DescribeTaskDefinition can't be limited
      # by tag and shows every project's environment variables.
      Condition = { StringEquals = { for k, v in local.tag : "aws:ResourceTag/${k}" => v } }
    }]
    ssm = [
      {
        Sid       = "SsmOnProjectInstances"
        Effect    = "Allow"
        Action    = ["ssm:StartSession", "ssm:SendCommand"]
        Resource  = "arn:${local.p}:ec2:*:${local.account}:instance/*"
        Condition = { StringEquals = { for k, v in local.tag : "ssm:resourceTag/${k}" => v } }
      },
      {
        Sid    = "SsmDocuments"
        Effect = "Allow"
        Action = ["ssm:StartSession", "ssm:SendCommand"]
        Resource = concat(
          ["arn:${local.p}:ssm:*:${local.account}:document/SSM-SessionManagerRunShell"],
          [for d in var.ssm_documents : "arn:${local.p}:ssm:*::document/${d}"],
        )
      },
      {
        Sid      = "OwnSessions"
        Effect   = "Allow"
        Action   = ["ssm:TerminateSession", "ssm:ResumeSession"]
        Resource = "arn:${local.p}:ssm:*:${local.account}:session/$${aws:userid}-*"
      },
    ]
    logs = [{
      Sid      = "ProjectLogs"
      Effect   = "Allow"
      Action   = ["logs:FilterLogEvents", "logs:GetLogEvents", "logs:DescribeLogStreams", "logs:StartQuery", "logs:StopQuery", "logs:GetLogGroupFields", "logs:StartLiveTail"]
      Resource = local.log_arns
    }]
    costs = [{
      Sid      = "CostExplorerShowsEveryProject"
      Effect   = "Allow"
      Action   = ["ce:GetCostAndUsage", "ce:GetCostForecast", "ce:GetDimensionValues", "ce:GetTags"]
      Resource = "*"
    }]
  }
  statements_on = {
    list  = true
    ecs   = true
    ssm   = var.allow_ssm
    logs  = length(var.log_group_prefixes) > 0
    costs = var.allow_cost_explorer
  }
  statements = flatten([for k in ["list", "ecs", "ssm", "logs", "costs"] : local.statement_groups[k] if local.statements_on[k]])

  trusted = concat(var.trusted_principal_arns, var.user_name == null ? [] : [aws_iam_user.this[0].arn])
}

resource "aws_iam_role" "this" {
  name                 = var.name
  path                 = var.path
  description          = "Access to the project tagged ${var.project_tag_key} = ${join(" or ", var.project_tag_values)}"
  max_session_duration = var.max_session_hours * 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [merge(
      { Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = local.trusted } },
      var.require_mfa ? { Condition = { Bool = { "aws:MultiFactorAuthPresent" = "true" } } } : {},
    )]
  })

  lifecycle {
    precondition {
      condition     = length(local.trusted) > 0
      error_message = "Nobody could assume this role: set user_name or trusted_principal_arns."
    }
  }
}

resource "aws_iam_role_policy" "project" {
  name   = "project-access"
  role   = aws_iam_role.this.id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.statements })
}

resource "aws_iam_role_policy" "extra" {
  count  = var.extra_policy_json == null ? 0 : 1
  name   = "project-extra"
  role   = aws_iam_role.this.id
  policy = var.extra_policy_json
}

# ── Optional sign-in user ──────────────────────────────
# No password or keys here (they'd land in state). Give it a console password
# with: aws iam create-login-profile --user-name <user> --password-reset-required
resource "aws_iam_user" "this" {
  #checkov:skip=CKV_AWS_273:Opt-in sign-in for a shared account without Identity Center; the organization and identity-center modules are the SSO path
  count = var.user_name == null ? 0 : 1
  name  = var.user_name
  path  = "/people/"
}

resource "aws_iam_user_policy" "this" {
  #checkov:skip=CKV_AWS_40:The user's only policy: assume the project role with MFA and manage its own password and MFA
  count = var.user_name == null ? 0 : 1
  name  = "assume-${var.name}-and-own-mfa"
  user  = aws_iam_user.this[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AssumeTheProjectRoleWithMfa"
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Resource  = aws_iam_role.this.arn
        Condition = { Bool = { "aws:MultiFactorAuthPresent" = "true" } }
      },
      {
        Sid    = "OwnPasswordAndMfa"
        Effect = "Allow"
        Action = ["iam:GetUser", "iam:ChangePassword", "iam:GetLoginProfile", "iam:ListMFADevices", "iam:CreateVirtualMFADevice", "iam:EnableMFADevice", "iam:ResyncMFADevice", "iam:ListVirtualMFADevices"]
        Resource = [
          "arn:${local.p}:iam::${local.account}:user/people/$${aws:username}",
          "arn:${local.p}:iam::${local.account}:mfa/$${aws:username}",
          "arn:${local.p}:iam::${local.account}:mfa/*",
        ]
      },
      {
        Sid      = "AccountPasswordRules"
        Effect   = "Allow"
        Action   = ["iam:GetAccountPasswordPolicy"]
        Resource = "*"
      },
    ]
  })
}
