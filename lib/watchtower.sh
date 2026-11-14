# shellcheck shell=bash
# shellcheck disable=SC2034  # DF_WT_NOTE is read by the scripts that source this file
# lib/watchtower.sh: deployment windows on a Watchtower collector, for bin/deploy-app,
# bin/deploy and bin/rotate-secret. Sourced after lib/common.sh.
#
# A window tells Watchtower a deploy is under way, so it holds the target's alerts and
# learns how long its deploys take. All of it is optional: with WATCHTOWER_URL unset
# no function here calls curl or aws. Watchtower being down, or answering with an
# error, only warns: a deploy never fails because monitoring is unavailable.
#
# Settings, from .env or the app's app.env / the site's site.env (the latter wins):
#   WATCHTOWER_URL              the collector, e.g. https://watch.example.com
#   WATCHTOWER_TOKEN_PARAMETER  SSM SecureString holding a deploy token (wtd_...)
#   WATCHTOWER_TARGET           what is deployed (default: the app's name or the domain)
#   WATCHTOWER_SOURCES, WATCHTOWER_GROUPS, WATCHTOWER_PROBES
#                               what the window covers, space- or comma-separated
#   WATCHTOWER_SETTLE_TIMEOUT   seconds to wait for settled (default twice the estimate)
#
# The token is read into a shell variable and handed to curl on stdin (--config -),
# so it never appears in a command line, a log or an error message.

DF_WT_ID=""; DF_WT_DONE=false; DF_WT_TOKEN=""; DF_WT_TARGET=""
DF_WT_DEADLINE_MS=0; DF_WT_ESTIMATE=0; DF_WT_NOTE=""; DF_WT_UNSETTLED=false

df_wt_configured() { [[ -n "${WATCHTOWER_URL:-}" ]]; }
df_wt_active() { [[ -n "$DF_WT_ID" ]]; }

# Copies WATCHTOWER_* settings out of an env file without keeping anything else it
# sets, for a script that doesn't source that file itself. Usage: df_wt_env_from <file>
df_wt_env_from() {
  [[ -f "$1" ]] || return 0
  eval "$(set +u; # shellcheck disable=SC1090
    source "$1" >/dev/null 2>&1
    for v in WATCHTOWER_URL WATCHTOWER_TOKEN_PARAMETER WATCHTOWER_TARGET WATCHTOWER_SOURCES \
             WATCHTOWER_GROUPS WATCHTOWER_PROBES WATCHTOWER_SETTLE_TIMEOUT; do
      [[ -n "${!v+x}" ]] && printf '%s=%q\n' "$v" "${!v}"
    done)"
}

df_wt_now_ms() { echo $(( $(date +%s) * 1000 )); }
df_wt_minutes() { echo $(( ($1 + 59) / 60 )); }

# Seconds left in the open window (negative once it has passed).
df_wt_remaining() { echo $(( (DF_WT_DEADLINE_MS - $(df_wt_now_ms)) / 1000 )); }

# A JSON array from a space- or comma-separated list.
df_wt_list_json() { jq -cn --arg s "$1" '[$s | splits("[ ,]+") | select(length > 0)]'; }

# One request to the deployments API. Sets DF_WT_CODE (000 when unreachable),
# DF_WT_BODY and DF_WT_ERR; true on a 2xx. Usage: df_wt_call <method> <path> [json]
df_wt_call() {
  local method="$1" path="$2" body="${3:-}" out
  out="$(mktemp)"
  local args=(-sS --max-time "${DF_WT_MAX_TIME:-10}" --retry 2 --retry-delay 1 --retry-connrefused
              --config - -X "$method" -o "$out" -w '%{http_code}')
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' --data-binary "$body")
  DF_WT_CODE="$(printf 'header = "Authorization: Bearer %s"\n' "$DF_WT_TOKEN" \
    | curl "${args[@]}" "${WATCHTOWER_URL%/}/api/v1/deployments$path" 2>"$out.err")" || true
  [[ "$DF_WT_CODE" =~ ^[0-9]{3}$ ]] || DF_WT_CODE=000
  DF_WT_BODY="$(cat "$out" 2>/dev/null || true)"
  if [[ "$DF_WT_CODE" == 000 ]]; then
    DF_WT_ERR="could not reach $WATCHTOWER_URL: $(tr '\n' ' ' <"$out.err" 2>/dev/null)"
  else
    DF_WT_ERR="HTTP $DF_WT_CODE: $(jq -r '.error // empty' <<<"$DF_WT_BODY" 2>/dev/null || true)"
    [[ "$DF_WT_ERR" != "HTTP $DF_WT_CODE: " ]] || DF_WT_ERR="HTTP $DF_WT_CODE: ${DF_WT_BODY:0:200}"
  fi
  rm -f "$out" "$out.err"
  [[ "$DF_WT_CODE" == 2* ]]
}

