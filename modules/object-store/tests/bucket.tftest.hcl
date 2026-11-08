# The bucket's fixed protections, its optional pieces (access logging, prefix
# expiry rules, customer managed key) and the prefix grant policy rendered for
# app roles. Plans only, against a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  # The policy documents name the bucket ARN; knowing it at plan lets them be
  # read, so their statements can be checked.
  mock_resource "aws_s3_bucket" {
    override_during = plan
    defaults = {
      arn = "arn:aws:s3:::demo-bucket"
      id  = "demo-bucket"
    }
  }
}

variables {
  bucket_name = "demo-bucket"
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "demo-bucket" && aws_s3_bucket.this.force_destroy == false
    error_message = "The bucket must use bucket_name and refuse destroy while it holds objects."
  }
  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "No access logging without access_log_bucket."
  }
  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1
    error_message = "By default only the noncurrent-versions lifecycle rule exists."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].noncurrent_days == 30 && aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Old versions must expire after 30 days and stale multipart uploads after 7."
  }
  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be on."
  }
  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "Every public-access block must be on."
  }
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "The bucket must default to SSE-KMS."
  }
  assert {
    condition     = data.aws_iam_policy_document.bucket.statement[0].effect == "Deny" && one(data.aws_iam_policy_document.bucket.statement[0].condition).values == tolist(["false"])
    error_message = "The bucket policy must refuse requests not made over TLS."
  }
  assert {
    condition     = data.aws_iam_policy_document.prefix.statement[1].resources == toset(["arn:aws:s3:::demo-bucket/*"]) && one(data.aws_iam_policy_document.prefix.statement[0].condition).values == tolist(["*"])
    error_message = "An empty policy_prefix must grant the whole bucket."
  }
  assert {
    condition     = contains(data.aws_iam_policy_document.prefix.statement[1].actions, "s3:PutObject") && contains(data.aws_iam_policy_document.prefix.statement[1].actions, "s3:DeleteObject")
    error_message = "The prefix grant must allow writes and deletes unless read-only."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.prefix.statement) == 2
    error_message = "Without a customer managed key the grant must carry no KMS statement."
  }
}

run "access_log_bucket_turns_on_logging" {
  command = plan

  variables {
    access_log_bucket = "demo-logs"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 1 && aws_s3_bucket_logging.this[0].target_bucket == "demo-logs" && aws_s3_bucket_logging.this[0].target_prefix == "demo-bucket/"
    error_message = "access_log_bucket must send logs there under the bucket's name."
  }
}

run "prefix_expiration_adds_a_rule_per_prefix" {
  command = plan

  variables {
    prefix_expiration_days      = { "tmp/" = 7, "cache/thumbs/" = 30 }
    noncurrent_versions_to_keep = 3
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 3
    error_message = "Each prefix in prefix_expiration_days must get its own rule."
  }
  # Dynamic rules follow the map's key order: "cache/thumbs/", then "tmp/".
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[1].id == "expire-cache-thumbs" && aws_s3_bucket_lifecycle_configuration.this.rule[2].id == "expire-tmp"
    error_message = "Prefix rules must be named after their prefix."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[1].filter[0].prefix == "cache/thumbs/" && aws_s3_bucket_lifecycle_configuration.this.rule[2].filter[0].prefix == "tmp/"
    error_message = "Each prefix rule must apply only to its prefix."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[1].expiration[0].days == 30 && aws_s3_bucket_lifecycle_configuration.this.rule[2].expiration[0].days == 7
    error_message = "Each prefix must expire after its own number of days."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].newer_noncurrent_versions == 3
    error_message = "noncurrent_versions_to_keep must reach the lifecycle rule."
  }
}

run "policy_prefix_limits_grant_and_trims_slashes" {
  command = plan

  variables {
    policy_prefix = "/uploads/"
  }

  assert {
    condition     = data.aws_iam_policy_document.prefix.statement[1].resources == toset(["arn:aws:s3:::demo-bucket/uploads/*"])
    error_message = "Object access must be limited to the prefix, with stray slashes trimmed."
  }
  assert {
    condition     = one(data.aws_iam_policy_document.prefix.statement[0].condition).values == tolist(["uploads/*", "uploads"])
    error_message = "Listing must be limited to the prefix."
  }
}

run "read_only_grant_with_customer_key" {
  command = plan

  variables {
    policy_read_only = true
    kms_key_arn      = "arn:aws:kms:us-east-1:111111111111:key/mock"
  }

  assert {
    condition     = data.aws_iam_policy_document.prefix.statement[1].actions == toset(["s3:GetObject", "s3:GetObjectVersion"])
    error_message = "A read-only grant must not allow writes or deletes."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.prefix.statement) == 3 && data.aws_iam_policy_document.prefix.statement[2].actions == toset(["kms:Decrypt"]) && data.aws_iam_policy_document.prefix.statement[2].resources == toset(["arn:aws:kms:us-east-1:111111111111:key/mock"])
    error_message = "A read-only grant on a customer key must allow only Decrypt on that key."
  }
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).kms_master_key_id == "arn:aws:kms:us-east-1:111111111111:key/mock"
    error_message = "kms_key_arn must become the bucket's default key."
  }
}

run "writable_grant_with_customer_key_can_generate_data_keys" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/mock"
  }

  assert {
    condition     = data.aws_iam_policy_document.prefix.statement[2].actions == toset(["kms:Decrypt", "kms:GenerateDataKey"])
    error_message = "A writable grant on a customer key must allow GenerateDataKey for uploads."
  }
}

run "extra_bucket_policy_documents_are_merged" {
  command = plan

  variables {
    extra_bucket_policy_documents = ["{\"Version\":\"2012-10-17\",\"Statement\":[]}"]
  }

  assert {
    condition     = data.aws_iam_policy_document.bucket.source_policy_documents == tolist(["{\"Version\":\"2012-10-17\",\"Statement\":[]}"])
    error_message = "Extra bucket policy documents must be merged into the bucket policy."
  }
}
