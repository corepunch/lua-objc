#!/usr/bin/env python3
"""Find a physical iPhone or iPad, then sign/install/launch a bundled Lua app."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


def device_list_command(requested, output):
    command = ['xcrun', 'devicectl', 'list', 'devices']
    if not requested:
        # Match devicectl's displayed State; tunnel and transport can remain
        # connected for paired devices that are unavailable for deployment.
        command += ['--filter', "State BEGINSWITH 'available' OR State = 'connected'"]
    return command + ['--json-output', output]


def select_device(devices, device_type, requested=None):
    candidates = []
    for device in devices:
        hardware = device.get('hardwareProperties', {})
        properties = device.get('deviceProperties', {})
        identity = device.get('identifier', '')
        name = properties.get('name', '')
        is_target_type = (hardware.get('deviceType') == device_type
                          or device_type.lower() in hardware.get('marketingName', '').lower())
        if not is_target_type or hardware.get('reality') != 'physical':
            continue
        if requested:
            if requested in (identity, name, hardware.get('udid')):
                candidates.append(identity)
        else:
            candidates.append(identity)
    if len(candidates) != 1:
        variable = 'IPHONE_DEVICE' if device_type == 'iPhone' else 'IPAD_DEVICE'
        raise ValueError(f'Expected exactly one available physical {device_type}; found {len(candidates)}. '
                         f'Run make list-devices and set {variable}=<identifier>.')
    return candidates[0]


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--device')
    parser.add_argument('--device-type', choices=('iPhone', 'iPad'), default='iPad')
    parser.add_argument('--team')
    parser.add_argument('--profile')
    parser.add_argument('--simulator', action='store_true')
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    identifier = plistlib.loads((bundle / 'Info.plist').read_bytes())['CFBundleIdentifier']
    if args.simulator:
        payload = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
        devices = [d for group in payload['devices'].values() for d in group
                   if args.device_type in d['name'] and d.get('isAvailable')]
        if args.device:
            devices = [d for d in devices if args.device in (d['udid'], d['name'])]
        devices.sort(key=lambda d: (d['state'] != 'Booted', d['name']))
        if not devices:
            raise SystemExit('No available iPad simulator. Install an iOS runtime in Xcode.')
        device = devices[0]
        if device['state'] != 'Booted':
            run('xcrun', 'simctl', 'boot', device['udid'])
        run('xcrun', 'simctl', 'bootstatus', device['udid'], '-b')
        run('open', '-a', 'Simulator')
        run('xcrun', 'simctl', 'install', device['udid'], bundle)
        run('xcrun', 'simctl', 'launch', '--terminate-running-process', device['udid'], identifier)
        print('Launched on ' + device['name'] + ' (' + device['udid'] + ')')
        return
    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary) / 'devices.json'
        run(*device_list_command(args.device, output))
        payload = json.loads(output.read_text())
    device = select_device(payload['result']['devices'], args.device_type, args.device)
    print('Selected ' + args.device_type + ' ' + device, flush=True)
    sign = [sys.executable, 'scripts/ipad/sign.py', str(bundle), '--device', device]
    # The signer checks provisioning device UDIDs after resolving CoreDevice's identifier below.
    matching = next(d for d in payload['result']['devices'] if d['identifier'] == device)
    sign[-1] = matching.get('hardwareProperties', {}).get('udid', device)
    if args.team:
        sign += ['--team', args.team]
    if args.profile:
        sign += ['--profile', args.profile]
    run(*sign)
    run('xcrun', 'devicectl', 'device', 'install', 'app', '--device', device, bundle)
    run('xcrun', 'devicectl', 'device', 'process', 'launch', '--device', device, '--terminate-existing', identifier)


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error))
    except subprocess.CalledProcessError as error:
        raise SystemExit(f'Deployment step failed (exit {error.returncode}). See the tool error above; unlock the device if launch was denied.')
