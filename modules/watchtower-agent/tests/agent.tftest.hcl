# The agent's user data and the one policy it needs: the group key parameter,
# and the release object only when the release is in S3. Plans only, against a
# mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  collector_url       = "https://watch.example.com"
  release_url         = "s3://artifacts/watchtower/v0.1.0/watchtower-agent_v0.1.0_linux_arm64.tar.gz"
  release_sha256      = "dd2a273cb15ef5e5a2e14e8bc10a08f1b83e06bd11c57fc36b9e5b0c885b96f4"
  group_key_parameter = "/myapp/watchtower/group-key/hosts"
}

run "s3_release" {
  command = plan

  assert {
    condition = (one([for s in data.aws_iam_policy_document.agent.statement : s.resources if s.sid == "ReadTheGroupKey"])
    == toset(["arn:aws:ssm:us-east-1:111111111111:parameter/myapp/watchtower/group-key/hosts"]))
    error_message = "The hosts may read only the one group key parameter."
  }
  assert {
    condition = (one([for s in data.aws_iam_policy_document.agent.statement : s.resources if s.sid == "ReadTheRelease"])
    == toset(["arn:aws:s3:::artifacts/watchtower/v0.1.0/watchtower-agent_v0.1.0_linux_arm64.tar.gz"]))
    error_message = "The hosts may read only the release object."
  }
  assert {
    condition     = strcontains(output.user_data, "signed s3 -o \"$work/agent.tar.gz\" \"https://artifacts.s3.us-east-1.amazonaws.com/watchtower/v0.1.0/watchtower-agent_v0.1.0_linux_arm64.tar.gz\"")
    error_message = "An s3:// release is fetched signed, from the bucket's regional endpoint."
  }
  assert {
    condition     = strcontains(output.user_data, "dd2a273cb15ef5e5a2e14e8bc10a08f1b83e06bd11c57fc36b9e5b0c885b96f4  $work/agent.tar.gz\" | sha256sum -c -")
    error_message = "The tarball is checked against release_sha256 before it is unpacked."
  }
}

run "https_release" {
  command = plan

  variables {
    release_url = "https://example.com/watchtower-agent_v0.1.0_linux_amd64.tar.gz"
    source_name = "web-1"
  }

  assert {
    condition     = length([for s in data.aws_iam_policy_document.agent.statement : s if s.sid == "ReadTheRelease"]) == 0
    error_message = "An https release needs no S3 access."
  }
  assert {
    condition     = strcontains(output.user_data, "curl -fsSL --retry 5 -o \"$work/agent.tar.gz\" \"https://example.com/watchtower-agent_v0.1.0_linux_amd64.tar.gz\"") && !strcontains(output.user_data, "signed s3")
    error_message = "An https release is fetched unsigned."
  }
  assert {
    condition     = strcontains(output.user_data, "WATCHTOWER_SOURCE=\"web-1\"")
    error_message = "source_name reaches the install."
  }
}

run "refuses_plain_http_collector" {
  command = plan
  variables {
    collector_url = "http://watch.example.com"
  }
  expect_failures = [var.collector_url]
}
