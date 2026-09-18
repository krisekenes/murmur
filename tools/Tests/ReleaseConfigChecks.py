"""Check packaging refuses accidental ad-hoc distribution before building anything."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseConfigChecks(unittest.TestCase):
    def check_config(self, *args, **settings):
        env = {k: v for k, v in os.environ.items()
               if k not in ("MURMUR_SIGNING_IDENTITY", "MURMUR_NOTARY_PROFILE")}
        env.update(settings)
        return subprocess.run(
            ["bash", "tools/package-release.sh", "--check-config", *args],
            cwd=ROOT, env=env, capture_output=True, text=True)

    def test_default_rejects_missing_signing(self):
        result = self.check_config()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Developer ID Application", result.stderr)

    def test_explicit_preview_works_without_credentials(self):
        self.assertEqual(self.check_config("--preview").returncode, 0)

    def test_development_and_adhoc_identities_rejected(self):
        for identity in ("-", "Apple Development: Example (TEAM)"):
            self.assertNotEqual(self.check_config(
                MURMUR_SIGNING_IDENTITY=identity,
                MURMUR_NOTARY_PROFILE="example").returncode, 0)

    def test_distribution_requires_notarization(self):
        self.assertNotEqual(self.check_config(
            MURMUR_SIGNING_IDENTITY="Developer ID Application: Example (TEAM)").returncode, 0)

    def test_distribution_configuration_accepted(self):
        self.assertEqual(self.check_config(
            MURMUR_SIGNING_IDENTITY="Developer ID Application: Example (TEAM)",
            MURMUR_NOTARY_PROFILE="example").returncode, 0)

    def test_preview_cannot_discard_signing_configuration(self):
        self.assertNotEqual(self.check_config("--preview",
            MURMUR_SIGNING_IDENTITY="Developer ID Application: Example (TEAM)").returncode, 0)
        self.assertNotEqual(self.check_config("--preview",
            MURMUR_NOTARY_PROFILE="example").returncode, 0)

    def test_unknown_options_rejected(self):
        self.assertNotEqual(self.check_config("--preveiw").returncode, 0)


if __name__ == "__main__":
    unittest.main()