df_wt_field() { jq -r "$1 // empty" <<<"$DF_WT_BODY" 2>/dev/null || true; }

# Opens a deployment window. Leaves DF_WT_ID empty, with a warning, when Watchtower
# isn't configured right, can't be reached, or already has a deployment of the
# target running (that one is someone else's, so this deploy runs without a window).
# Usage: df_wt_start <script name> <default target> <description> <version>
df_wt_start() {
  df_wt_configured || return 0
  local caller="$1" description="$3" version="$4" body err
  DF_WT_TARGET="${WATCHTOWER_TARGET:-$2}"
  if [[ -z "${WATCHTOWER_TOKEN_PARAMETER:-}" ]]; then
    warn "Watchtower: WATCHTOWER_URL is set but WATCHTOWER_TOKEN_PARAMETER is not; deploying without a window"
    return 0
  fi
  err="$(mktemp)"
  if ! DF_WT_TOKEN="$(aws ssm get-parameter --name "$WATCHTOWER_TOKEN_PARAMETER" --with-decryption \
        --query Parameter.Value --output text 2>"$err")" || [[ -z "$DF_WT_TOKEN" ]]; then
    warn "Watchtower: could not read the deploy token from SSM $WATCHTOWER_TOKEN_PARAMETER ($(tr '\n' ' ' <"$err")); deploying without a window"
    DF_WT_TOKEN=""; rm -f "$err"; return 0
  fi
  rm -f "$err"
  DF_WT_TOKEN="${DF_WT_TOKEN//[[:space:]]/}"
  body="$(jq -cn --arg target "$DF_WT_TARGET" --arg description "$description" --arg version "$version" \
    --arg caller "devopsfoundry/$caller" --argjson sources "$(df_wt_list_json "${WATCHTOWER_SOURCES:-}")" \
    --argjson groups "$(df_wt_list_json "${WATCHTOWER_GROUPS:-}")" \
    --argjson probes "$(df_wt_list_json "${WATCHTOWER_PROBES:-}")" \
    '{target: $target, scope: {sources: $sources, groups: $groups, probes: $probes},
      description: $description, version: $version, caller: $caller}')"
  if df_wt_call POST "" "$body"; then
    DF_WT_ID="$(df_wt_field .id)"
    DF_WT_DEADLINE_MS="$(df_wt_field .deadline_ms)"; DF_WT_DEADLINE_MS="${DF_WT_DEADLINE_MS:-0}"
    DF_WT_ESTIMATE="$(df_wt_field .estimate_seconds)"; DF_WT_ESTIMATE="${DF_WT_ESTIMATE:-0}"
    if [[ -z "$DF_WT_ID" ]]; then
      warn "Watchtower: the start answer had no deployment id; deploying without a window"
      return 0
    fi
    pass "Watchtower: deployment window $DF_WT_ID opened for $DF_WT_TARGET, $(df_wt_minutes "$(df_wt_remaining)") min"
  elif [[ "$DF_WT_CODE" == 409 ]]; then
    warn "Watchtower: a deployment of $DF_WT_TARGET is already running ($(df_wt_field .running_id)); deploying without a window of our own"
  else
    warn "Watchtower: could not open a deployment window ($DF_WT_ERR); deploying without one"
  fi
}

# Moves the window's deadline out. Usage: df_wt_extend <seconds> <reason>
df_wt_extend() {
  df_wt_active || return 0
  if df_wt_call POST "/$DF_WT_ID/extend" "$(jq -cn --argjson s "$1" --arg r "$2" '{seconds: $s, reason: $r}')"; then
    DF_WT_DEADLINE_MS="$(df_wt_field .deadline_ms)"; DF_WT_DEADLINE_MS="${DF_WT_DEADLINE_MS:-0}"
    info "Watchtower: window extended by $(df_wt_minutes "$1") min ($2), $(df_wt_minutes "$(df_wt_remaining)") min left"
  else
    warn "Watchtower: could not extend the window ($DF_WT_ERR)"
  fi
}

