"""Offline checks that a build which ships refuses our development project."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ipad_bundle', Path(__file__).with_name('bundle.py'))
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


def app(directory, manifest=None):
    folder = Path(directory) / 'app'
    folder.mkdir()
    if manifest is not None:
        (folder / 'app.xml').write_text(manifest)
    return folder


class BackendTest(unittest.TestCase):
    def test_development_project_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = app(directory, '<App name="X"><Backend provider="appwrite" /></App>')
            with self.assertRaises(ValueError) as refused:
                bundle.check_backend(folder)
            self.assertIn('development project', str(refused.exception))
            self.assertIn('project="<project ID>"', str(refused.exception))

    def test_own_project_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = app(directory, '<App name="X"><Backend provider="appwrite" '
                         'endpoint="https://fra.cloud.appwrite.io/v1" project="abc123" /></App>')
            bundle.check_backend(folder)

    def test_local_apps_are_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle.check_backend(app(directory, '<App name="X"><Section title="A" /></App>'))
        with tempfile.TemporaryDirectory() as directory:
            bundle.check_backend(app(directory))

    def test_cloud_notes_saves_to_the_development_project(self):
        with self.assertRaises(ValueError):
            bundle.check_backend(ROOT / 'demo/cloud-notes')

    def test_released_apps_are_accepted(self):
        import json
        for record in json.loads((ROOT / 'scripts/release/apps.json').read_text()):
            bundle.check_backend(ROOT / 'apps' / record['app'])


if __name__ == '__main__':
    unittest.main()
