"""Security checks for the one-time organization App import."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import import_runner_app as setup


class CredentialChecks(unittest.TestCase):
    def test_rejects_repository_administration_and_code_permissions(self):
        for extra in ({"administration": "write"}, {"contents": "read"},
                      {"contents": "write"}, {"organization_administration": "write"}):
            with self.subTest(extra=extra), self.assertRaises(RuntimeError):
                setup.validate_permissions({setup.REQUIRED_PERMISSION: "write", **extra})

    def test_rejects_missing_runner_write_permission(self):
        with self.assertRaises(RuntimeError):
            setup.validate_permissions({setup.REQUIRED_PERMISSION: "read"})

    def test_accepts_only_runner_management_and_metadata(self):
        setup.validate_permissions({setup.REQUIRED_PERMISSION: "write", "metadata": "read"})

    def test_keeps_all_private_group_without_mutations(self):
        for visibility in ("all", "private"):
            group = {"id": 1, "default": True, "visibility": visibility,
                     "allows_public_repositories": False, "restricted_to_workflows": False}
            with self.subTest(visibility=visibility), patch.object(setup, "api", return_value={"runner_groups": [group]}) as api:
                self.assertEqual(setup.verify_runner_group("fake-token", False), group)
                self.assertEqual(api.call_count, 1)

    def test_rejects_public_access_and_repository_allowlist_without_configure(self):
        for visibility, public in (("all", True), ("selected", False)):
            group = {"id": 1, "default": True, "visibility": visibility,
                     "allows_public_repositories": public, "restricted_to_workflows": False}
            with self.subTest(visibility=visibility, public=public), patch.object(setup, "api", return_value={"runner_groups": [group]}), self.assertRaises(RuntimeError):
                setup.verify_runner_group("fake-token", False)

    def test_accepts_free_plan_without_workflow_restriction_fields(self):
        group = {"id": 1, "default": True, "visibility": "all",
                 "allows_public_repositories": False}
        with patch.object(setup, "api", return_value={"runner_groups": [group]}) as api:
            self.assertEqual(setup.verify_runner_group("fake-token", True), group)
            self.assertEqual(api.call_count, 1)

    def test_verifies_policy_after_configuring(self):
        original = {"id": 1, "default": True, "visibility": "selected",
                    "allows_public_repositories": True, "restricted_to_workflows": True}
        configured = {**original, "visibility": "all", "allows_public_repositories": False,
                      "restricted_to_workflows": False}
        with patch.object(setup, "api", side_effect=[{"runner_groups": [original]}, {}, configured]) as api:
            self.assertEqual(setup.verify_runner_group("fake-token", True), configured)
            self.assertEqual(api.call_args_list[1].args[0], "PATCH")

    def test_plaintext_file_is_owner_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "github-app.secret"
            setup.write_secret(path, "123", 456, "fake-test-key\n")
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            self.assertIn('github_app_installation_id: "456"', path.read_text())
            self.assertEqual(list(Path(directory).iterdir()), [path])


if __name__ == "__main__":
    unittest.main()