# Extends the window when less than <seconds> of it is left. Usage: df_wt_ensure <seconds> <reason>
df_wt_ensure() {
  df_wt_active || return 0
  (( $(df_wt_remaining) >= $1 )) || df_wt_extend "$1" "$2"
}

# Polls /settled every DF_WT_POLL_SECONDS (15) until the target is back to normal,
# extending the window by the estimate when its deadline is under a minute away, for
# at most WATCHTOWER_SETTLE_TIMEOUT seconds (default twice the estimate). Sets
# DF_WT_NOTE to what happened, for df_wt_done. A target that has not settled by then
# sets DF_WT_UNSETTLED, so df_wt_done leaves the window open and Watchtower reports
# an unusual deployment when it expires. Never fails the deploy.
df_wt_wait_settled() {
  df_wt_active || return 0
  local est="$DF_WT_ESTIMATE" limit start elapsed reasons
  (( est > 0 )) || est=300
  limit="${WATCHTOWER_SETTLE_TIMEOUT:-$((2 * est))}"
  start="$(date +%s)"
  info "Watchtower: waiting up to $limit s for $DF_WT_TARGET to settle"
  while :; do
    elapsed=$(( $(date +%s) - start ))
    if ! df_wt_call GET "/$DF_WT_ID/settled"; then
      DF_WT_NOTE="settled state unknown ($DF_WT_ERR)"
      warn "Watchtower: could not read whether $DF_WT_TARGET settled ($DF_WT_ERR)"
      return 0
    fi
    if [[ "$(df_wt_field .settled)" == true ]]; then
      DF_WT_NOTE="settled after $elapsed s"
      pass "Watchtower: $DF_WT_TARGET settled after $elapsed s (normal for $(df_wt_field .normal_for_seconds) s)"
      return 0
    fi
    reasons="$(jq -r '(.reasons // []) | join("; ")' <<<"$DF_WT_BODY" 2>/dev/null || true)"
    if (( elapsed >= limit )); then
      DF_WT_NOTE="not settled after $elapsed s${reasons:+: $reasons}"
      DF_WT_UNSETTLED=true
      warn "Watchtower: $DF_WT_TARGET not settled after $elapsed s${reasons:+: $reasons}"
      return 0
    fi
    [[ -z "$(df_wt_field .deadline_ms)" ]] || DF_WT_DEADLINE_MS="$(df_wt_field .deadline_ms)"
    (( $(df_wt_remaining) >= 60 )) || df_wt_extend "$est" "waiting for $DF_WT_TARGET to settle"
    sleep "${DF_WT_POLL_SECONDS:-15}"
  done
}

# Closes the window, once. Usage: df_wt_done succeeded|failed|rolled-back <note>
df_wt_done() {
  df_wt_active || return 0
  ! $DF_WT_DONE || return 0
  DF_WT_DONE=true
  if $DF_WT_UNSETTLED && [[ "$1" == succeeded ]]; then
    warn "Watchtower: leaving deployment $DF_WT_ID open, since $DF_WT_TARGET has not settled; Watchtower reports an unusual deployment if it is still running in $(df_wt_minutes "$(df_wt_remaining)") min"
    return 0
  fi
  if df_wt_call POST "/$DF_WT_ID/done" "$(jq -cn --arg o "$1" --arg n "${2:0:500}" '{outcome: $o, note: $n}')"; then
    info "Watchtower: deployment $DF_WT_ID closed as $1"
  else
    warn "Watchtower: could not close deployment $DF_WT_ID as $1 ($DF_WT_ERR)"
  fi
}

# For an EXIT trap: a window still open when the script exits closes as failed,
# with the last error die printed. Usage: df_wt_on_exit <exit status>
df_wt_on_exit() {
  df_wt_active && ! $DF_WT_DONE || return 0
  df_wt_done failed "${DF_LAST_ERROR:-${DF_SCRIPT_NAME:-devopsfoundry} exited with status $1 before finishing}"
}
