# DNSSEC: turning it on and off

`route53-zone-security` (and `full-stack` with `enable_dnssec = true`) signs a hosted zone. Signing is only half of
DNSSEC: the parent zone (`.com`, via your registrar) must also publish a DS record that points at the zone's
key-signing key. The order of the two steps matters both ways. A DS record without signing makes the domain fail to
resolve for every validating resolver, which includes most public resolvers.

## Turning it on

1. Apply with `enable_dnssec = true`. Route53 starts signing; nothing changes for resolvers yet.
2. Read the DS record:
   - `terraform output dnssec_ds_record` from a `full-stack` app (or `ds_record` from the module) gives one line.
   - `dnssec_ds_record_fields` gives the parts, for registrars that ask separately.
3. Publish it at the registrar. On Namecheap: *Domain List → Manage → Advanced DNS → DNSSEC*, turn it on and add a
   record with the key tag, algorithm (13, ECDSA P-256), digest type (2, SHA-256) and digest. The Namecheap
   Terraform provider does not manage DS records, so this step is manual.
4. Check, after the parent's TTL (often an hour or two): `dig +dnssec example.com SOA` should show the `ad` flag
   through a validating resolver such as 1.1.1.1, or use an online DNSSEC analyzer.

## Turning it off, or destroying the stack

Do these in order. Skipping ahead breaks resolution until the old DS record expires from caches.

1. Remove the DS record at the registrar.
2. Wait for the parent zone's DS TTL to pass. For `.com` it is a day; waiting 48 hours is safe.
3. Apply with `enable_dnssec = false` (or run `destroy-app`). Route53 stops signing; the KMS key is scheduled for
   deletion after 7 days.

`destroy-app` on a signed zone follows the same rule: remove the DS record and wait before destroying.

## Rotating the key-signing key

KMS cannot rotate asymmetric keys, and the module manages a single key-signing key. Rotating means adding a second
key-signing key, publishing its DS record next to the old one, waiting out the TTL, then removing the old key and DS
record. The module does not automate this; most small zones never need it.
