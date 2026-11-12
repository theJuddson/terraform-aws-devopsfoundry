"""The plugin's PreToolUse hook (#61): asks before steps that skip DevOpsFoundry's
plan approval, denies reading credential files and fetching secret values, and
lets everything else through. Run: python3 -m unittest discover -s tests/plugin
"""

import json
import pathlib
import subprocess
import sys
import unittest

HOOK = pathlib.Path(__file__).resolve().parents[2] / "plugins/devopsfoundry/hooks/approval_guard.py"


def run(command, tool="Bash"):
    out = subprocess.run([sys.executable, str(HOOK)], input=json.dumps({"tool_name": tool, "tool_input": {"command": command}}),
                         capture_output=True, text=True, timeout=5)
    assert out.returncode == 0, out.stderr
    if not out.stdout.strip():
        return None
    return json.loads(out.stdout)["hookSpecificOutput"]["permissionDecision"]


class Asks(unittest.TestCase):
    def test_scripts_with_yes_ask(self):
        for cmd in ("bin/deploy-app --config ../app/.devopsfoundry --yes",
                    "./bin/new-app example.com --config x -y",
                    "/Users/a/DevOpsFoundry/bin/destroy-app --config x --yes",
                    "cd ~/DevOpsFoundry && bin/rotate-secret --config x redis --yes",
                    "AWS_PROFILE=main bin/release-nameservers --config x --yes",
                    "bash bin/new-site example.com --build-dir dist --yes",
                    "bin/deploy example.com --yes",
                    "bin/deploy --config ../site/.devopsfoundry --yes",
                    "bin/destroy-site --config ../site/.devopsfoundry --yes"):
            self.assertEqual(run(cmd), "ask", cmd)

    def test_ses_production_request_asks(self):
        self.assertEqual(run("bin/email-status --config x --request-production --website-url https://e.com --use-case t"), "ask")

    def test_terraform_shortcuts_ask(self):
        for cmd in ("terraform apply -auto-approve",
                    "terraform -chdir=app/.devopsfoundry destroy -auto-approve -var-file=app.tfvars",
                    "terraform apply -replace=aws_instance.x",
                    "terraform apply -target=module.app",
                    "terraform state rm module.app.x",
                    "terraform -chdir=x state mv a b",
                    "terraform state push s.json"):
            self.assertEqual(run(cmd), "ask", cmd)


class Denies(unittest.TestCase):
    def test_reading_credential_files_is_denied(self):
        for cmd in ("cat .env", "head -5 ~/DevOpsFoundry/.env", "source .env", ". ./.env",
                    "grep KEY .env.production", "cat sites/example.com/site.env",
                    "ls && cat .env", "cp .env /tmp/x"):
            self.assertEqual(run(cmd), "deny", cmd)

    def test_fetching_secret_values_is_denied(self):
        for cmd in ("aws secretsmanager get-secret-value --secret-id x",
                    "aws --region us-east-1 secretsmanager get-secret-value --secret-id x --query SecretString",
                    "aws secretsmanager batch-get-secret-value --secret-id-list a b"):
            self.assertEqual(run(cmd), "deny", cmd)

    def test_deny_wins_over_ask_in_one_command(self):
        self.assertEqual(run("bin/deploy-app --config x --yes; cat .env"), "deny")


class Allows(unittest.TestCase):
    def test_ordinary_and_read_only_commands_pass(self):
        for cmd in ("bin/deploy-app --config x",            # the script asks for itself
                    "bin/preflight",
                    "bin/email-status --config x",
                    "terraform plan -out=p.bin",
                    "terraform apply p.bin",                 # a saved, reviewed plan
                    "terraform state list",
                    "terraform state show module.app.x",
                    "cat .env.example",
                    "cp .env.example .env",                  # copying the template is fine
                    "grep -rn get-secret-value lib/",       # mentioning it isn't calling it
                    "aws secretsmanager describe-secret --secret-id x",
                    "git commit -m 'deploy-app --yes is now asked about'",
                    "echo hello",
                    "scripts/deploy --yes",                 # another project's script, not DevOpsFoundry's bin/
                    "npm run deploy -- --yes"):
            self.assertIsNone(run(cmd), cmd)

    def test_other_tools_and_bad_input_pass(self):
        self.assertIsNone(run("cat .env", tool="Read"))
        out = subprocess.run([sys.executable, str(HOOK)], input="not json", capture_output=True, text=True, timeout=5)
        self.assertEqual((out.returncode, out.stdout), (0, ""))

    def test_a_long_flag_run_finishes_quickly(self):
        self.assertIsNone(run("aws " + "--x y " * 5000 + "s3 ls"))


if __name__ == "__main__":
    unittest.main()
