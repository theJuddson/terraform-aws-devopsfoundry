# SMTP key rotation (#22): two IAM key slots, so a new key is published while
# the previous one still works. Applied against a mocked AWS provider, so each
# key gets its own made-up id and the secret can be checked against it.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_resource "aws_ses_domain_dkim" {
    defaults = { dkim_tokens = ["tok1", "tok2", "tok3"] }
  }
  mock_resource "aws_ses_domain_identity" {
    defaults = { arn = "arn:aws:ses:us-east-1:111111111111:identity/example.com" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:111111111111:secret:demo/ses/smtp-AbCdEf" }
  }
}

variables {
  name            = "demo"
  sender_domain   = "example.com"
  sender_zone_id  = "Z123EXAMPLE"
  dmarc_rua_email = "dmarc@example.com"
}

run "defaults_one_active_key_in_slot_a" {
  command = apply

  assert {
    condition     = keys(aws_iam_access_key.ses_smtp) == ["a"] && aws_iam_access_key.ses_smtp["a"].status == "Active"
    error_message = "Before any rotation there is one Active key, in slot a."
  }
  assert {
    condition     = jsondecode(aws_secretsmanager_secret_version.smtp.secret_string).username == aws_iam_access_key.ses_smtp["a"].id
    error_message = "The secret must hold slot a's key."
  }
  assert {
    condition     = output.smtp_keys == { active = "a", status = { a = "Active" } }
    error_message = "smtp_keys must report slot a as the only, Active, key."
  }
}

# Publish: the new key is in the secret, the previous one still works.
run "publishing_b_keeps_a_active" {
  command = apply

  variables {
    smtp_active_key  = "b"
    smtp_standby_key = "active"
  }

  assert {
    condition     = aws_iam_access_key.ses_smtp["a"].status == "Active" && aws_iam_access_key.ses_smtp["b"].status == "Active"
    error_message = "Until tasks restart, both keys must work."
  }
  assert {
    condition     = jsondecode(aws_secretsmanager_secret_version.smtp.secret_string).username == aws_iam_access_key.ses_smtp["b"].id
    error_message = "The secret must hold the active slot's key."
  }
  assert {
    condition     = jsondecode(aws_secretsmanager_secret_version.smtp.secret_string).password == aws_iam_access_key.ses_smtp["b"].ses_smtp_password_v4
    error_message = "The secret's password must be the active key's SMTP password."
  }
}

# Retire: the previous key stops working but stays, so there is a way back.
run "retiring_makes_the_standby_inactive" {
  command = apply

  variables {
    smtp_active_key  = "b"
    smtp_standby_key = "inactive"
  }

  assert {
    condition     = output.smtp_keys == { active = "b", status = { a = "Inactive", b = "Active" } }
    error_message = "After retiring, slot a must be Inactive and slot b Active."
  }
  assert {
    condition     = jsondecode(aws_secretsmanager_secret_version.smtp.secret_string).username == aws_iam_access_key.ses_smtp["b"].id
    error_message = "Retiring must not change the secret."
  }
}

run "the_next_rotation_goes_back_to_a" {
  command = apply

  variables {
    smtp_active_key  = "a"
    smtp_standby_key = "inactive"
  }

  assert {
    condition     = output.smtp_keys == { active = "a", status = { a = "Active", b = "Inactive" } }
    error_message = "The active slot must be Active whichever it is."
  }
}

run "slot_b_needs_a_standby" {
  command = plan

  variables {
    smtp_active_key = "b"
  }

  expect_failures = [aws_iam_access_key.ses_smtp]
}

run "unknown_slots_are_refused" {
  command = plan

  variables {
    smtp_active_key  = "c"
    smtp_standby_key = "retired"
  }

  expect_failures = [var.smtp_active_key, var.smtp_standby_key]
}
