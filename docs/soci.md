# Lazy loading images with SOCI

Fargate pulls a container's whole image before starting it. With a SOCI (Seekable OCI) index alongside the image,
Fargate starts the container straight away and fetches files as they are read. For images of a gigabyte or more this
cuts start time sharply. Fargate uses an index automatically when it finds one; there is no task definition setting.

## Building an index

`bin/soci-index` takes an image that is already in ECR, builds an index with `soci convert` (index manifest v2) and
pushes the indexed image under a new tag, by default `<tag>-soci`:

```sh
bin/soci-index 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-job:git-abc123
# -> 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-job:git-abc123-soci
```

Point the task definition (for example `task_definitions.<key>.image` in `task-runner`) at the `-soci` tag.

It needs Linux with containerd, `nerdctl`, `soci` 0.10 or later and the AWS CLI, so run it in CI (a Linux GitHub
runner works) or on a build host, not on macOS. It has not been run against ECR from this repository's checks.

## Pushing multi-platform images

Push with every platform: `docker push --all-platforms` (Docker's containerd image store) or
`nerdctl push --all-platforms`. A multi-platform image index also lists attestation manifests (provenance and SBOM
from BuildKit). Pushing only the local platform leaves those manifests missing, and the push or the later SOCI
conversion fails. `bin/soci-index` passes `--all-platforms` on pull and push for the same reason. Alternatively
build with `--provenance=false --sbom=false` so there are no attestation manifests.

## Repository settings

The `ecr-repository` module defaults to immutable tags, which suits this flow: every build and every index gets its
own tag. Keep `max_image_count` high enough to hold both the image and its `-soci` twin for every tag you still run.
