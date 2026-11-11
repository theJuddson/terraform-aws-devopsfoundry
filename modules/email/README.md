# email

An SES sending domain: identity, DKIM, DMARC, optional custom MAIL FROM, and an IAM user whose SMTP credentials are stored in a Secrets Manager secret.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_access_key.ses_smtp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_access_key) | resource |
| [aws_iam_user.ses_smtp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user) | resource |
| [aws_iam_user_policy.ses_send](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy) | resource |
| [aws_route53_record.dkim](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.dmarc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.dmarc_report_auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.mail_from_mx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.mail_from_spf](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.ses_verification](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_secretsmanager_secret.smtp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.smtp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_ses_domain_dkim.sender](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ses_domain_dkim) | resource |
| [aws_ses_domain_identity.sender](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ses_domain_identity) | resource |
| [aws_ses_domain_identity_verification.sender](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ses_domain_identity_verification) | resource |
| [aws_ses_domain_mail_from.sender](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ses_domain_mail_from) | resource |
| [aws_ses_identity_notification_topic.bounce](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ses_identity_notification_topic) | resource |
| [aws_ses_identity_notification_topic.complaint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ses_identity_notification_topic) | resource |
| [aws_sns_topic.ses_notifications](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.ses_notifications](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.ses_notifications_topic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ses_send](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| dmarc\_rua\_email | DMARC aggregate-report address (rua=mailto:) | `string` | n/a | yes |
| name | Resource-name prefix (app slug) | `string` | n/a | yes |
| sender\_domain | Domain to send mail from (SES identity) | `string` | n/a | yes |
| sender\_zone\_id | Route53 hosted zone ID for sender\_domain | `string` | n/a | yes |
| aws\_region | Region (the SES SMTP endpoint is region-scoped) | `string` | `"us-east-1"` | no |
| dmarc\_policy | DMARC policy applied to the domain + subdomains: none \| quarantine \| reject | `string` | `"none"` | no |
| dmarc\_report\_zone\_id | Route53 zone of dmarc\_rua\_email's domain, when that is another domain: creates the <sender\_domain>.\_report.\_dmarc.<report domain> TXT record receivers need before they send reports there. Empty = create nothing; the dmarc\_report\_authorization output gives the record to add by hand. | `string` | `""` | no |
| enable\_notifications | Create an SNS topic wired to SES Bounce/Complaint (subscription left to the caller) | `bool` | `false` | no |
| kms\_key\_arn | Customer managed KMS key for the SMTP credentials secret. null (default) = the AWS-managed key. Whatever reads the secret also needs kms:Decrypt on it. | `string` | `null` | no |
| mail\_from\_subdomain | Label for a custom MAIL FROM subdomain (e.g. 'mail' -> mail.<sender\_domain>), giving SPF alignment. Empty = SES default (amazonses.com), DKIM-only DMARC alignment. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| dmarc\_report\_authorization | When dmarc\_rua\_email is on another domain: the TXT record that domain must publish before receivers send it reports, and whether this module created it (dmarc\_report\_zone\_id). Null when no record is needed. |
| notifications\_topic\_arn | SNS topic ARN for SES bounce/complaint (null when disabled) |
| smtp\_host | n/a |
| smtp\_secret\_arn | Secrets Manager ARN holding SMTP creds (JSON: username/password/host/port) |
<!-- END_TF_DOCS -->
