"""Offline native build contracts for the checked-in Xcode project."""
import json
from pathlib import Path
import subprocess
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'apps/adventure-arena'
PROJECT = APP / 'AdventureArena.xcodeproj'


class ProjectTests(unittest.TestCase):
    def test_committed_project_has_all_native_sources_and_valid_references(self):
        project = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', PROJECT / 'project.pbxproj'])
        objects = json.loads(project)['objects']
        phases = [obj for obj in objects.values() if obj['isa'] == 'PBXSourcesBuildPhase']
        sources = [objects[objects[uid]['fileRef']]['path'] for phase in phases for uid in phase['files']]
        expected = set((ROOT / 'ios/LuaRuntime').glob('*.m'))
        lua = ROOT / 'vendor/lua-5.4.8/src'
        expected.update(lua.glob('*.c'))
        expected.difference_update(lua / name for name in ('lua.c', 'luac.c'))
        expected.update(ROOT / name for name in (
            'src/uikit_module.m', 'src/plugins/git/Git.c', 'src/plugins/speech/Speech.m'))
        actual = [(APP / source).resolve() for source in sources]
        self.assertEqual(set(actual), expected)
        self.assertEqual(len(actual), len(set(actual)))
        self.assertTrue(all(path.is_file() for path in actual))
        settings = [obj['buildSettings'] for obj in objects.values() if obj['isa'] == 'XCBuildConfiguration']
        for config in (value for value in settings if 'SDKROOT' in value):
            self.assertEqual(config['TARGETED_DEVICE_FAMILY'], '1,2')
            self.assertEqual(config['SUPPORTED_PLATFORMS'], 'iphoneos iphonesimulator')
            self.assertIn('$(DERIVED_FILE_DIR)/libgit2/libgit2.a', config['OTHER_LDFLAGS'])
        scheme = ET.parse(PROJECT / 'xcshareddata/xcschemes/AdventureArena.xcscheme')
        for ref in scheme.findall('.//BuildableReference'):
            self.assertEqual(objects[ref.attrib['BlueprintIdentifier']]['isa'], 'PBXNativeTarget')


if __name__ == '__main__':
    unittest.main()
