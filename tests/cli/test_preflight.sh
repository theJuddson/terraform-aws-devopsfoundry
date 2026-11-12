# shellcheck shell=bash
# preflight tells an expired sign-in from missing or rejected credentials, and
# notes long-term access keys, without ever printing a key (#58).

# sts <exit> <output>: what `aws sts get-caller-identity` answers. configure_list
# is what `aws configure list` prints (masked keys and their source).
sts() {
  printf '%s' "$2" > "$TMP/sts.out"
  printf '%s\n' "${3:-access_key : ****************ABCD     : login            : }" > "$TMP/configure.out"
  stub aws "case \"\$*\" in
  *get-caller-identity*) cat '$TMP/sts.out'; exit $1 ;;
  *'configure list'*) cat '$TMP/configure.out' ;;
esac; exit 0"
}
preflight() {
  printf 'bucket = "b"\n' > "$DF/backend.tfvars"
  OUT="$(AWS_PROFILE=main NAMECHEAP_USER_NAME=u NAMECHEAP_API_USER=u NAMECHEAP_API_KEY=k "$DF/bin/preflight" 2>&1)" || true
}

t_working_credentials_pass() {
  sts 0 111111111111
  preflight
  assert_contains "$OUT" "AWS account: 111111111111"
  assert_not_contains "$OUT" "long-term"
}

t_an_expired_sign_in_says_how_to_renew_it() {
  sts 255 "An error occurred (ExpiredToken) when calling the GetCallerIdentity operation: The security token included in the request is expired"
  preflight
  assert_contains "$OUT" "AWS sign-in for profile main has expired. Run: aws login --profile main"
  assert_not_contains "$OUT" "aws configure"
  assert_contains "$OUT" "hard check"
}

t_an_expired_sso_session_says_how_to_renew_it() {
  sts 255 "Error when retrieving token from sso: Token has expired and refresh failed"
  preflight
  assert_contains "$OUT" "has expired"
  assert_contains "$OUT" "aws sso login --profile main"
}

t_missing_credentials_say_how_to_sign_in() {
  sts 255 "Unable to locate credentials. You can configure credentials by running \"aws login\"."
  preflight
  assert_contains "$OUT" "No AWS credentials for profile main"
}

t_other_rejections_show_aws_s_reason() {
  sts 254 "An error occurred (InvalidClientTokenId) when calling the GetCallerIdentity operation: The security token included in the request is invalid."
  preflight
  assert_contains "$OUT" "AWS rejected the credentials for profile main: An error occurred (InvalidClientTokenId)"
}

t_long_term_keys_are_noted_without_showing_them() {
  sts 0 111111111111 "access_key     ****************WXYZ shared-credentials-file    "
  preflight
  assert_contains "$OUT" "uses long-term access keys"
  assert_not_contains "$OUT" "WXYZ"
}

t_long_term_keys_are_noted_in_the_newer_cli_layout() {
  sts 0 111111111111 "access_key : ****************WXYZ     : shared-credentials-file : ~/.aws/credentials"
  preflight
  assert_contains "$OUT" "uses long-term access keys"
  assert_not_contains "$OUT" "WXYZ"
}

t_short_lived_sign_ins_are_not_noted() {
  sts 0 111111111111 "access_key : ****************ABCD     : sso            : "
  preflight
  assert_not_contains "$OUT" "long-term"
}

t_an_sso_token_that_cannot_be_refreshed_counts_as_expired() {
  sts 255 "Error when retrieving token from sso: Token could not be refreshed"
  preflight
  assert_contains "$OUT" "has expired"
}
