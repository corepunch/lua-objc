#!/usr/bin/env python3
"""Bundle a standalone Lua app, its framework modules, and runtime assets."""
import argparse
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ElementTree


def check_backend(app):
    """A build that ships saves to the app's own Appwrite project.

    A `<Backend>` without `project` uses our development project, whose
    accounts every app shares (docs/backend.md): fine on the simulator and
    under `make run`, refused for a device or a release."""
    manifest = Path(app) / 'app.xml'
    if not manifest.is_file():
        return
    for backend in ElementTree.parse(manifest).getroot().iter('Backend'):
        if not backend.get('project'):
            raise ValueError(
                f'{manifest}: <Backend> uses the development project, which is not for builds that ship. '
                'Create an Appwrite project for the app and name it: '
                '<Backend provider="appwrite" endpoint="https://fra.cloud.appwrite.io/v1" project="<project ID>" />')


def copy_tree(source, workspace, lua_only=False, runtime_only=False):
    source = Path(source)
    for path in source.rglob('*'):
        relative = path.relative_to(source)
        if not path.is_file() or any(part.startswith('.') or part in ('Build', '__pycache__', 'ci_scripts', 'store-assets', 'fastlane')
                                   or part.endswith(('.xcodeproj', '.xcworkspace', '.xcassets')) for part in relative.parts):
            continue
        if lua_only and path.suffix not in ('.lua', '.etlua'):
            continue
        if runtime_only and path.suffix in ('.md', '.plist', '.entitlements', '.xcprivacy', '.sh', '.py', '.c', '.m', '.h'):
            continue
        target = workspace / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)


def asset_kits(*roots):
    """Shared asset kits (assets/kenney/<kit>) the app's sources name.

    Kits live once at the repository root rather than inside each app, so a
    bundle copies exactly the kits its Lua and templates refer to."""
    kits = set()
    for root in roots:
        for path in Path(root).rglob('*'):
            if path.is_file() and path.suffix in ('.lua', '.etlua', '.xml'):
                kits.update(re.findall(r'assets/kenney/([a-z0-9-]+)/', path.read_text(errors='ignore')))
    return sorted(kit for kit in kits if (Path('assets/kenney') / kit).is_dir())


def resolve_app_and_entry(app, entry):
    """Resolve app slugs while keeping app and entry paths in sync."""
    source = Path(app)
    if not source.is_dir() and (Path('apps') / source).is_dir():
        source = Path('apps') / source
        if entry == f'{app}/init.lua':
            entry = f'{source.as_posix()}/init.lua'
    if not source.is_dir():
        raise ValueError(f'app directory does not exist: {app}')
    # Entry paths are workspace-relative (for example apps/foo/init.lua).
    if not Path(entry).is_file():
        raise ValueError(f'app entry does not exist: {entry}')
    return source.as_posix(), entry


def bundle_icon(app, bundle, sdk, minimum, device_family):
    """Let Apple's asset compiler supply icon sizes and bundle metadata."""
    assets = Path(app) / 'Assets.xcassets'
    if not assets.is_dir():
        shutil.copy2('ios/LuaRuntime/AppIcon.png', bundle / 'AppIcon.png')
        return {}
    # A reused bundle must not retain the runtime's generic icon.
    (bundle / 'AppIcon.png').unlink(missing_ok=True)
    targets = ['iphone' if family == '1' else 'ipad' for family in device_family.split(',')]
    devices = [argument for target in targets for argument in ('--target-device', target)]
    with tempfile.TemporaryDirectory(dir=bundle.parent) as directory:
        partial = Path(directory) / 'asset-info.plist'
        subprocess.run(['xcrun', '--sdk', sdk, 'actool', str(assets), '--compile', str(bundle),
                        '--platform', sdk, '--minimum-deployment-target', minimum,
                        '--app-icon', 'AppIcon', '--output-partial-info-plist', str(partial),
                        *devices], check=True)
        return plistlib.loads(partial.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('binary', 'bundle', 'sdk', 'identifier', 'minimum'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--app', required=True)
    parser.add_argument('--entry', required=True)
    parser.add_argument('--display-name', required=True)
    parser.add_argument('--device-family', choices=('1', '2', '1,2'), required=True)
    parser.add_argument('--file-sharing', action='store_true')
    parser.add_argument('--overlay', action='append', default=[],
                        help='copy this folder\'s files into the workspace at their paths relative to it')
    args = parser.parse_args()
    try:
        args.app, args.entry = resolve_app_and_entry(args.app, args.entry)
        if args.sdk == 'iphoneos':
            check_backend(args.app)
    except ValueError as error:
        parser.error(str(error))
    bundle = Path(args.bundle)
    bundle.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.binary, bundle / 'LuaStudio')
    info = plistlib.loads(Path('ios/LuaRuntime/Info.plist').read_bytes())
    app_info = Path(args.app) / 'Info.plist'
    if app_info.is_file():
        info.update(plistlib.loads(app_info.read_bytes()))
    info.update(CFBundleDisplayName=args.display_name, CFBundleName=args.display_name,
                CFBundleExecutable='LuaStudio', CFBundleIdentifier=args.identifier,
                CFBundleSupportedPlatforms=['iPhoneOS' if args.sdk == 'iphoneos' else 'iPhoneSimulator'],
                UIDeviceFamily=[int(family) for family in args.device_family.split(',')], MinimumOSVersion=args.minimum,
                LRTLocalEntry=args.entry)
    if 2 in info['UIDeviceFamily'] and 'UISupportedInterfaceOrientations~ipad' not in info:
        info['UISupportedInterfaceOrientations~ipad'] = [
            'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
            'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']
    if args.file_sharing:
        info.update(UIFileSharingEnabled=True, LSSupportsOpeningDocumentsInPlace=True)
    else:
        info.pop('UIFileSharingEnabled', None)
        info.pop('LSSupportsOpeningDocumentsInPlace', None)
    if (Path(args.app) / 'Assets.xcassets').is_dir():
        info.pop('CFBundleIcons', None)
        info.pop('CFBundleIcons~ipad', None)
    info.update(bundle_icon(args.app, bundle, args.sdk, args.minimum, args.device_family))
    privacy = Path(args.app) / 'PrivacyInfo.xcprivacy'
    if privacy.is_file():
        shutil.copy2(privacy, bundle / privacy.name)
    else:
        (bundle / 'PrivacyInfo.xcprivacy').unlink(missing_ok=True)
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
    workspace = bundle / 'Workspace'
    if workspace.exists():
        shutil.rmtree(workspace)
    copy_tree('lua', workspace, lua_only=True)
    copy_tree(args.app, workspace, runtime_only=True)
    if args.app == 'apps/studio':
        copy_tree('demo/playground', workspace)
    for kit in asset_kits(args.app, *(['demo/playground'] if args.app == 'apps/studio' else [])):
        copy_tree(f'assets/kenney/{kit}', workspace, runtime_only=True)
    for overlay in args.overlay:
        root = Path(overlay)
        for path in root.rglob('*'):
            relative = path.relative_to(root)
            if path.is_file() and not any(part.startswith('.') for part in relative.parts):
                target = workspace / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
    (bundle / 'PkgInfo').write_bytes(b'APPL????')


if __name__ == '__main__':
    main()
