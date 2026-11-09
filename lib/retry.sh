# shellcheck shell=bash
# retry <command...>: for steps that download (terraform init, tflint --init).
# Runs the command up to three times, waiting 10s and then 30s, so a brief
# registry or GitHub outage doesn't fail a check run. A real error still fails,
# about 40 seconds later.
retry() {
  local attempt=1 delays=(10 30)
  until "$@"; do
    if ((attempt > ${#delays[@]})); then
      echo "retry: giving up after $attempt attempts: $*" >&2
      return 1
    fi
    echo "retry: attempt $attempt failed, trying again in ${delays[attempt - 1]}s: $*" >&2
    sleep "${delays[attempt - 1]}"
    attempt=$((attempt + 1))
  done
}
