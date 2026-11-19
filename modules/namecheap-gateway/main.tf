# A Lambda that makes DevOpsFoundry's Namecheap API calls from a fixed address.
# Namecheap answers only allowlisted IPs, and a laptop's address changes from one
# network to the next. The function runs in private subnets whose route to the
# internet is a NAT gateway with an Elastic IP, so every call leaves from that one
# address: allowlist it once at Namecheap.
#
# The API key is an SSM SecureString you create outside Terraform (bin/namecheap
# put-key), so it never reaches Terraform state. The function reads it at run time
# and can do four things only: check access, read a domain's nameservers, set
# them, or reset the domain to Namecheap's default DNS (lambda/handler.py).

data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_subnet" "first" {
  id = var.subnet_ids[0]
}

locals {
  region = lookup(data.aws_region.current, "region", lookup(data.aws_region.current, "name", null))
  # A name like /devopsfoundry/namecheap/api-key, with or without the leading slash.
  parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(var.api_key_parameter, "/")}"
}

data "archive_file" "code" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.root}/.terraform/tmp/${var.name}.zip"
}

resource "aws_security_group" "fn" {
  name        = var.name
  description = "Namecheap gateway: HTTPS out only, nothing in"
  vpc_id      = data.aws_subnet.first.vpc_id

  # No inbound rules: the function is only ever invoked through the Lambda API.
  ingress = []

  egress {
    description = "HTTPS to the Namecheap API and SSM, through the NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = var.name })
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "fn" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# Network interfaces in the VPC, and logs.
resource "aws_iam_role_policy_attachment" "vpc" {
  role       = aws_iam_role.fn.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "key" {
  statement {
    sid       = "ReadTheApiKey"
    actions   = ["ssm:GetParameter"]
    resources = [local.parameter_arn]
  }
  dynamic "statement" {
    for_each = var.api_key_kms_key_arn == null ? [] : [1]
    content {
      sid       = "DecryptTheApiKey"
      actions   = ["kms:Decrypt"]
      resources = [var.api_key_kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["ssm.${local.region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "key" {
  name   = "${var.name}-api-key"
  role   = aws_iam_role.fn.id
  policy = data.aws_iam_policy_document.key.json
}

resource "aws_cloudwatch_log_group" "fn" {
  #checkov:skip=CKV_AWS_158:CloudWatch default encryption unless log_kms_key_arn is set; the logs hold action names and domains only
  #checkov:skip=CKV_AWS_338:Retention is log_retention_days
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn
  tags              = var.tags
}

resource "aws_lambda_function" "fn" {
  #checkov:skip=CKV_AWS_116:Called synchronously by bin/namecheap and Terraform, which see every failure; a dead-letter queue would hold nothing
  #checkov:skip=CKV_AWS_50:X-Ray adds cost for a function called a few times a year
  #checkov:skip=CKV_AWS_173:The environment holds no secret: the API key is read from SSM at run time
  #checkov:skip=CKV_AWS_272:The code is one file shipped in this module and pinned by its hash
  #checkov:skip=CKV_AWS_115:Reserved concurrency is reserved_concurrency, null by default so a small account's unreserved pool is not cut below its minimum
  function_name                  = var.name
  description                    = "DevOpsFoundry Namecheap gateway: nameserver calls from a fixed IP"
  role                           = aws_iam_role.fn.arn
  runtime                        = "python3.13"
  architectures                  = ["arm64"]
  handler                        = "handler.handler"
  filename                       = data.archive_file.code.output_path
  source_code_hash               = data.archive_file.code.output_base64sha256
  timeout                        = 60
  memory_size                    = 128
  reserved_concurrent_executions = var.reserved_concurrency

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.fn.id]
  }

  environment {
    variables = {
      API_KEY_PARAMETER = var.api_key_parameter
      API_USER          = var.api_user
      USER_NAME         = coalesce(var.user_name, var.api_user)
      CLIENT_IP         = var.client_ip
      SANDBOX           = tostring(var.sandbox)
      ALLOWED_DOMAINS   = join(",", var.allowed_domains)
    }
  }

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy_attachment.vpc, aws_iam_role_policy.key]
}
