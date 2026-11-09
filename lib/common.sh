#!/usr/bin/env bash
# ─────────────────────────────────────────────
# lib/common.sh — shared helpers for DevOpsFoundry bin/ scripts.
# Sourced, not executed. No `set -e` here (caller owns that);
# uses explicit `die` for fatal errors.
# ─────────────────────────────────────────────

# Resolve repo root regardless of where a bin/ script is invoked from.
DF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DF_LOG_DIR="$DF_ROOT/logs"
DF_LOG_FILE="$DF_LOG_DIR/devopsfoundry.log"
mkdir -p "$DF_LOG_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${YELLOW}→${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
step() { echo -e "${BLUE}▶${NC} $1"; }

log() {
  local level="$1" msg="$2" ts account
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
  echo "$ts | ${DF_SCRIPT_NAME:-devopsfoundry} | $level | account=$account | $msg" >> "$DF_LOG_FILE"
}

die() {
  echo -e "${RED}✗${NC} $1" >&2
  log "ERROR" "${1//$'\n'/ }"
  exit 1
}

# Load .env if present so NAMECHEAP_* / AWS_PROFILE are exported.
df_load_env() {
  if [[ -f "$DF_ROOT/.env" ]]; then
    set -a; # shellcheck disable=SC1091
    source "$DF_ROOT/.env"; set +a
  fi
}

# Best-effort public IPv4 detection (for the Namecheap whitelist check).
df_detect_ip() {
  curl -fsS4 https://ifconfig.me 2>/dev/null \
    || curl -fsS4 https://api.ipify.org 2>/dev/null \
    || echo ""
}

# domain.com -> domain-com  (S3-bucket / resource-name safe slug)
df_slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//'; }

df_site_dir()  { echo "$DF_ROOT/sites/$1"; }
df_state_key() { echo "devopsfoundry/$1/terraform.tfstate"; }

# Assert a domain arg looks like a bare apex domain (no scheme, no path).
df_validate_domain() {
  local d="$1"
  [[ -n "$d" ]] || die "No domain given. Usage: $DF_SCRIPT_NAME <domain> [...]"
  [[ "$d" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || die "Not a bare domain: '$d' (expected e.g. example.com)"
  [[ "$d" != www.* ]] || die "Pass the apex domain (example.com), not www.$d"
}

# Run terraform in a site dir. Usage: df_tf <domain> <args...>
df_tf() { local d="$1"; shift; terraform -chdir="$(df_site_dir "$d")" "$@"; }

# ── App (full-stack) helpers ───────────────────────────
df_app_state_key() { echo "devopsfoundry/app/$1/terraform.tfstate"; }

# Resolve a --config dir to an abspath and assert it's a DevOpsFoundry app root.
df_resolve_config() {
  local c="$1"
  [[ -n "$c" ]] || die "No --config <dir> given (the app's .devopsfoundry directory)"
  [[ -d "$c" ]] || die "Config dir not found: $c"
  c="$(cd "$c" && pwd)"
  [[ -f "$c/main.tf" ]] || die "Not a DevOpsFoundry app root (no main.tf): $c — run new-app first"
  echo "$c"
}

# Run terraform in a config dir. Usage: df_tf_at <config_dir> <args...>
df_tf_at() { local c="$1"; shift; terraform -chdir="$c" "$@"; }

# terraform init that survives a registry or GitHub blip. Usage: df_tf_init <dir> <init args...>
# Retries (after DF_RETRY_DELAYS seconds, default "10 30") only when the error
# looks like a network failure; a configuration error fails at once.
DF_NETWORK_ERRORS='could not query provider registry|failed to retrieve|request failed after|Gateway Timeout|Bad Gateway|Service Unavailable|bad response|[Tt]imeout|timed out|connection reset|connection refused|TLS handshake|no such host|temporary failure in name resolution|unexpected EOF'
df_tf_init() {
  local dir="$1"; shift
  local errfile delay attempt=1
  errfile="$(mktemp)"
  for delay in ${DF_RETRY_DELAYS:-10 30} ""; do
    if terraform -chdir="$dir" init "$@" >/dev/null 2>"$errfile"; then
      rm -f "$errfile"; return 0
    fi
    if [[ -z "$delay" ]] || ! grep -qE "$DF_NETWORK_ERRORS" "$errfile"; then
      cat "$errfile" >&2; rm -f "$errfile"; return 1
    fi
    warn "terraform init hit a network error (attempt $attempt); retrying in ${delay}s"
    sleep "$delay"; attempt=$((attempt + 1))
  done
}

# Value of an uncommented `key = value` line in a .tfvars file (last one wins),
# without quotes or a trailing comment. Empty if unset. Usage: df_tfvar <file> <key>
df_tfvar() {
  awk -v k="$2" '
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
      gsub(/^"|"$/, "", v); val = v
    }
    END { print val }' "$1"
}

# Set `key = value` in a .tfvars file: replaces an uncommented line, else uncomments
# the first `# key =` line, else appends. Usage: df_set_tfvar <file> <key> <value>
df_set_tfvar() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$value" '
    BEGIN { set = 0 }
    { lines[NR] = $0 }
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { live[NR] = 1; has_live = 1 }
    $0 ~ "^[[:space:]]*#[[:space:]]*" k "[[:space:]]*=" && !first_commented { first_commented = NR }
    END {
      for (i = 1; i <= NR; i++) {
        if ((has_live && live[i]) || (!has_live && i == first_commented)) {
          if (!set) { print k " = " v; set = 1 }   # one line, even if the key appeared twice
        } else print lines[i]
      }
      if (!set) print k " = " v
    }' "$file" > "$tmp" && mv "$tmp" "$file"
}
