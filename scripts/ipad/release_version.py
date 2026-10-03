#!/usr/bin/env python3
"""Set the TestFlight version from an Xcode Cloud release tag."""
import argparse
from pathlib import Path
import plistlib
import re


def version_from_tag(tag: str, prefix: str = 'release') -> str:
    match = re.fullmatch(re.escape(prefix) + r'/([0-9]+\.[0-9]+\.[0-9]+)', tag)
    if not match:
        raise ValueError(f'Expected a tag like {prefix}/1.2.3')
    return match[1]


def set_version(plist_path: Path, version: str) -> None:
    info = plistlib.loads(plist_path.read_bytes())
    info['CFBundleShortVersionString'] = version
    plist_path.write_bytes(plistlib.dumps(info, sort_keys=False))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('plist', type=Path)
    parser.add_argument('--prefix', default='release', help='tag prefix before the version')
    args = parser.parse_args()
    set_version(args.plist, version_from_tag(args.tag, args.prefix))


if __name__ == '__main__':
    main()
