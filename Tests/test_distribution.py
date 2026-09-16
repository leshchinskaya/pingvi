import importlib.util
from pathlib import Path
import unittest
import os
import subprocess

spec = importlib.util.spec_from_file_location('distribution', Path(__file__).resolve().parents[1] / 'tools/distribution.py')
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)


class DistributionTests(unittest.TestCase):
    def test_release_cannot_silently_use_ad_hoc_or_skip_notarization(self):
        errors = distribution.problems('release', {}, 'arm64', 'arm64', '')
        self.assertEqual(len(errors), 2)
        self.assertTrue(any('SIGNING_IDENTITY' in error for error in errors))
        self.assertTrue(any('NOTARY_PROFILE' in error for error in errors))

    def test_development_certificate_is_not_developer_id(self):
        env = dict(SIGNING_IDENTITY='ABC', NOTARY_PROFILE='profile')
        self.assertTrue(distribution.problems('release', env, 'arm64', 'arm64', 'ABC "Apple Development: Tester"'))
        self.assertFalse(distribution.problems('release', env, 'arm64', 'arm64', 'ABC "Developer ID Application: Tester (TEAM)"'))

    def test_explicit_adhoc_beta_does_not_require_developer_id(self):
        self.assertFalse(distribution.problems('adhoc', {}, 'arm64', 'arm64', ''))
        self.assertTrue(distribution.problems('adhoc', {}, 'x86_64', 'arm64', ''))

    def test_local_requires_matching_runtime_architecture(self):
        self.assertFalse(distribution.problems('local', {}, 'arm64', 'arm64', ''))
        self.assertTrue(distribution.problems('local', {}, 'x86_64', 'arm64', ''))

    def test_real_release_command_stops_before_build_without_credentials(self):
        env = dict(os.environ)
        env.pop('SIGNING_IDENTITY', None)
        env.pop('NOTARY_PROFILE', None)
        script = Path(__file__).resolve().parents[1] / 'tools/package-dmg.sh'
        result = subprocess.run(['bash', str(script), '--release'], env=env, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SIGNING_IDENTITY', result.stdout)
        self.assertIn('NOTARY_PROFILE', result.stdout)
        self.assertNotIn('Building for production', result.stdout + result.stderr)
