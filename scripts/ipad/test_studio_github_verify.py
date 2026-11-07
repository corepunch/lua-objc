"""Credential input checks without Keychain access, a simulator, or network."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('studio_github_verify', Path(__file__).with_name('studio_github_verify.py'))
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class CredentialsTest(unittest.TestCase):
    def test_environment_supplies_token(self):
        self.assertEqual(verify.review_token({'STUDIO_REVIEW_GITHUB_TOKEN': '  fixture-token\n'}), 'fixture-token')

    def test_missing_token_does_not_launch_keychain(self):
        with patch.object(verify.subprocess, 'run', side_effect=AssertionError('Unexpected credential lookup')) as run:
            with self.assertRaisesRegex(RuntimeError, 'Set STUDIO_REVIEW_GITHUB_TOKEN'):
                verify.review_token({})
            run.assert_not_called()

    def test_blank_token_does_not_launch_keychain(self):
        with patch.object(verify.subprocess, 'run', side_effect=AssertionError('Unexpected credential lookup')) as run:
            with self.assertRaisesRegex(RuntimeError, 'Keychain lookup is disabled'):
                verify.review_token({'STUDIO_REVIEW_GITHUB_TOKEN': ' \n\t'})
            run.assert_not_called()

    def test_unrelated_credentials_are_not_used(self):
        with self.assertRaisesRegex(RuntimeError, 'STUDIO_REVIEW_GITHUB_TOKEN'):
            verify.review_token({'GH_TOKEN': 'unrelated-token'})


if __name__ == '__main__':
    unittest.main()
