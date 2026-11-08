"""Offline checks that a bundle carries the shared asset kits its app names."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ipad_bundle', Path(__file__).with_name('bundle.py'))
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class AssetKitTest(unittest.TestCase):
    def test_coin_quest_names_the_platformer_kit(self):
        previous = Path.cwd()
        try:
            os.chdir(ROOT)
            self.assertEqual(bundle.asset_kits('apps/coin-quest'), ['platformer-kit'])
        finally:
            os.chdir(previous)

    def test_only_existing_kits_named_in_sources_are_bundled(self):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                Path('assets/kenney/space-kit').mkdir(parents=True)
                Path('assets/kenney/unused-kit').mkdir(parents=True)
                Path('apps/game/views').mkdir(parents=True)
                Path('apps/game/views/Stage.etlua').write_text('<Node model="assets/kenney/space-kit/models/ship.glb" />')
                Path('apps/game/init.lua').write_text('local KIT = "assets/kenney/missing-kit/models/"')
                self.assertEqual(bundle.asset_kits('apps/game'), ['space-kit'])
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
