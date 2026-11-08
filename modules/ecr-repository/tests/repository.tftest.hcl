# Repository settings and the lifecycle policy each input produces. Plans
# only, against a mocked provider: no AWS account is touched.

mock_provider "aws" {}

variables {
  name = "demo-app"
}

run "defaults_immutable_scanned_aes_keep_last_ten" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.name == "demo-app" && aws_ecr_lifecycle_policy.this.repository == "demo-app"
    error_message = "The repository and its lifecycle policy must use the given name."
  }
  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "Tags must be immutable by default, so a pushed tag cannot be repointed."
  }
  assert {
    condition     = aws_ecr_repository.this.force_delete == false
    error_message = "By default destroy must not delete a repository that still holds images."
  }
  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push == true
    error_message = "Images must be scanned on push."
  }
  assert {
    condition     = length(aws_ecr_repository.this.encryption_configuration) == 0
    error_message = "Without kms_key_arn the repository must keep the default AES-256 encryption."
  }
  assert {
    condition     = aws_ecr_repository.this.tags == tomap({ Name = "demo-app" })
    error_message = "The repository must carry a Name tag."
  }
  assert {
    condition = jsondecode(aws_ecr_lifecycle_policy.this.policy) == {
      rules = [{
        rulePriority = 1
        description  = "Keep last 10 images"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
        action       = { type = "expire" }
      }]
    }
    error_message = "By default the lifecycle policy must keep only the newest 10 images, and nothing else."
  }
}

run "settings_pass_through" {
  command = plan

  variables {
    image_tag_mutability = "MUTABLE"
    force_delete         = true
    tags                 = { Team = "web" }
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "MUTABLE"
    error_message = "image_tag_mutability must reach the repository."
  }
  assert {
    condition     = aws_ecr_repository.this.force_delete == true
    error_message = "force_delete must reach the repository."
  }
  assert {
    condition     = aws_ecr_repository.this.tags == tomap({ Name = "demo-app", Team = "web" })
    error_message = "Caller tags must be added alongside the Name tag."
  }
}

run "kms_key_switches_encryption_to_kms" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/mock"
  }

  assert {
    condition     = length(aws_ecr_repository.this.encryption_configuration) == 1
    error_message = "kms_key_arn must add an encryption configuration."
  }
  assert {
    condition = (
      aws_ecr_repository.this.encryption_configuration[0].encryption_type == "KMS" &&
      aws_ecr_repository.this.encryption_configuration[0].kms_key == "arn:aws:kms:us-east-1:111111111111:key/mock"
    )
    error_message = "Images must be encrypted with the given customer managed key."
  }
}

run "untagged_expiry_adds_a_first_rule" {
  command = plan

  variables {
    max_image_count      = 5
    untagged_expire_days = 7
  }

  assert {
    condition = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules == [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 5 images"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 5 }
        action       = { type = "expire" }
      },
    ]
    error_message = "untagged_expire_days must add an untagged-expiry rule at priority 1, ahead of the keep-last rule at priority 2."
  }
}

run "lifecycle_policy_json_replaces_default_rules" {
  command = plan

  variables {
    untagged_expire_days  = 7
    lifecycle_policy_json = "{\"rules\":[]}"
  }

  assert {
    condition     = aws_ecr_lifecycle_policy.this.policy == "{\"rules\":[]}"
    error_message = "A caller-supplied lifecycle policy must be used verbatim, replacing the built-in rules."
  }
}
