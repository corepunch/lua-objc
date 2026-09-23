#!/usr/bin/env python3
"""Bundle the standalone editor, framework Lua, and editable starter project."""
import argparse
from pathlib import Path
import plistlib
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('binary', 'bundle', 'sdk', 'identifier', 'minimum'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    bundle = Path(args.bundle)
    bundle.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.binary, bundle / 'LuaStudio')
    info = plistlib.loads(Path('ios/LuaRuntime/Info.plist').read_bytes())
    info.update(CFBundleDisplayName='Lua Studio', CFBundleName='Lua Studio',
                CFBundleExecutable='LuaStudio', CFBundleIdentifier=args.identifier,
                CFBundleSupportedPlatforms=['iPhoneOS' if args.sdk == 'iphoneos' else 'iPhoneSimulator'],
                UIDeviceFamily=[2], MinimumOSVersion=args.minimum,
                LRTLocalEntry='apps/studio/init.lua',
                UIFileSharingEnabled=True, LSSupportsOpeningDocumentsInPlace=True)
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copy2('ios/LuaRuntime/AppIcon.png', bundle / 'AppIcon.png')
    workspace = bundle / 'Workspace'
    if workspace.exists():
        shutil.rmtree(workspace)
    for folder in ('lua', 'apps/studio', 'apps/playground'):
        source = Path(folder)
        for path in source.rglob('*'):
            if path.is_file() and '.git' not in path.parts and (path.suffix in ('.lua', '.etlua') or folder == 'apps/studio' and 'Documents' in path.parts):
                target = workspace / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
    (bundle / 'PkgInfo').write_bytes(b'APPL????')


if __name__ == '__main__':
    main()
