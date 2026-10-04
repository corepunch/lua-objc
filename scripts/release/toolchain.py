#!/usr/bin/env python3
"""Select a stable Apple toolchain for release builds and uploads."""
import os
from pathlib import Path
import plistlib
import re


def select_xcode(applications):
    candidates = []
    for app in applications.glob('Xcode*.app'):
        plist = app / 'Contents/version.plist'
        if not plist.is_file():
            continue
        info = plistlib.loads(plist.read_bytes())
        version = info['CFBundleShortVersionString']
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version):
            continue
        number = tuple(map(int, version.split('.')))
        if (number >= (26, 5) and not re.search('beta|RC', app.name, re.I)
                and not re.search(r'[a-z]$', info['ProductBuildVersion'])):
            candidates.append((number, app))
    if not candidates:
        raise ValueError('A stable Xcode 26.5+ toolchain is required')
    return max(candidates)[1] / 'Contents/Developer'


if __name__ == '__main__':
    selected = select_xcode(Path('/Applications'))
    print('Release toolchain: ' + str(selected))
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        print('DEVELOPER_DIR=' + str(selected), file=output)
