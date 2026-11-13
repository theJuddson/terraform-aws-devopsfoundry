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

# Legacy site root inside this checkout. A site's own repo can hold its root in
# .devopsfoundry/ instead, passed as --config (see df_resolve_site_config).
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

# ── Static-site build freshness (bin/deploy) ───────────
# "<mtime> <path>" for every file under the given paths (files or directories),
# skipping .git, node_modules, .devopsfoundry (the deploy config, whose
# .terraform/ changes on every init) and .DS_Store, and the directory <prune> (an
# absolute path, or "" for none). Usage: df_file_mtimes <prune> <path>...
df_file_mtimes() {
  local prune="$1"; shift
  local st=(stat -f '%m %N')
  stat -c %Y / >/dev/null 2>&1 && st=(stat -c '%Y %n')   # GNU stat (Linux)
  local skip=()
  [[ -n "$prune" ]] && skip=(-path "$prune" -prune -o)
  find "$@" ${skip[@]+"${skip[@]}"} \( -name .git -o -name node_modules -o -name .devopsfoundry \) -prune \
    -o -type f ! -name .DS_Store -exec "${st[@]}" {} +
}

# Whether a build directory is at least as new as its source. Prints one line:
#   FRESH <newest source file>   no source file changed after the last build
#   STALE <newest source file>   that file changed after the last build
#   SELF                         the source is the build directory itself
#   EMPTY                        the build directory holds no files
#   MISSING <path>               an extra input path does not exist
# The last build's time is the NEWEST file in the build directory: builds often
# copy static assets with their original times, so the oldest would flag fresh
# builds. Usage: df_build_freshness <build_dir> <src_dir> [extra input path...]
df_build_freshness() {
  local build src i newest_build newest_src
  build="$(cd "$1" && pwd)"; src="$(cd "$2" && pwd)"; shift 2
  [[ "$src" != "$build" ]] || { echo SELF; return 0; }
  newest_build="$(df_file_mtimes "" "$build" | sort -n | tail -1)"
  [[ -n "$newest_build" ]] || { echo EMPTY; return 0; }
  local inputs=("$src")
  for i in "$@"; do
    [[ -e "$i" ]] || { echo "MISSING $i"; return 0; }
    inputs+=("$(cd "$(dirname "$i")" && pwd)/$(basename "$i")")
  done
  newest_src="$(df_file_mtimes "$build" "${inputs[@]}" | sort -n | tail -1)"
  [[ -n "$newest_src" ]] || { echo "FRESH (no source files)"; return 0; }
  if [[ "${newest_src%% *}" -gt "${newest_build%% *}" ]]; then
    echo "STALE ${newest_src#* }"
  else
    echo "FRESH ${newest_src#* }"
  fi
}

