# Contributing

Issues and pull requests are welcome.

## Rules for changes

- **No surprise infrastructure changes.** A consumer who moves to a new minor release must see no plan changes. If a
  resource moves, add `moved` blocks. New behavior goes behind a variable whose default keeps the old behavior.
  Breaking changes wait for a major release and are listed in `CHANGELOG.md`.
- **Generic only.** Modules must not name a particular product, company, domain or AWS account. Examples use
  `example.com` and account `123456789012`.
- **Every module has** `versions.tf`, `variables.tf` (each with a description and type), `outputs.tf` (each with a
  description), a `README.md` with terraform-docs tables, and an example under `examples/`.

## Checks

Install terraform, tflint, terraform-docs and checkov (`pip install checkov==3.4.3`; the Homebrew build skips the
graph checks), then run:

```sh
bin/check-modules             # fmt, validate, tflint, terraform test, checkov; no AWS calls
bin/check-compat v1.2.0       # offline proof that container-service plans no change
terraform-docs -c .terraform-docs.yml modules/<name>   # refresh a module's README tables
```

Module tests live in `modules/<name>/tests/*.tftest.hcl`. They only plan, against mocked providers, and check what each
input and mode creates or rejects; `modules/full-stack/tests/modes.tftest.hcl` shows the pattern. A change to a module's
behaviour should come with a test that fails without it. Run one module's tests with `terraform test` in its directory.

The `bin/` scripts are tested in `tests/cli` (`tests/cli/run.sh`), against stub `aws`, `terraform`, `docker`, `dig`
and `curl` commands that record their calls; no account or registrar is touched. Keep the scripts working on
macOS's bash 3.2: no associative arrays or `mapfile`, and guard empty arrays under `set -u`.

CI runs the same checks on every pull request. New checkov findings must be fixed or suppressed in the code with a
`#checkov:skip=<id>:<reason>` comment and added to `docs/checkov-accepted.md`.

## Commits and releases

One logical change per commit. Releases are git tags (`vMAJOR.MINOR.PATCH`) made after the pull request is merged;
add an entry to `CHANGELOG.md` in the same pull request. Pushing the tag creates the GitHub Release, with that
entry as its notes (`.github/workflows/release.yml`); preview them with `bin/release-notes <tag>`.

By contributing you agree that your contribution is licensed under the Apache License 2.0.
