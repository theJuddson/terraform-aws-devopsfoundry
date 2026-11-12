"""bin/check-plugin (#60): each test copies the plugin into a temporary repo, breaks
one rule, and expects check-plugin to name it. Run: python3 -m unittest discover -s tests/plugin
"""

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]
CHECK = REPO / "bin/check-plugin"
SKILL = "plugins/devopsfoundry/skills/deploying-with-devopsfoundry/SKILL.md"


class CheckPlugin(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        for d in ("plugins", ".claude-plugin", ".cursor-plugin", ".agents"):
            shutil.copytree(REPO / d, self.tmp / d)
        shutil.copy(REPO / "CHANGELOG.md", self.tmp / "CHANGELOG.md")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def check(self, *args):
        out = subprocess.run([sys.executable, str(CHECK), *args, str(self.tmp)], capture_output=True, text=True, timeout=30)
        return out.returncode, out.stdout

    def edit(self, rel, old, new):
        p = self.tmp / rel
        text = p.read_text()
        self.assertIn(old, text, f"fixture text not found in {rel}")
        p.write_text(text.replace(old, new, 1))

    def test_the_repo_passes(self):
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_a_skill_name_must_match_its_folder(self):
        self.edit(SKILL, "name: deploying-with-devopsfoundry", "name: deploying-with-dof")
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("must match its folder", out)

    def test_a_skill_name_must_be_kebab_case(self):
        self.edit(SKILL, "name: deploying-with-devopsfoundry", "name: Deploying_With")
        self.assertIn("kebab-case", self.check()[1])

    def test_a_description_must_be_20_to_1024_characters(self):
        text = (self.tmp / SKILL).read_text()
        start, end = text.index("description: >"), text.index("license:")
        (self.tmp / SKILL).write_text(text[:start] + "description: Deploys.\n" + text[end:])
        self.assertIn("it must be 20 to 1024", self.check()[1])

    def test_unknown_frontmatter_fields_are_refused(self):
        self.edit(SKILL, "license: Apache-2.0", "license: Apache-2.0\nauthor: someone")
        self.assertIn("field 'author' is not allowed", self.check()[1])

    def test_a_broken_reference_link_is_named(self):
        self.edit(SKILL, "(references/secrets.md)", "(references/secret.md)")
        self.assertIn("link 'references/secret.md' points at nothing", self.check()[1])

    def test_a_version_behind_the_newest_release_fails_and_fix_repairs_it(self):
        self.edit("plugins/devopsfoundry/.codex-plugin/plugin.json", '"version": "', '"version": "0.0.1-')
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn(".codex-plugin/plugin.json: version", out)
        rc, out = self.check("--fix")
        self.assertEqual(rc, 0, out)

    def test_a_missing_hook_script_is_named(self):
        (self.tmp / "plugins/devopsfoundry/hooks/approval_guard.py").unlink()
        self.assertIn("hooks/approval_guard.py doesn't exist", self.check()[1])

    def test_every_plugin_must_be_in_every_marketplace(self):
        p = self.tmp / ".agents/plugins/marketplace.json"
        m = json.loads(p.read_text())
        m["plugins"] = []
        p.write_text(json.dumps(m))
        self.assertIn(".agents/plugins/marketplace.json: plugins/devopsfoundry isn't listed", self.check()[1])

    def test_a_manifest_must_name_its_folder(self):
        self.edit("plugins/devopsfoundry/.claude-plugin/plugin.json", '"name": "devopsfoundry"', '"name": "dof"')
        self.assertIn("name 'dof' != folder 'devopsfoundry'", self.check()[1])


if __name__ == "__main__":
    unittest.main()
