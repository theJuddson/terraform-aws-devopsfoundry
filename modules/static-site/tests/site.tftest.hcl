# The bucket stays private, readable only by this site's CloudFront distribution
# through origin access control. Plans only, against a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_cloudfront_cache_policy" {
    defaults = { id = "658327ea-f89d-4fab-a63d-7e88639e58f6" }
  }
  # Known at plan so the bucket policy and the origin can be checked.
  mock_resource "aws_s3_bucket" {
    override_during = plan
    defaults = {
      id                          = "example-com-site-111111111111"
      arn                         = "arn:aws:s3:::example-com-site-111111111111"
      bucket_regional_domain_name = "example-com-site-111111111111.s3.us-east-1.amazonaws.com"
    }
  }
  mock_resource "aws_cloudfront_distribution" {
    override_during = plan
    defaults        = { arn = "arn:aws:cloudfront::111111111111:distribution/E123EXAMPLE" }
  }
  mock_resource "aws_cloudfront_origin_access_control" {
    override_during = plan
    defaults        = { id = "OAC123EXAMPLE" }
  }
}

variables {
  site_name       = "example-com"
  domain_name     = "example.com"
  bucket_name     = "example-com-site-111111111111"
  certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/abc"
}

run "bucket_blocks_all_public_access" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.site.block_public_acls,
      aws_s3_bucket_public_access_block.site.block_public_policy,
      aws_s3_bucket_public_access_block.site.ignore_public_acls,
      aws_s3_bucket_public_access_block.site.restrict_public_buckets,
    ])
    error_message = "Every public access block setting must be on."
  }
  assert {
    condition     = aws_s3_bucket_versioning.site.versioning_configuration[0].status == "Enabled"
    error_message = "The bucket must be versioned, so a bad deploy can be rolled back."
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.site.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "The bucket must be encrypted at rest."
  }
}

run "only_this_distribution_can_read_the_bucket" {
  command = plan

  assert {
    condition = jsondecode(aws_s3_bucket_policy.site.policy).Statement == [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::example-com-site-111111111111/*"
      Condition = { StringEquals = { "AWS:SourceArn" = "arn:aws:cloudfront::111111111111:distribution/E123EXAMPLE" } }
    }]
    error_message = "The bucket policy must allow only GetObject, only to CloudFront, only from this site's distribution."
  }
}

run "cloudfront_reads_through_signed_origin_access_control" {
  command = plan

  assert {
    condition     = aws_cloudfront_origin_access_control.site.signing_behavior == "always" && aws_cloudfront_origin_access_control.site.origin_access_control_origin_type == "s3"
    error_message = "CloudFront must sign every request to the S3 origin."
  }
  assert {
    condition = alltrue([for o in aws_cloudfront_distribution.site.origin :
      o.origin_access_control_id == "OAC123EXAMPLE" && o.domain_name == "example-com-site-111111111111.s3.us-east-1.amazonaws.com"
    ])
    error_message = "The distribution must reach the bucket through its origin access control."
  }
  assert {
    condition     = one(aws_cloudfront_distribution.site.default_cache_behavior).viewer_protocol_policy == "redirect-to-https"
    error_message = "Viewers must be redirected to HTTPS."
  }
  assert {
    condition     = toset(aws_cloudfront_distribution.site.aliases) == toset(["example.com", "www.example.com"])
    error_message = "The site must serve the apex and www."
  }
  assert {
    condition     = one(aws_cloudfront_distribution.site.viewer_certificate).acm_certificate_arn == var.certificate_arn && one(aws_cloudfront_distribution.site.viewer_certificate).minimum_protocol_version == "TLSv1.2_2021"
    error_message = "The distribution must use the given certificate with TLS 1.2 or later."
  }
}

# A site in a subdomain of an existing zone (blog.example.com) has no www.
run "without_www_serves_only_the_domain" {
  command = plan

  variables {
    domain_name = "blog.example.com"
    include_www = false
  }

  assert {
    condition     = aws_cloudfront_distribution.site.aliases == toset(["blog.example.com"])
    error_message = "With include_www = false the site must serve its own name only."
  }
}
