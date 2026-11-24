#!/usr/bin/env python3
"""Resolve the requested simulator to one available device UDID."""
import json
import subprocess
import sys


def select_device(devices, requested):
    if requested:
        return [device for device in devices if requested in (device['name'], device['udid'])]

    phones = [device for device in devices
              if '.SimDeviceType.iPhone-' in device.get('deviceTypeIdentifier', '')]
    preferred = [device for device in phones if device['name'] == 'iPhone 17']
    return preferred or phones


if __name__ == '__main__':
    requested = sys.argv[1]
    result = subprocess.run(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'],
                            capture_output=True, text=True)
    if result.returncode:
        sys.exit(result.stderr.strip() or 'Could not list available simulator devices.')
    devices = [device for group in json.loads(result.stdout)['devices'].values() for device in group]
    matches = select_device(devices, requested)
    if len(matches) != 1:
        target = f' matching {requested!r}' if requested else ' for the default iPhone'
        sys.exit(f'Found {len(matches)} available simulators{target}. Run '
                 '`xcrun simctl list devices available` and pass DEVICE=<UDID>.')
    print(matches[0]['udid'])
