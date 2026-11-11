# shellcheck shell=bash
# bin/email-status reports whether SES can send to anyone yet and requests
# production access only when asked (#25), and reports the DMARC report
# authorization record when reports go to another domain (#26).

# ses_account <get-account JSON>: what `aws sesv2 get-account` answers.
ses_account() {
  printf '%s' "$1" > "$TMP/ses.json"
  stub aws "case \"\$*\" in *'sesv2 get-account'*) cat '$TMP/ses.json' ;; esac; exit 0"
}
SANDBOX_JSON='{"ProductionAccessEnabled":false,"SendingEnabled":true}'

status() { OUT="$("$DF/bin/email-status" "$@" 2>&1)"; }

t_production_access_is_reported() {
  ses_account '{"ProductionAccessEnabled":true}'
  status --region us-east-1 || fail "email-status must succeed: $OUT"
  assert_contains "$OUT" "SES in us-east-1: production access"
  assert_called "^aws sesv2 get-account --region us-east-1"
}

t_sandbox_is_reported_with_the_way_out() {
  ses_account "$SANDBOX_JSON"
  status --region eu-west-1 || fail "email-status must succeed: $OUT"
  assert_contains "$OUT" "SES in eu-west-1: sandbox, so mail only reaches verified addresses"
  assert_contains "$OUT" "--request-production"
  assert_not_called "put-account-details"
}

t_a_pending_review_is_reported() {
  ses_account '{"ProductionAccessEnabled":false,"Details":{"ReviewDetails":{"Status":"PENDING","CaseId":"1"}}}'
  status --region us-east-1 || fail "email-status must succeed: $OUT"
  assert_contains "$OUT" "review pending"
}

t_an_unreadable_status_is_said_not_guessed() {
  stub aws 'exit 255'
  status --region us-east-1 || fail "email-status must not fail on a read error: $OUT"
  assert_contains "$OUT" "could not read the account status"
}

t_the_region_comes_from_the_app() {
  APP="$TMP/app"; mkdir -p "$APP"; touch "$APP/main.tf"
  printf 'domain_name = "example.com"\naws_region  = "ap-southeast-2"\n' > "$APP/app.tfvars"
  ses_account '{"ProductionAccessEnabled":true}'
  status --config "$APP" || fail "email-status must succeed: $OUT"
  assert_called "^aws sesv2 get-account --region ap-southeast-2"
}

t_no_region_is_refused() {
  ses_account "$SANDBOX_JSON"
  OUT="$(env -u AWS_REGION -u AWS_DEFAULT_REGION "$DF/bin/email-status" 2>&1)" && fail "no region must fail"
  assert_contains "$OUT" "No region"
}

# ── --request-production ───────────────────────────────
t_request_from_the_sandbox_sends_it_after_asking() {
  ses_account "$SANDBOX_JSON"
  OUT="$(echo y | "$DF/bin/email-status" --region us-east-1 --request-production \
    --website-url https://example.com --use-case "Sign-in links to registered users" 2>&1)" || fail "request must succeed: $OUT"
  assert_called "^aws sesv2 put-account-details --region us-east-1 --production-access-enabled --mail-type TRANSACTIONAL --website-url https://example.com --use-case-description Sign-in links to registered users --contact-language EN$"
  assert_contains "$OUT" "Requested"
}

t_answering_no_sends_nothing() {
  ses_account "$SANDBOX_JSON"
  OUT="$(echo n | "$DF/bin/email-status" --region us-east-1 --request-production \
    --website-url https://example.com --use-case "Receipts" 2>&1)" || fail "declining must not fail: $OUT"
  assert_contains "$OUT" "Not sent."
  assert_not_called "put-account-details"
}

t_no_request_is_sent_unless_in_the_sandbox() {
  local json
  for json in '{"ProductionAccessEnabled":true}' \
              '{"ProductionAccessEnabled":false,"Details":{"ReviewDetails":{"Status":"PENDING"}}}' \
              '{"ProductionAccessEnabled":false,"Details":{"ReviewDetails":{"Status":"DENIED"}}}'; do
    ses_account "$json"
    status --region us-east-1 --request-production --website-url https://example.com --use-case "Receipts" --yes || true
  done
  stub aws 'exit 255'
  status --region us-east-1 --request-production --website-url https://example.com --use-case "Receipts" --yes \
    && fail "an unreadable status must not be taken as the sandbox"
  assert_not_called "put-account-details"
}

