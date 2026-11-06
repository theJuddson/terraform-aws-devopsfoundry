# A repository for a job image: immutable tags, untagged images gone after a
# week, the newest 30 images kept.
terraform {
  required_version = ">= 1.7.0"
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

module "ecr" {
  source               = "../../modules/ecr-repository"
  name                 = "example-job"
  max_image_count      = 30
  untagged_expire_days = 7
}

output "repository_url" {
  value = module.ecr.repository_url
}
