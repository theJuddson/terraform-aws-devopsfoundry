# Provenance

## Decision

On 2026-11-06 the owner, Juddson Sharp, confirmed that he holds the rights to publish all of this repository's code,
including the parts adapted from an earlier private infrastructure project, and chose to publish it under the
Apache License 2.0 (`LICENSE`, `NOTICE`).

Before publication the owner asked that references to that earlier project be removed and that the repository be
published without its private history.

## What was adapted

These modules began as adaptations of modules from that earlier project and were then generalized (generic names,
optional components, teardown-friendly defaults, shared-platform and existing-zone modes). As of 2026-11-06, the share
of each module's substantive lines still matching the earlier code was:

| Module | Still matching |
| --- | --- |
| route53-records, route53-zone, static-site | about 80–95% |
| database, cache, acm-cert | about 60–90% |
| networking, email | about 65–70% |
| container-service | about 35–40% |

`full-stack`, `shared-platform`, `namecheap-ns`, the `bin/` scripts, `lib/common.sh` and the templates were written
for this repository or have been rewritten (under about 25%, which is the level shared Terraform idiom alone
produces). The modules added in v1.2.0 (`object-store`, `kms-key`, `shared-filesystem`, `task-runner`,
`ecr-repository`, `ec2-host`, `budget-alarm`) and the check scripts were written from scratch.