t_a_request_needs_a_website_and_a_use_case_before_any_call() {
  ses_account "$SANDBOX_JSON"
  status --region us-east-1 --request-production --use-case "Receipts" --yes && fail "no website must fail"
  assert_contains "$OUT" "--website-url https://"
  status --region us-east-1 --request-production --website-url https://example.com --use-case "  " --yes && fail "a blank use case must fail"
  assert_contains "$OUT" "--use-case"
  status --region us-east-1 --website-url https://example.com && fail "--website-url alone must fail"
  assert_not_called "^aws sesv2"
}

# ── DMARC report authorization ─────────────────────────
dmarc_app() { # dmarc_app <terraform output -json dmarc_report_authorization>
  APP="$TMP/app"; mkdir -p "$APP"; touch "$APP/main.tf"
  printf 'domain_name = "example.com"\naws_region  = "us-east-1"\n' > "$APP/app.tfvars"
  printf '%s' "$1" > "$TMP/dmarc.json"
  stub terraform "case \"\$*\" in *'output -json dmarc_report_authorization'*) cat '$TMP/dmarc.json' ;; esac; exit 0"
  ses_account '{"ProductionAccessEnabled":true}'
}

t_a_dmarc_record_to_add_is_printed() {
  dmarc_app '{"name":"example.com._report._dmarc.example.net","type":"TXT","value":"v=DMARC1","created":false}'
  status --config "$APP" || fail "email-status must succeed: $OUT"
  assert_contains "$OUT" 'example.com._report._dmarc.example.net  TXT  "v=DMARC1"'
  assert_contains "$OUT" "dmarc_report_zone_id"
}

t_a_created_dmarc_record_is_confirmed() {
  dmarc_app '{"name":"example.com._report._dmarc.example.net","type":"TXT","value":"v=DMARC1","created":true}'
  status --config "$APP" || fail "email-status must succeed: $OUT"
  assert_contains "$OUT" "DMARC report authorization record created: example.com._report._dmarc.example.net"
}

t_no_dmarc_line_when_none_is_needed() {
  dmarc_app 'null'
  status --config "$APP" || fail "email-status must succeed: $OUT"
  assert_not_contains "$OUT" "DMARC"
}

# ── new-app and preflight ──────────────────────────────
new_app_with_email() { # new_app_with_email <flags...>
  APP="$TMP/app/.devopsfoundry"
  stub terraform "
case \"\$*\" in
  *'output -json name_servers'*) echo '[\"ns-1.awsdns-01.org\"]' ;;
  *'output -json dmarc_report_authorization'*) echo '{\"name\":\"example.com._report._dmarc.example.net\",\"type\":\"TXT\",\"value\":\"v=DMARC1\",\"created\":false}' ;;
  *'show -json'*) echo '{\"resource_changes\":[]}' ;;
  *'output -raw'*) echo x ;;
esac
exit 0"
  stub dig "echo ns-1.awsdns-01.org."
  ses_account "$SANDBOX_JSON"
  OUT="$(NAMECHEAP_API_KEY=x NAMECHEAP_CLIENT_IP=203.0.113.9 "$DF/bin/new-app" example.com --config "$APP" --yes "$@" 2>&1)" || fail "new-app must succeed: $OUT"
}

t_new_app_with_email_reports_ses_and_dmarc() {
  new_app_with_email --enable-email
  assert_contains "$OUT" "SES in us-east-1: sandbox"
  assert_contains "$OUT" 'example.com._report._dmarc.example.net  TXT  "v=DMARC1"'
  assert_not_called "put-account-details"
}

t_new_app_without_email_says_nothing_about_it() {
  new_app_with_email
  assert_not_contains "$OUT" "SES"
  assert_not_called "sesv2"
}

t_preflight_reports_ses_without_failing() {
  printf 'bucket = "b"\n' > "$DF/backend.tfvars"
  stub aws "case \"\$*\" in *get-caller-identity*) echo 111111111111 ;; *'sesv2 get-account'*) echo '$SANDBOX_JSON' ;; esac; exit 0"
  OUT="$(AWS_REGION=us-west-2 NAMECHEAP_USER_NAME=u NAMECHEAP_API_USER=u NAMECHEAP_API_KEY=k "$DF/bin/preflight" 2>&1)" || true
  assert_contains "$OUT" "SES in us-west-2: sandbox"
  assert_not_contains "$OUT" "hard check"
}
