# An organization run from the account this is applied in, a member account for
# one venture, and IAM Identity Center access to it: its owner as administrator
# of that account only, and the organization's owner as administrator of it too.
# Identity Center must be turned on once in the console before the first apply.
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
  region = "us-east-1" # Identity Center's region
}

module "org" {
  source = "../../modules/organization"
  accounts = {
    example-venture = { email = "owner+example-venture@example.com", tags = { project = "example-venture" } }
  }
}

module "access" {
  source = "../../modules/identity-center"
  users = {
    owner   = { given_name = "Org", family_name = "Owner", email = "owner@example.com" }
    partner = { given_name = "Venture", family_name = "Owner", email = "partner@example.com" }
  }
  permission_sets = {
    AdministratorAccess = { managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"], session_duration = "PT8H" }
  }
  assignments = [
    { permission_set = "AdministratorAccess", account_id = module.org.account_ids["example-venture"], user = "partner" },
    { permission_set = "AdministratorAccess", account_id = module.org.account_ids["example-venture"], user = "owner" },
  ]
}

# Build inside the member account through the role AWS made there.
provider "aws" {
  alias  = "venture"
  region = "us-east-1"
  assume_role {
    role_arn = module.org.member_admin_role_arns["example-venture"]
  }
}

# A budget alarm inside the venture's own account.
module "venture_budget" {
  source          = "../../modules/budget-alarm"
  providers       = { aws = aws.venture }
  name            = "example-venture-monthly"
  monthly_limit   = 300
  email_addresses = ["owner@example.com"]
}
