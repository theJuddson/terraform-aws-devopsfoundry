# watchtower

A [Watchtower](https://github.com/theJuddson/DevOpsWatchtower) collector: the server that takes metrics from
Watchtower agents (hosts, containers, Fargate tasks) and pushes from apps, stores them, runs alarms and serves the
dashboard. One Graviton host from `ec2-host`, about $12 a month on the default `t4g.micro`.

```hcl
module "watchtower" {
  source         = "theJuddson/devopsfoundry/aws//modules/watchtower"
  version        = "~> 1.19"
  name           = "myapp-watchtower"
  subnet_id      = module.networking.public_subnet_ids[0]
  hostname       = "watch.example.com"
  zone_id        = aws_route53_zone.main.zone_id
  release_url    = "s3://my-artifacts/watchtower/v0.1.0/watchtower_v0.1.0_linux_arm64.tar.gz"
  release_sha256 = "<from the release's SHA256SUMS>"

  mail_from        = "watchtower@example.com"
  ses_identity_arn = aws_sesv2_email_identity.main.arn
  rules_yaml       = file("${path.module}/watchtower-rules.yaml")
}
```

## What it builds

- The host: `ec2-host` with no SSH, IMDSv2, an encrypted 40 GiB data volume mounted at `/var/lib/watchtower`
  that outlives the instance, and daily snapshots kept 14 days.
- Port 443 open to `ingress_cidr_blocks` (default everywhere), and nothing else. People, agents and Let's
  Encrypt all come in on 443: the collector gets its certificate with the TLS-ALPN-01 challenge.
- An Elastic IP, so the address, the DNS record and the certificate survive the instance being replaced. With
  `zone_id`, an A record for `hostname`; without it, point the name at the `public_ip` output yourself before
  the first boot finishes, or the certificate request fails until it does.
- An instance role with SSM, plus `s3:GetObject` on the one release object when `release_url` is `s3://`, and
  `ses:SendEmail` as `mail_from` only, on `ses_identity_arn`, when mail is on. No SMTP password exists anywhere.

## The release

At boot the user data downloads `release_url`, refuses it unless its SHA-256 equals `release_sha256`, and runs
the tarball's `install.sh`, which installs the collector and an agent watching the collector's own host. The
default instance is Graviton, so use the `linux_arm64` tarball. Changing the release, the rules or any setting
replaces the instance; the data volume moves to the new one. The install log is `/var/log/watchtower-install.log`.

A private Watchtower repository can't be downloaded anonymously, so copy the tarball to a bucket the account owns
and use an `s3://` URL.

## The first admin

Sign-in is invite-only, with passkeys or email links. Open a shell with the `ssm_session_command` output and run
the `first_admin_command` output with your address. It prints a one-time link; invite everyone else from the
dashboard.

## Deploy tokens

`bin/deploy-app`, `bin/deploy` and `bin/rotate-secret` open a deployment window on the collector when
`WATCHTOWER_URL` is set (see the DevOpsFoundry README, "Deployment windows (Watchtower)"). They authenticate with a
deploy token read from an SSM SecureString. The `deploy_token_command` output mints one on the collector over SSM
and stores it from stdin, so the token never reaches a command line or the terminal. Replace `<name>` (the token's
name in the dashboard) and `<parameter>` (e.g. `/myapp/watchtower/deploy-token`), and add `--overwrite` to replace
an existing parameter. It needs the Session Manager plugin, as `ssm_session_command` does.

## Test deployments

Set `acme_directory` to Let's Encrypt's staging directory
(`https://acme-staging-v02.api.letsencrypt.org/directory`) so test hosts don't spend the production rate limit.
Browsers won't trust the staging certificate.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
| aws | >= 5.60 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 5.60 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| host | ../ec2-host | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eip.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_eip_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip_association) | resource |
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_vpc_security_group_ingress_rule.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| hostname | The collector's public name, such as `watch.example.com`. It gets its certificate for this name. | `string` | n/a | yes |
| name | Name for the host and its resources, such as `myapp-watchtower`. | `string` | n/a | yes |
| release\_sha256 | SHA-256 of the tarball at `release_url`, from the release's SHA256SUMS. The host refuses any other file. | `string` | n/a | yes |
| release\_url | The full Watchtower release tarball (`watchtower_<version>_linux_<arch>.tar.gz`), as `https://...` or `s3://bucket/key`. Its arch must match `instance_type` (arm64 for Graviton). An `s3://` URL gives the host read access to that one object. | `string` | n/a | yes |
| subnet\_id | A public subnet: people, agents and the ACME CA reach the collector on 443. | `string` | n/a | yes |
| acme\_directory | ACME directory URL. Empty for Let's Encrypt production; use `https://acme-staging-v02.api.letsencrypt.org/directory` for a test deployment. | `string` | `""` | no |
| acme\_email | Contact address given to Let's Encrypt (optional). | `string` | `""` | no |
| ami\_ssm\_parameter | Public SSM parameter holding the AMI. Amazon Linux 2023 is what the user data is written for. | `string` | `"/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"` | no |
| data\_volume\_size\_gib | Data volume for the TSDB, its rollups and the auth database. It outlives the instance. | `number` | `40` | no |
| ingress\_cidr\_blocks | IPv4 ranges allowed to reach 443. Agents on Fargate tasks and the ACME CA come from anywhere, so narrow this only if every source is known. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| instance\_type | Instance type. The default is Graviton, so `release_url` must be the arm64 tarball. | `string` | `"t4g.micro"` | no |
| kms\_key\_arn | Customer managed key for the volumes. Null uses the account's default EBS key. | `string` | `null` | no |
| mail\_from | From address for sign-in links, invites and alarm email, sent through SES with the instance role. Null sends no email: invites are then printed links only. | `string` | `null` | no |
| retention\_hours | How long raw 1 s samples are kept. The minute (90 days) and hour (2 years) tiers are fixed. | `number` | `72` | no |
| rules\_yaml | Alarm rules and probes, as Watchtower's YAML. Empty for none. | `string` | `""` | no |
| ses\_identity\_arn | ARN of the verified SES identity (domain or address) `mail_from` belongs to; the role may send as that identity only. Required with `mail_from`. | `string` | `null` | no |
| ses\_region | Region of the SES identity. Null uses the provider's region. | `string` | `null` | no |
| snapshot\_retain\_count | Daily data volume snapshots to keep. | `number` | `14` | no |
| tags | Tags for every resource. | `map(string)` | `{}` | no |
| zone\_id | Route53 zone to put the hostname's A record in. Null leaves DNS to you: point the name at the `public_ip` output. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| collector\_flags | The flags the collector runs with (no secrets: mail goes through the instance role). |
| data\_volume\_id | The data volume that outlives the instance. |
| deploy\_token\_command | Run on your machine to mint a deploy token on the collector (over SSM) and store it as a SecureString, for `WATCHTOWER_TOKEN_PARAMETER`. Replace `<name>` and `<parameter>`; the token never reaches a command line or the terminal. |
| first\_admin\_command | Run in an SSM session on the collector to print a one-time sign-in link for the first admin. |
| instance\_id | The collector's instance. |
| public\_ip | The fixed public address. Point `hostname` at it when `zone_id` is null. |
| role\_name | The instance role, to attach more policies to. |
| security\_group\_id | The collector's security group (443 in, from `ingress_cidr_blocks`). |
| ssm\_session\_command | Opens a shell on the collector, for `watchtower admin` commands. |
| url | The collector's URL: the dashboard for people, and the collector address for agents. |
<!-- END_TF_DOCS -->
