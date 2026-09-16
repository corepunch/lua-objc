"""Simulator Security reads entitlements from Mach-O sections, not the host signature."""
import argparse
from pathlib import Path
import plistlib


def entitlements(identifier):
    app_id = 'SIMULATOR.' + identifier
    return {'application-identifier': app_id, 'keychain-access-groups': [app_id]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identifier', required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.write_bytes(plistlib.dumps(entitlements(args.identifier)))
