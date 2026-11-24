"""Fast, offline regression checks for iOS app packaging and deployment."""
import os
from pathlib import Path
import plistlib
import subprocess
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from bundle import main as bundle_app, resolve_app_and_entry
from deploy import device_list_command, select_device
from sign import matches, signing_entitlements
from simulator_entitlements import entitlements


def device(identifier, kind='iPad', reality='physical'):
    return {'identifier': identifier, 'hardwareProperties': {'deviceType': kind, 'reality': reality,
                                                             'udid': 'udid-' + identifier},
            'deviceProperties': {'name': 'name-' + identifier},
            'connectionProperties': {'tunnelState': 'connected', 'transportType': 'wired'}}


class DiscoveryTests(unittest.TestCase):
    def test_iphone_make_target_uses_device_override_or_iphone_default(self):
        environment = dict(os.environ, IPHONE_DEVICE='default-phone')
        environment.pop('DEVICE', None)
        for arguments, expected in (([], 'default-phone'), (['DEVICE=other-phone'], 'other-phone'),
                                    (['IPHONE_DEVICE='], None)):
            with self.subTest(arguments=arguments):
                plan = subprocess.check_output(
                    ['make', '-n', 'iphone', 'APP=adventure-arena', *arguments],
                    env=environment, text=True)
                self.assertIn('--sdk iphoneos', plan)
                self.assertIn('--device-family 1', plan)
                self.assertIn('--app "apps/adventure-arena"', plan)
                self.assertIn('--display-name "Elsewhere"', plan)
                deploy = next(line for line in plan.splitlines() if 'python3 scripts/ipad/deploy.py' in line)
                self.assertIn('--device-type "iPhone"', deploy)
                if expected:
                    self.assertIn(f'--device "{expected}"', deploy)
                else:
                    self.assertNotIn('--device "', deploy)

    def test_adventure_arena_simulator_bundle_has_valid_metadata_and_assets(self):
        plan = subprocess.check_output(
            ['make', '-n', 'ipad-simulator', 'APP=adventure-arena'], text=True)
        self.assertIn('--device-family 1,2', plan)
        with TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = root / 'AdventureArena.app'
            binary = root / 'binary'
            binary.touch()
            app = 'apps/adventure-arena'
            arguments = ['bundle.py', '--bundle', str(bundle), '--binary', str(binary),
                         '--sdk', 'iphonesimulator', '--identifier', 'org.luaobjc.adventure-arena',
                         '--minimum', '26.5', '--app', app, '--entry', f'{app}/init.lua',
                         '--display-name', 'Elsewhere', '--device-family', '1,2']
            with patch('sys.argv', arguments), patch('bundle.bundle_icon', return_value={}):
                bundle_app()
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            self.assertEqual(info['CFBundleDisplayName'], 'Elsewhere')
            self.assertEqual(info['CFBundleShortVersionString'], '1.0')
            self.assertEqual(info['CFBundleVersion'], '1')
            self.assertEqual(info['UIDeviceFamily'], [1, 2])
            self.assertIs(info['ITSAppUsesNonExemptEncryption'], False)
            self.assertTrue((bundle / info['CFBundleExecutable']).is_file())
            workspace = bundle / 'Workspace'
            self.assertTrue((workspace / 'lua/embedded/UIKit.lua').is_file())
            self.assertTrue((workspace / info['LRTLocalEntry']).is_file())
            self.assertTrue((workspace / app / 'assets/zork1.jpg').is_file())
            self.assertTrue((workspace / app / 'zilscript/zilscript/bootstrap.lua').is_file())
            self.assertFalse((workspace / app / 'Info.plist').exists())
            self.assertFalse((workspace / app / 'Assets.xcassets').exists())

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
