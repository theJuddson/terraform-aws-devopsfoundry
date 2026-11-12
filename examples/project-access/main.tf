# A collaborator on one project in an account other projects share: an IAM user
# that can only assume a role, with MFA, that reaches the project's tagged
# instances (SSM), its log groups, and its ECS and ECR, plus the project's own
# deploy bucket and SSM parameters through extra_policy_json.
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::example-deploy-output", "arn:aws:s3:::example-deploy-output/*"]
  }
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:us-east-1:*:parameter/example/*"]
  }
}

module "collaborator" {
  source             = "../../modules/project-access"
  name               = "example-collaborator"
  project_tag_values = ["example"]
  log_group_prefixes = ["/example/", "/ecs/example-"]
  user_name          = "collaborator"
  extra_policy_json  = data.aws_iam_policy_document.deploy.json
}

output "switch_role_url" {
  value = module.collaborator.switch_role_url
}
