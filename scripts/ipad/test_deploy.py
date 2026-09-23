"""Fast, offline regression checks for iPad deployment selection."""
import unittest
from deploy import device_list_command, select_ipad
from sign import matches, signing_entitlements
from simulator_entitlements import entitlements


def device(identifier, kind='iPad', reality='physical'):
    return {'identifier': identifier, 'hardwareProperties': {'deviceType': kind, 'reality': reality,
                                                             'udid': 'udid-' + identifier},
            'deviceProperties': {'name': 'name-' + identifier},
            'connectionProperties': {'tunnelState': 'connected', 'transportType': 'wired'}}


class DiscoveryTests(unittest.TestCase):
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
        self.assertEqual(select_ipad([device('phone', 'iPhone'), device('tablet')]), 'tablet')

    def test_auto_discovery_uses_displayed_availability(self):
        self.assertEqual(device_list_command(None, '/tmp/devices.json'),
                         ['xcrun', 'devicectl', 'list', 'devices', '--filter',
                          "State BEGINSWITH 'available' OR State = 'connected'",
                          '--json-output', '/tmp/devices.json'])
        self.assertEqual(device_list_command('tablet', '/tmp/devices.json'),
                         ['xcrun', 'devicectl', 'list', 'devices', '--json-output', '/tmp/devices.json'])

    def test_simulated_connected_ipad_is_not_a_candidate(self):
        self.assertEqual(select_ipad([device('simulator', reality='simulated'), device('tablet')]), 'tablet')

    def test_no_or_multiple_devices(self):
        for devices in ([], [device('a'), device('b')], [device('simulator', reality='simulated')]):
            with self.assertRaises(ValueError):
                select_ipad(devices)

    def test_explicit_selection(self):
        for selector in ('b', 'name-b', 'udid-b'):
            self.assertEqual(select_ipad([device('a'), device('b')], selector), 'b')
        with self.assertRaises(ValueError):
            select_ipad([device('a', 'iPhone')], 'a')
        with self.assertRaises(ValueError):
            select_ipad([device('a', reality='simulated')], 'a')

    def test_profile_identifiers(self):
        self.assertTrue(matches('TEAM.org.luaobjc.*', 'TEAM.org.luaobjc.studio'))
        self.assertTrue(matches('TEAM.org.luaobjc.studio', 'TEAM.org.luaobjc.studio'))
        self.assertFalse(matches('OTHER.*', 'TEAM.org.luaobjc.studio'))
        self.assertFalse(matches('TEAM.org.luaobjc.host', 'TEAM.org.luaobjc.studio'))


if __name__ == '__main__':
    unittest.main()
