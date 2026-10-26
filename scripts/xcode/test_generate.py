"""Offline project regeneration and native build contracts."""
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

import generate


class ProjectTests(unittest.TestCase):
    def test_shared_scheme_and_workspace_settings_are_generated(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / 'AdventureArena.xcodeproj'
            generate.generate(project)
            scheme = project / 'xcshareddata/xcschemes/AdventureArena.xcscheme'
            settings = project / 'project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings'
            key = 'IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded'
            self.assertIs(plistlib.loads(settings.read_bytes())[key], False)
            self.assertTrue(scheme.is_file())
            self.assertFalse((project / 'xcuserdata').exists())
            before = settings.read_bytes(), settings.stat().st_mtime_ns
            generate.generate(project)
            self.assertEqual(before, (settings.read_bytes(), settings.stat().st_mtime_ns))
            # Regeneration restores the shared scheme and owns automatic creation,
            # while preserving unrelated workspace preferences.
            scheme.unlink()
            settings.write_bytes(plistlib.dumps({key: True, 'PreviewsEnabled': False}))
            generate.generate(project)
            self.assertTrue(scheme.is_file())
            self.assertEqual(plistlib.loads(settings.read_bytes()), {key: False, 'PreviewsEnabled': False})

    def test_regeneration_is_stable_and_preserves_xcode_choices(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / 'AdventureArena.xcodeproj'
            generate.generate(project)
            path = project / 'project.pbxproj'
            scheme = project / 'xcshareddata/xcschemes/AdventureArena.xcscheme'
            before = path.read_bytes(), path.stat().st_mtime_ns, scheme.read_bytes()
            generate.generate(project)
            self.assertEqual(before, (path.read_bytes(), path.stat().st_mtime_ns, scheme.read_bytes()))
            data = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
            for obj in data['objects'].values():
                if obj['isa'] == 'XCBuildConfiguration' and 'PRODUCT_NAME' in obj['buildSettings']:
                    obj['buildSettings'].update(DEVELOPMENT_TEAM='TESTTEAM', CODE_SIGN_STYLE='Manual',
                                                PROVISIONING_PROFILE_SPECIFIER='My Profile',
                                                MARKETING_VERSION='2.3', CURRENT_PROJECT_VERSION='42')
            path.write_text(generate.encode(data))
            scheme.write_text(scheme.read_text() + '<!-- custom -->\n')
            custom_scheme = scheme.read_bytes()
            generate.generate(project)
            for obj in generate.read_project(path).values():
                if obj['isa'] == 'XCBuildConfiguration' and 'PRODUCT_NAME' in obj['buildSettings']:
                    for key, value in dict(DEVELOPMENT_TEAM='TESTTEAM', CODE_SIGN_STYLE='Manual',
                                          PROVISIONING_PROFILE_SPECIFIER='My Profile',
                                          MARKETING_VERSION='2.3', CURRENT_PROJECT_VERSION='42').items():
                        self.assertEqual(obj['buildSettings'][key], value)
            self.assertEqual(scheme.read_bytes(), custom_scheme)

    def test_committed_project_has_all_native_sources_and_valid_references(self):
        objects = generate.read_project(generate.PROJECT / 'project.pbxproj')
        phases = [obj for obj in objects.values() if obj['isa'] == 'PBXSourcesBuildPhase']
        sources = [objects[objects[uid]['fileRef']]['path'] for phase in phases for uid in phase['files']]
        expected = set(generate.ROOT.joinpath('ios/LuaRuntime').glob('*.m'))
        expected.update(generate.ROOT.joinpath('vendor/lua-5.4.8/src').glob('*.c'))
        expected.difference_update(generate.ROOT / 'vendor/lua-5.4.8/src' / name for name in ('lua.c', 'luac.c'))
        expected.update(generate.ROOT / name for name in (
            'src/uikit_module.m', 'src/plugins/git/Git.c', 'src/plugins/speech/Speech.m'))
        actual = [(generate.APP / source).resolve() for source in sources]
        self.assertEqual(set(actual), expected)
        self.assertEqual(len(actual), len(set(actual)))
        self.assertTrue(all(path.is_file() for path in actual))
        settings = [obj['buildSettings'] for obj in objects.values() if obj['isa'] == 'XCBuildConfiguration']
        for config in (value for value in settings if 'SDKROOT' in value):
            self.assertEqual(config['TARGETED_DEVICE_FAMILY'], '1,2')
            self.assertEqual(config['SUPPORTED_PLATFORMS'], 'iphoneos iphonesimulator')
            self.assertIn('$(DERIVED_FILE_DIR)/libgit2/libgit2.a', config['OTHER_LDFLAGS'])
        scheme = ET.parse(generate.PROJECT / 'xcshareddata/xcschemes/AdventureArena.xcscheme')
        for ref in scheme.findall('.//BuildableReference'):
            self.assertEqual(objects[ref.attrib['BlueprintIdentifier']]['isa'], 'PBXNativeTarget')
        self.assertFalse((generate.ROOT / 'ios/AdventureArena').exists())


if __name__ == '__main__':
    unittest.main()
