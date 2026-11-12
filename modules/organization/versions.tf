terraform {
  required_version = ">= 1.9.0" # validations that refer to other variables

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
  }
}
