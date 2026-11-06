# Security

## Reporting a vulnerability

Please report security problems privately through GitHub: **Security → Report a vulnerability** on this repository.
Do not open a public issue. You should get a reply within a week.

In scope: anything in this repository that would make infrastructure built with it less secure than its
documentation says, for example an IAM policy broader than described, a resource left publicly reachable, or a
secret written to state, logs or user data.

## Supported versions

Only the latest release tag gets fixes.

## What the modules do and do not promise

The README of each module says what its IAM policies allow. Two limits are stated there and repeated here:
`kms-key` and `shared-filesystem` let an app role tag resources it creates, and AWS authorizes those create-time tags
without a resource-tag condition, so an untagged key or access point elsewhere in the same account could be claimed
by that role. Run such apps in their own AWS account or give the role a permissions boundary.

Accepted static-analysis findings are listed in `docs/checkov-accepted.md`.
