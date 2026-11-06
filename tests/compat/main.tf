# Calls container-service with fixed inputs. bin/check-compat plans it against
# a state written by an older release to prove the upgrade changes nothing.
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "offline"
  secret_key                  = "offline"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

module "svc" {
  source                = "./mod/container-service"
  name                  = "demo"
  domain_name           = "example.com"
  zone_id               = "Z123"
  certificate_arn       = "arn:aws:acm:us-east-1:111111111111:certificate/abc"
  vpc_id                = "vpc-1"
  public_subnet_ids     = ["subnet-a"]
  private_subnet_ids    = ["subnet-b"]
  alb_security_group_id = "sg-1"
  api_security_group_id = "sg-2"
}
