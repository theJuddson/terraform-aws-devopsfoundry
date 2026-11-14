# watchtower-agent

Installs the [Watchtower](https://github.com/theJuddson/DevOpsWatchtower) agent on hosts you build, to report to a
collector from the `watchtower` module. It creates nothing: it gives you a user data script and the IAM policy that
script needs.

```hcl
module "watchtower_agent" {
  source              = "theJuddson/devopsfoundry/aws//modules/watchtower-agent"
  version             = "~> 1.19"
  collector_url       = module.watchtower.url
  release_url         = "s3://my-artifacts/watchtower/v0.1.0/watchtower-agent_v0.1.0_linux_arm64.tar.gz"
  release_sha256      = "<from the release's SHA256SUMS>"
  group_key_parameter = "/myapp/watchtower/group-key/hosts"
}

module "server" {
  source              = "theJuddson/devopsfoundry/aws//modules/ec2-host"
  # ...
  user_data           = module.watchtower_agent.user_data
  inline_policy_jsons = { watchtower-agent = module.watchtower_agent.policy_json }
}
```

## The group key

A host enrolls once with a group enrollment key and gets a push token of its own; the key is not used again. Make
one on the collector (`watchtower admin group-key <group> [ttl]`, in an SSM session; the default lasts 30 days)
and store it as a SecureString:

```sh
aws ssm put-parameter --name /myapp/watchtower/group-key/hosts --type SecureString --value file:///dev/stdin
```

Every host enrolled with it lands in that group, which is what alarm rules match on (`groups: [hosts]`). Hosts that
come and go, such as a check fleet, suit a key of their own with a group of their own. A key revoked in the
dashboard stops new enrollments; hosts already enrolled keep their tokens.

## How it runs

The script reads the instance role's credentials from IMDSv2 and signs its S3 and SSM requests with curl
(`--aws-sigv4`), so it needs `curl` and `python3` but not the AWS CLI: it runs on Amazon Linux 2023 and Ubuntu.
It refuses the tarball unless its SHA-256 matches, never puts the key or the role's secret in a command line, and
logs to `/var/log/watchtower-agent-install.log`. The agent runs as its own user; on a host with Docker it gets the
docker group to read container metadata, which is root-equivalent access to the Docker socket (it only sends
GET requests).

Use the tarball for the hosts' arch: `linux_arm64` for Graviton, `linux_amd64` otherwise.

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

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| collector\_url | The Watchtower collector, such as `https://watch.example.com` (the watchtower module's `url` output). | `string` | n/a | yes |
| group\_key\_parameter | Name of the SSM SecureString holding a group enrollment key (`watchtower admin group-key <group>` on the collector). Each host trades it once for a token of its own. | `string` | n/a | yes |
| release\_sha256 | SHA-256 of the tarball at `release_url`, from the release's SHA256SUMS. | `string` | n/a | yes |
| release\_url | The agent tarball (`watchtower-agent_<version>_linux_<arch>.tar.gz`), as `https://...` or `s3://bucket/key`, for the hosts' arch. An `s3://` URL adds read access to that one object to `policy_json`. | `string` | n/a | yes |
| source\_name | The host's name at the collector. Empty uses the hostname, which suits fleets that come and go. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| policy\_json | IAM policy the hosts' role needs: the group key parameter and, for an s3:// release, that object. A parameter under a customer managed KMS key also needs kms:Decrypt on that key. |
| user\_data | A cloud-init shell script that installs and enrolls the agent. Use it as a host's user data, or as one part of a multi-part cloud-init. |
<!-- END_TF_DOCS -->
