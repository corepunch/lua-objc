"""Fast, offline regression checks for iPad deployment selection."""
import unittest
from deploy import select_ipad
from sign import matches


def device(identifier, kind='iPad', state='connected', transport='localNetwork'):
    return {'identifier': identifier, 'hardwareProperties': {'deviceType': kind, 'udid': 'udid-' + identifier},
            'deviceProperties': {'name': 'name-' + identifier},
            'connectionProperties': {'tunnelState': state, 'transportType': transport}}


class DiscoveryTests(unittest.TestCase):
    def test_ipad_ignores_iphone(self):
        self.assertEqual(select_ipad([device('phone', 'iPhone'), device('tablet')]), 'tablet')

    def test_wired_ipad_without_tunnel(self):
        self.assertEqual(select_ipad([device('tablet', state='disconnected', transport='wired')]), 'tablet')

    def test_no_or_multiple_devices(self):
        for devices in ([], [device('a'), device('b')], [device('a', state='disconnected')]):
            with self.assertRaises(ValueError):
                select_ipad(devices)

    def test_explicit_selection(self):
        for selector in ('b', 'name-b', 'udid-b'):
            self.assertEqual(select_ipad([device('a'), device('b')], selector), 'b')
        with self.assertRaises(ValueError):
            select_ipad([device('a', 'iPhone')], 'a')

    def test_profile_identifiers(self):
        self.assertTrue(matches('TEAM.org.luaobjc.*', 'TEAM.org.luaobjc.studio'))
        self.assertTrue(matches('TEAM.org.luaobjc.studio', 'TEAM.org.luaobjc.studio'))
        self.assertFalse(matches('OTHER.*', 'TEAM.org.luaobjc.studio'))
        self.assertFalse(matches('TEAM.org.luaobjc.host', 'TEAM.org.luaobjc.studio'))


if __name__ == '__main__':
    unittest.main()
