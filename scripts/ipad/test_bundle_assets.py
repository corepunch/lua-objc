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


class LocalizationTest(unittest.TestCase):
    def test_lproj_folders_go_to_the_bundle_root_and_stale_ones_go(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'app/de.lproj').mkdir(parents=True)
            (root / 'app/de.lproj/InfoPlist.strings').write_text('"a" = "b";')
            (root / 'bundle/fr.lproj').mkdir(parents=True)
            bundle.copy_localizations(root / 'app', root / 'bundle')
            self.assertTrue((root / 'bundle/de.lproj/InfoPlist.strings').is_file())
            self.assertFalse((root / 'bundle/fr.lproj').exists())

    def test_the_workspace_copy_leaves_lproj_folders_out(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'app/ru.lproj').mkdir(parents=True)
            (root / 'app/ru.lproj/InfoPlist.strings').write_text('"a" = "b";')
            (root / 'app/init.lua').write_text('return {}')
            previous = Path.cwd()
            try:
                os.chdir(root)
                bundle.copy_tree('app', root / 'workspace')
            finally:
                os.chdir(previous)
            self.assertTrue((root / 'workspace/app/init.lua').is_file())
            self.assertFalse((root / 'workspace/app/ru.lproj').exists())


if __name__ == '__main__':
    unittest.main()
