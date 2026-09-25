"""Fast, offline regression checks for iOS app packaging and deployment."""
import unittest
from bundle import copy_tree, resolve_app_and_entry
from deploy import device_list_command, select_device
from sign import matches, signing_entitlements
from simulator_entitlements import entitlements
from release_version import version_from_tag, set_version
from xcode_bundle import populate


def device(identifier, kind='iPad', reality='physical'):
    return {'identifier': identifier, 'hardwareProperties': {'deviceType': kind, 'reality': reality,
                                                             'udid': 'udid-' + identifier},
            'deviceProperties': {'name': 'name-' + identifier},
            'connectionProperties': {'tunnelState': 'connected', 'transportType': 'wired'}}


class DiscoveryTests(unittest.TestCase):
    def test_xcode_app_declares_exempt_encryption(self):
        from pathlib import Path
        import plistlib

        info = plistlib.loads(Path('ios/AdventureArena/Info.plist').read_bytes())
        self.assertIs(info['ITSAppUsesNonExemptEncryption'], False)

    def test_release_tag_sets_archive_version(self):
        from tempfile import TemporaryDirectory
        from pathlib import Path
        import plistlib

        self.assertEqual(version_from_tag('release/1.2.3'), '1.2.3')
        for tag in ('v1.2.3', 'release/1.2', 'release/1.2.3/extra'):
            with self.assertRaises(ValueError):
                version_from_tag(tag)
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'Info.plist'
            path.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.0', 'CFBundleVersion': '1'}))
            set_version(path, version_from_tag('release/1.2.3'))
            info = plistlib.loads(path.read_bytes())
            self.assertEqual(info['CFBundleShortVersionString'], '1.2.3')
            self.assertEqual(info['CFBundleVersion'], '1')

    def test_xcode_bundle_has_runtime_and_app(self):
        from tempfile import TemporaryDirectory
        from pathlib import Path

        with TemporaryDirectory() as directory:
            bundle = Path(directory) / 'AdventureArena.app'
            bundle.mkdir()
            populate(bundle)
            self.assertTrue((bundle / 'Workspace/lua/embedded/UIKit.lua').is_file())
            self.assertTrue((bundle / 'Workspace/apps/adventure-arena/init.lua').is_file())
            self.assertTrue((bundle / 'Workspace/apps/adventure-arena/zilscript/zilscript/bootstrap.lua').is_file())

    def test_simulator_keychain(self):
        result = entitlements('org.luaobjc.test')
        self.assertEqual(result['application-identifier'], 'SIMULATOR.org.luaobjc.test')
        self.assertEqual(result['keychain-access-groups'], ['SIMULATOR.org.luaobjc.test'])

    def test_keychain_entitlement(self):
        # App ID prefixes can differ from the signing team identifier.
        entitlements = signing_entitlements('PREFIX.org.luaobjc.studio', 'TEAM', ['PREFIX.*'])
        self.assertEqual(entitlements['keychain-access-groups'], ['PREFIX.org.luaobjc.studio'])
        self.assertEqual(entitlements['application-identifier'], 'PREFIX.org.luaobjc.studio')
        self.assertEqual(entitlements['com.apple.developer.team-identifier'], 'TEAM')
        with self.assertRaises(ValueError):
            signing_entitlements('PREFIX.org.luaobjc.studio', 'TEAM', ['OTHER.*'])

    def test_ipad_ignores_iphone(self):
        self.assertEqual(select_device([device('phone', 'iPhone'), device('tablet')], 'iPad'), 'tablet')

    def test_iphone_ignores_ipad(self):
        self.assertEqual(select_device([device('tablet'), device('phone', 'iPhone')], 'iPhone'), 'phone')

    def test_iphone_discovery_needs_no_device_selector(self):
        with self.assertRaisesRegex(ValueError, 'Connect exactly one available physical iPhone'):
            select_device([device('phone-a', 'iPhone'), device('phone-b', 'iPhone')], 'iPhone')

    def test_auto_discovery_uses_displayed_availability(self):
        self.assertEqual(device_list_command(None, '/tmp/devices.json'),
                         ['xcrun', 'devicectl', 'list', 'devices', '--filter',
                          "State BEGINSWITH 'available' OR State = 'connected'",
                          '--json-output', '/tmp/devices.json'])
        self.assertEqual(device_list_command('tablet', '/tmp/devices.json'),
                         ['xcrun', 'devicectl', 'list', 'devices', '--json-output', '/tmp/devices.json'])

    def test_simulated_connected_ipad_is_not_a_candidate(self):
        self.assertEqual(select_device([device('simulator', reality='simulated'), device('tablet')], 'iPad'), 'tablet')

    def test_no_or_multiple_devices(self):
        for devices in ([], [device('a'), device('b')], [device('simulator', reality='simulated')]):
            with self.assertRaises(ValueError):
                select_device(devices, 'iPad')

    def test_explicit_selection(self):
        for selector in ('b', 'name-b', 'udid-b'):
            self.assertEqual(select_device([device('a'), device('b')], 'iPad', selector), 'b')
        with self.assertRaises(ValueError):
            select_device([device('a', 'iPhone')], 'iPad', 'a')
        with self.assertRaises(ValueError):
            select_device([device('a', reality='simulated')], 'iPad', 'a')

    def test_bundle_copies_project_assets_and_framework_lua(self):
        from tempfile import TemporaryDirectory
        from pathlib import Path

        with TemporaryDirectory() as directory:
            workspace = Path(directory)
            copy_tree('lua', workspace, lua_only=True)
            copy_tree('apps/adventure-arena', workspace)
            self.assertTrue((workspace / 'lua/embedded/UIKit.lua').is_file())
            self.assertTrue((workspace / 'apps/adventure-arena/init.lua').is_file())
            self.assertTrue((workspace / 'apps/adventure-arena/assets/zork1.jpg').is_file())

    def test_app_slug_resolves_to_apps_directory_and_entry(self):
        app, entry = resolve_app_and_entry('adventure-arena', 'adventure-arena/init.lua')
        self.assertEqual(app, 'apps/adventure-arena')
        self.assertEqual(entry, 'apps/adventure-arena/init.lua')

    def test_missing_app_fails_instead_of_creating_empty_bundle(self):
        with self.assertRaisesRegex(ValueError, 'app directory does not exist'):
            resolve_app_and_entry('missing-app', 'missing-app/init.lua')

    def test_profile_identifiers(self):
        self.assertTrue(matches('TEAM.org.luaobjc.*', 'TEAM.org.luaobjc.studio'))
        self.assertTrue(matches('TEAM.org.luaobjc.studio', 'TEAM.org.luaobjc.studio'))
        self.assertFalse(matches('OTHER.*', 'TEAM.org.luaobjc.studio'))
        self.assertFalse(matches('TEAM.org.luaobjc.host', 'TEAM.org.luaobjc.studio'))


if __name__ == '__main__':
    unittest.main()
