# full-stack expects an aliased us-east-1 provider from its caller, so it can
# only be validated through a root module like this one.
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    namecheap = {
      source  = "namecheap/namecheap"
      version = ">= 2.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "namecheap" {}

module "app" {
  source      = "../../../modules/full-stack"
  name        = "example-com"
  domain_name = "example.com"
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