# ── Static-site cache headers (bin/deploy) ─────────────
# Whether a file name carries a content hash, so its URL changes whenever its
# content does and browsers may keep it for a year: "index-B4kq9z1x.js",
# "main.3f2a9c1b.css". The hash is the last dash- or dot-separated part of the
# name before the extension: 8 or more letters, digits or underscores, at least
# one of them a digit. "mountains.png" has no digit, so it counts as unhashed.
# Erring that way is cheap (one revalidation per visit); the other way would
# serve a stale file for a year. Usage: df_is_hashed_asset <path>
df_is_hashed_asset() {
  local base="${1##*/}" stem part
  stem="${base%.*}"
  [[ "$stem" != "$base" && -n "$stem" ]] || return 1
  part="${stem##*[.-]}"
  [[ "$part" != "$stem" ]] || return 1
  [[ ${#part} -ge 8 && "$part" =~ ^[A-Za-z0-9_]+$ && "$part" =~ [0-9] ]]
}

# Paths, relative to <build_dir>, of the files whose names carry a content hash
# (see df_is_hashed_asset). Usage: df_hashed_assets <build_dir>
df_hashed_assets() {
  local f
  (cd "$1" && find . -type f ! -name .DS_Store | sed 's|^\./||' | sort) | while IFS= read -r f; do
    if df_is_hashed_asset "$f"; then echo "$f"; fi
  done
}

# Whether a git work tree has uncommitted changes to tracked files under <dir>.
# Untracked files don't count (editor and Finder litter would flag every deploy).
# False outside a git work tree. Usage: df_git_dirty <dir>
df_git_dirty() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [[ -n "$(git -C "$1" status --porcelain --untracked-files=no -- . 2>/dev/null)" ]]
}

# ── Existing Route53 zones (bin/new-site --existing-zone) ──
# Public zones in this account that could serve <domain>: the zone named
# <domain> and each parent of it, closest first. One line each:
# "<name> <id> <record count>", the id without "/hostedzone/". Prints aws's
# error and returns 1 when the zones can't be listed. Usage: df_candidate_zones <domain>
df_candidate_zones() {
  local d out
  d="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  out="$(aws route53 list-hosted-zones --output json 2>&1)" || { echo "$out" >&2; return 1; }
  [[ -n "$out" ]] || return 0
  jq -r --arg d "$d" '.HostedZones[]? | select(.Config.PrivateZone != true)
      | (.Name | ascii_downcase | rtrimstr(".")) as $n
      | select($n == $d or ($d | endswith("." + $n)))
      | "\($n | length) \($n) \(.Id | sub("^/hostedzone/"; "")) \(.ResourceRecordSetCount // 0)"' <<<"$out" \
    | sort -k1,1nr -k3,3 | cut -d' ' -f2-
}

# The --existing-zone argument that names one candidate line unambiguously: its
# name, or its id when another candidate has the same name.
# Usage: df_zone_flag <candidate line> <all candidate lines>
df_zone_flag() {
  local name id; read -r name id _ <<<"$1"
  if [[ "$(awk -v n="$name" '$1 == n' <<<"$2" | wc -l | tr -d ' ')" -gt 1 ]]; then echo "--existing-zone $id"
  else echo "--existing-zone $name"; fi
}

# Whether public DNS (8.8.8.8) answers a zone's own nameservers for its name.
# Sets DF_ZONE_NS and DF_PUBLIC_NS (sorted, lowercase, one per line). True when
# public DNS gives at least one nameserver and every one is the zone's.
# Usage: df_zone_answers_publicly <zone id> <zone name>
df_ns_list() { tr '[:upper:]' '[:lower:]' | sed 's/\.$//' | { grep . || true; } | sort -u; }
df_zone_answers_publicly() {
  DF_ZONE_NS="$(aws route53 get-hosted-zone --id "$1" --output json 2>/dev/null \
    | jq -r '.DelegationSet.NameServers[]?' | df_ns_list)"
  DF_PUBLIC_NS="$(dig +short NS "$2" @8.8.8.8 2>/dev/null | df_ns_list)"
  [[ -n "$DF_ZONE_NS" && -n "$DF_PUBLIC_NS" ]] || return 1
  [[ -z "$(comm -23 <(echo "$DF_PUBLIC_NS") <(echo "$DF_ZONE_NS"))" ]]
}

# ── App (full-stack) helpers ───────────────────────────
# SES account status in a region: PRODUCTION, PENDING (a production access
# review is open), DENIED, SANDBOX, or UNKNOWN when it can't be read.
# Usage: df_ses_account_status <region>
df_ses_account_status() {
  local out
  out="$(aws sesv2 get-account --region "$1" --output json 2>/dev/null)" || { echo UNKNOWN; return 0; }
  jq -r 'if .ProductionAccessEnabled == true then "PRODUCTION"
         else ((.Details.ReviewDetails.Status // "") | ascii_upcase) as $s
              | if $s == "PENDING" then "PENDING" elif $s == "DENIED" then "DENIED" else "SANDBOX" end
         end' <<<"$out" 2>/dev/null || echo UNKNOWN
}

# Whether SES can send as a domain: the identity verified for sending, DKIM
# verified, and its custom MAIL FROM domain (when it has one) verified. Prints
# one line per problem. Returns 0 when ready, 1 when not, 2 when unreadable.
# Usage: df_ses_identity_status <domain> <region>
df_ses_identity_status() {
  local out
  if ! out="$(aws sesv2 get-email-identity --email-identity "$1" --region "$2" --output json 2>&1)"; then
    if grep -q NotFoundException <<<"$out"; then echo "  $1 is not an SES identity in $2 yet"; return 1; fi
    echo "  could not read SES identity $1 in $2 (aws sesv2 get-email-identity)"; return 2
  fi
  jq -r --arg d "$1" '
    (if .VerifiedForSendingStatus == true then empty else "  \($d) is not verified for sending" end),
    (if (.DkimAttributes.Status // "") == "SUCCESS" then empty
     else "  DKIM for \($d) is \(.DkimAttributes.Status // "not set up") (needs its CNAME records in DNS)" end),
    (if (.MailFromAttributes.MailFromDomain // "") == "" or (.MailFromAttributes.MailFromDomainStatus // "") == "SUCCESS" then empty
     else "  MAIL FROM \(.MailFromAttributes.MailFromDomain) is \(.MailFromAttributes.MailFromDomainStatus // "unknown") (needs its MX and SPF records)" end)
  ' <<<"$out" | grep . && return 1
  return 0
}

# One line on what an SES status means for sending. Usage: df_ses_report <region> <status>
df_ses_report() {
  case "$2" in
    PRODUCTION) pass "SES in $1: production access, so mail reaches any address" ;;
    PENDING)    info "SES in $1: sandbox, with a production access review pending (AWS replies within a day or so)" ;;
    DENIED)     warn "SES in $1: sandbox; production access was denied. Reply in the AWS Support case it opened." ;;
    SANDBOX)    warn "SES in $1: sandbox, so mail only reaches verified addresses. To request production access:"
                echo "    bin/email-status --region $1 --request-production --website-url https://<your site> --use-case \"<what you send>\"" ;;
    *)          warn "SES in $1: could not read the account status (aws sesv2 get-account)" ;;
  esac
}

# If an app's DMARC reports go to another domain, says whether the record that
# authorizes it was created or prints the one to add. Silent otherwise, and for
# app roots made before the output existed. Usage: df_dmarc_report <config>
df_dmarc_report() {
  local j
  j="$(df_tf_at "$1" output -json dmarc_report_authorization 2>/dev/null)" || return 0
  [[ -n "$j" && "$j" != null ]] || return 0
  if [[ "$(jq -r .created <<<"$j")" == true ]]; then
    pass "DMARC report authorization record created: $(jq -r .name <<<"$j")"
  else
    warn "DMARC reports go to another domain, which must authorize them or receivers drop them. Add to its DNS:"
    jq -r '"    \(.name)  \(.type)  \"\(.value)\""' <<<"$j"
    echo "  (or set dmarc_report_zone_id in app.tfvars when that zone is in this account)"
  fi
}

# Warn about each app's Redis or SMTP secret (tagged Project=devopsfoundry) whose
# current value is older than DF_SECRET_MAX_AGE_DAYS (default 90). Information
# only: it never fails. Values are never read. Usage: df_secret_age_report <region>
df_secret_age_report() {
  local region="$1" max="${DF_SECRET_MAX_AGE_DAYS:-90}" names name created age app kind old=0
  names="$(aws secretsmanager list-secrets --region "$region" \
      --filters Key=tag-key,Values=Project Key=tag-value,Values=devopsfoundry \
      --query 'SecretList[].Name' --output json 2>/dev/null \
    | jq -r '.[] | select(endswith("/redis/auth") or endswith("/ses/smtp"))' 2>/dev/null)" || return 0
  [[ -n "$names" ]] || return 0
  while IFS= read -r name; do
    created="$(aws secretsmanager list-secret-version-ids --secret-id "$name" --region "$region" --output json 2>/dev/null \
      | jq -r '[.Versions[] | select(.VersionStages | index("AWSCURRENT")) | .CreatedDate][0]
               | if type == "number" then floor else (.[0:19] + "Z" | fromdateiso8601) end' 2>/dev/null)" || continue
    [[ "$created" =~ ^[0-9]+$ ]] || continue
    age=$(( ($(date +%s) - created) / 86400 ))
    if (( age > max )); then
      app="${name%%/*}"; kind=$([[ "$name" == */redis/auth ]] && echo redis || echo smtp)
      warn "$name is $age days old: bin/rotate-secret --config <$app's .devopsfoundry> $kind"
      old=$((old + 1))
    fi
  done <<<"$names"
  (( old > 0 )) || pass "App Redis/SMTP secrets rotated within $max days"
}

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

# Resolve a site's --config dir to an abspath and assert it's a static-site root.
# Usage: df_resolve_site_config <dir>
df_resolve_site_config() {
  local c="$1"
  [[ -n "$c" ]] || die "No --config <dir> given (the site's .devopsfoundry directory)"
  [[ -d "$c" ]] || die "Config dir not found: $c"
  c="$(cd "$c" && pwd)"
  [[ -f "$c/main.tf" && -f "$c/site.env" ]] || die "Not a DevOpsFoundry site root (needs main.tf and site.env): $c"
  [[ -f "$c/terraform.tfvars" ]] || die "Missing $c/terraform.tfvars"
  echo "$c"
}

# A site.env path made absolute against <base> (the repo holding .devopsfoundry/).
# Absolute paths and "" pass through. Usage: df_path_from <base> <path>
df_path_from() {
  case "$2" in ""|/*) echo "$2" ;; *) echo "$1/${2#./}" ;; esac
}

# The state backend an app or site root uses: its own backend.tfvars (e.g. a venture's
# own bucket), else the shared one. Usage: df_app_backend_file <config_dir>
df_app_backend_file() {
  if [[ -f "$1/backend.tfvars" ]]; then echo "$1/backend.tfvars"; else echo "$DF_ROOT/backend.tfvars"; fi
}

# Initialize an app or site root this checkout hasn't initialized yet. .terraform/ is
# gitignored, so a fresh clone or a repo moved to a new path has the app's
# .devopsfoundry/ but no backend or modules, and every plan fails (#45).
# Usage: df_ensure_app_init <config_dir>
df_ensure_app_init() {
  local c="$1" backend
  [[ -f "$c/.terraform/terraform.tfstate" && -f "$c/.terraform/modules/modules.json" ]] && return 0
  backend="$(df_app_backend_file "$c")"
  [[ -f "$backend" ]] || die "No state backend config for $c: add $c/backend.tfvars, or $DF_ROOT/backend.tfvars"
  info "Initializing Terraform in $c (this checkout has no .terraform yet)"
  df_tf_init "$c" -input=false -backend-config="$backend" || die "terraform init failed in $c"
}

# Force a new deployment of an ECS service and wait for it to settle. With the
# circuit breaker on, a failing deployment is rolled back and the service
# settles on the previous one, so "stable" alone isn't success: check the
# deployment we started is still the primary one (#54).
# Returns 0 on success, 1 if update-service failed, 2 if the deployment was
# rolled back or failed, 3 if it didn't settle in time.
# Usage: df_roll_service <cluster> <service> <region>
df_roll_service() {
  local cluster="$1" service="$2" region="$3" started primary state settled=true
  started="$(aws ecs update-service --cluster "$cluster" --service "$service" --force-new-deployment \
    --region "$region" --query "service.deployments[?status=='PRIMARY'] | [0].id" --output text)" || return 1
  aws ecs wait services-stable --cluster "$cluster" --services "$service" --region "$region" || settled=false
  read -r primary state < <(aws ecs describe-services --cluster "$cluster" --services "$service" --region "$region" \
    --query "services[0].deployments[?status=='PRIMARY'] | [0].[id, rolloutState]" --output text 2>/dev/null) || true
  if [[ -n "$started" && "$started" != "None" && -n "$primary" && "$primary" != "$started" ]] || [[ "$state" == FAILED ]]; then
    echo "  deployment ${started:-?} failed; $service is on ${primary:-?} (${state:-unknown})" >&2
    return 2
  fi
  $settled || return 3
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

# Secrets Manager ARNs referenced on uncommented lines of a .tfvars file, one
# per line, without any ":json-key:stage:version" selector.
df_tfvars_secret_arns() {
  grep -vE '^[[:space:]]*#' "$1" \
    | grep -oE 'arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:[A-Za-z0-9/_+=.@-]+' \
    | sort -u
}

# Check each secret exists, isn't scheduled for deletion and has a current
# version. Prints one line per problem and returns 1 if there are any. Only
# describe-secret is called: the value is never read, so neither DevOpsFoundry
# nor the identity running it needs secretsmanager:GetSecretValue (#55).
# (bin/put-secret refuses an empty value, so "has a current version" is the
# check that can still fail.)
df_check_secrets() {
  local arn region bad=0 out deleted current
  for arn in "$@"; do
    region="$(cut -d: -f4 <<<"$arn")"
    if ! out="$(aws secretsmanager describe-secret --secret-id "$arn" --region "$region" \
          --query '[DeletedDate, length(values(VersionIdsToStages || `{}`)[?contains(@, `AWSCURRENT`)])]' \
          --output text 2>/dev/null)"; then
      echo "  missing:   $arn"; bad=1; continue
    fi
    read -r deleted current <<<"$out"
    if [[ -n "$deleted" && "$deleted" != "None" ]]; then
      echo "  deleted:   $arn (scheduled for deletion; restore it with aws secretsmanager restore-secret)"; bad=1
    elif [[ "${current:-0}" == "0" ]]; then
      echo "  no value:  $arn (no current version: store one with bin/put-secret)"; bad=1
    fi
  done
  return $bad
}

# Summarize a saved plan: counts as Terraform reports them, then one line per
# resource that changes. Usage: df_plan_summary <dir> <planfile>
df_plan_summary() {
  df_tf_at "$1" show -json "$2" | jq -r '
    [.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])] as $c
    | ($c | map(select(.change.actions | index("create"))) | length) as $add
    | ($c | map(select(.change.actions == ["update"])) | length) as $chg
    | ($c | map(select(.change.actions | index("delete"))) | length) as $del
    | "  Plan: \($add) to add, \($chg) to change, \($del) to destroy.",
      ($c[] | "    " + (if (.change.actions | length) == 2 then "-/+"
                         elif .change.actions == ["create"] then "  +"
                         elif .change.actions == ["update"] then "  ~"
                         else "  -" end) + " " + .address)'
}

# State addresses of an app's Namecheap delegation record and Route53 zone. States
# not applied since full-stack gained a count (v1.2.5) still use the unindexed
# form until the next apply runs the moved blocks, so match both.
DF_NS_RECORD_RE='^module\.app\.module\.namecheap_ns(\[0\])?\.namecheap_domain_records\.ns$'
DF_ZONE_RE='^module\.app\.module\.route53_zone(\[0\])?\.aws_route53_zone\.main$'
