#!/usr/bin/env python3
"""Bundle a standalone Lua app, its framework modules, and runtime assets."""
import argparse
from pathlib import Path
import plistlib
import shutil


def copy_tree(source, workspace, lua_only=False):
    source = Path(source)
    for path in source.rglob('*'):
        relative = path.relative_to(source)
        if not path.is_file() or any(part.startswith('.') for part in relative.parts):
            continue
        if lua_only and path.suffix not in ('.lua', '.etlua'):
            continue
        target = workspace / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('binary', 'bundle', 'sdk', 'identifier', 'minimum'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--app', required=True)
    parser.add_argument('--entry', required=True)
    parser.add_argument('--display-name', required=True)
    parser.add_argument('--device-family', type=int, choices=(1, 2), required=True)
    parser.add_argument('--file-sharing', action='store_true')
    args = parser.parse_args()
    bundle = Path(args.bundle)
    bundle.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.binary, bundle / 'LuaStudio')
    info = plistlib.loads(Path('ios/LuaRuntime/Info.plist').read_bytes())
    info.update(CFBundleDisplayName=args.display_name, CFBundleName=args.display_name,
                CFBundleExecutable='LuaStudio', CFBundleIdentifier=args.identifier,
                CFBundleSupportedPlatforms=['iPhoneOS' if args.sdk == 'iphoneos' else 'iPhoneSimulator'],
                UIDeviceFamily=[args.device_family], MinimumOSVersion=args.minimum,
                LRTLocalEntry=args.entry)
    if args.file_sharing:
        info.update(UIFileSharingEnabled=True, LSSupportsOpeningDocumentsInPlace=True)
    else:
        info.pop('UIFileSharingEnabled', None)
        info.pop('LSSupportsOpeningDocumentsInPlace', None)
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copy2('ios/LuaRuntime/AppIcon.png', bundle / 'AppIcon.png')
    workspace = bundle / 'Workspace'
    if workspace.exists():
        shutil.rmtree(workspace)
    copy_tree('lua', workspace, lua_only=True)
    copy_tree(args.app, workspace)
    if args.app == 'apps/studio':
        copy_tree('apps/playground', workspace)
    (bundle / 'PkgInfo').write_bytes(b'APPL????')


if __name__ == '__main__':
    main()
