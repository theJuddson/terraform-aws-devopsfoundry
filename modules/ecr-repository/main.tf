# One ECR repository with scan on push and a lifecycle policy that keeps the
# newest images. container-service uses this module for its own repository.

locals {
  default_rules = concat(
    var.untagged_expire_days == null ? [] : [{
      rulePriority = 1
      description  = "Expire untagged images after ${var.untagged_expire_days} days"
      selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = var.untagged_expire_days }
      action       = { type = "expire" }
    }],
    [{
      rulePriority = var.untagged_expire_days == null ? 1 : 2
      description  = "Keep last ${var.max_image_count} images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.max_image_count }
      action       = { type = "expire" }
    }],
  )
}

resource "aws_ecr_repository" "this" {
  #checkov:skip=CKV_AWS_136:AES-256 is the default; pass kms_key_arn for a customer managed key
  #checkov:skip=CKV_AWS_51:Tag mutability is a variable; the default is IMMUTABLE and container-service keeps MUTABLE for its :latest flow
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  dynamic "encryption_configuration" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      encryption_type = "KMS"
      kms_key         = var.kms_key_arn
    }
  }

  tags = merge({ Name = var.name }, var.tags)
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = var.lifecycle_policy_json != null ? var.lifecycle_policy_json : jsonencode({ rules = local.default_rules })
}
