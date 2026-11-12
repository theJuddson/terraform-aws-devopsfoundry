#!/usr/bin/env python3
"""PreToolUse hook for DevOpsFoundry's approval rules (AGENTS.md, issue #61).

Reads the tool call as JSON on stdin. For a shell command it:
  - asks the person first when the command skips a plan approval or changes
    Terraform state by hand: a DevOpsFoundry script run with --yes, an SES
    production request, terraform apply/destroy -auto-approve, apply with
    -replace or -target, and terraform state rm/mv/push;
  - denies reading credential files (.env, site.env) and fetching a secret's
    value (secretsmanager get-secret-value).
Everything else passes untouched.

Best-effort, not a security boundary: it matches the shape of commands, and a
determined rewrite gets past it. It fails open (allows) on anything it can't
parse, so it never blocks work by mistake. Standard library only; every pattern
is linear, so it can't hang past the hook's timeout.
"""

import json
import os
import re
import shlex
import sys

# DevOpsFoundry scripts whose --yes skips a plan approval.
APPROVED_SCRIPTS = (
    "new-app", "new-site", "deploy-app", "deploy", "destroy-app", "destroy-site",
    "rotate-secret", "release-nameservers",
)
CREDENTIAL_FILES = (".env", "site.env")
SAFE_ENV_SUFFIXES = (".example", ".sample", ".template")
READERS = {
    "cat", "less", "more", "head", "tail", "bat", "nl", "strings", "xxd", "od",
    "hexdump", "grep", "egrep", "fgrep", "rg", "awk", "sed", "sort", "uniq",
    "cut", "tr", "cp", "scp", "base64", "source", ".", "open", "code",
}
SEGMENT_SPLIT = re.compile(r"\|\||&&|[;|&\n]|\$\(|`|\)")
GET_SECRET_VALUE = re.compile(r"(?:^|\s)secretsmanager\s+(?:\S+\s+)*?(?:batch-)?get-secret-value\b")


def decide(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}))
    sys.exit(0)


def words(segment):
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def is_credential_file(arg):
    name = os.path.basename(arg.strip("'\""))
    if name.endswith(SAFE_ENV_SUFFIXES):
        return False
    return name in CREDENTIAL_FILES or name.startswith(".env.")


def script_name(word):
    """'deploy-app' for bin/deploy-app, ./bin/deploy-app or /x/DevOpsFoundry/bin/deploy-app."""
    parts = word.replace("\\", "/").split("/")
    if len(parts) >= 2 and parts[-2] == "bin":
        return parts[-1]
    return None


def check_segment(segment):
    w = words(segment.strip())
    while w and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w[0]):  # VAR=value prefixes
        w = w[1:]
    if not w:
        return None
    cmd = os.path.basename(w[0])
    if cmd in ("bash", "sh", "zsh", "env", "exec", "sudo", "time", "nice") and len(w) > 1:
        return check_segment(" ".join(shlex.quote(x) for x in w[1:]))

    script = script_name(w[0])
    if script in APPROVED_SCRIPTS and any(a in ("--yes", "-y") for a in w[1:]):
        return ("ask", f"bin/{script} --yes skips its plan approval. DevOpsFoundry's rule: only after the "
                       "person has seen the plan and said yes in this conversation.")
    if script == "email-status" and "--request-production" in w[1:]:
        return ("ask", "bin/email-status --request-production sends AWS an account-wide request; "
                       "the person decides.")

    if cmd == "terraform":
        args = [a for a in w[1:] if not a.startswith("-chdir")]
        sub = next((a for a in args if not a.startswith("-")), "")
        if sub in ("apply", "destroy") and any(a in ("-auto-approve", "--auto-approve") for a in args):
            return ("ask", f"terraform {sub} -auto-approve applies without showing a plan.")
        if sub == "apply" and any(a.startswith(("-replace", "-target")) for a in args):
            return ("ask", "terraform apply with -replace or -target changes only part of the plan; "
                           "DevOpsFoundry's rule is not to force past an error with it.")
        if sub == "state" and any(a in ("rm", "mv", "push", "replace-provider") for a in args):
            return ("ask", "terraform state edits change what Terraform manages; only "
                           "bin/release-nameservers does that on purpose.")

    # cp and scp read their sources; the last argument is where they write.
    read_args = [a for a in w[1:] if not a.startswith("-")]
    if cmd in ("cp", "scp"):
        read_args = read_args[:-1]
    if cmd in READERS and any(is_credential_file(a) for a in read_args):
        return ("deny", "Credential files (.env, site.env) are read only by DevOpsFoundry's scripts. "
                        "Don't read, print or source them.")
    if cmd == "aws" and GET_SECRET_VALUE.search(" ".join(w)):
        return ("deny", "Don't fetch a secret's value. Check a secret with describe-secret; "
                        "use one at run time with asm-exec and {{resolve:secretsmanager:...}}.")
    return None


def main():
    try:
        call = json.load(sys.stdin)
    except (ValueError, OSError):
        sys.exit(0)
    if call.get("tool_name") != "Bash":
        sys.exit(0)
    command = (call.get("tool_input") or {}).get("command") or ""
    if not isinstance(command, str) or len(command) > 20000:
        sys.exit(0)
    worst = None
    for segment in SEGMENT_SPLIT.split(command):
        found = check_segment(segment)
        if found and (worst is None or found[0] == "deny"):
            worst = found
            if found[0] == "deny":
                break
    if worst:
        decide(*worst)
    sys.exit(0)


if __name__ == "__main__":
    main()
