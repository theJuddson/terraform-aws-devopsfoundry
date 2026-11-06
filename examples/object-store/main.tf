# A bucket for application uploads, encrypted with its own key, with a role
# policy that grants the app the `uploads/` prefix. Scratch files under `tmp/`
# expire after a week.
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

module "key" {
  source = "../../modules/kms-key"
  alias  = "example-uploads"
}

module "bucket" {
  source                 = "../../modules/object-store"
  bucket_name            = "example-app-uploads-123456789012"
  kms_key_arn            = module.key.key_arn
  policy_prefix          = "uploads"
  prefix_expiration_days = { "tmp/" = 7 }
}

resource "aws_iam_policy" "uploads" {
  name   = "example-app-uploads"
  policy = module.bucket.prefix_policy_json
}
