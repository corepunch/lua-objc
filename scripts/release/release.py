#!/usr/bin/env python3
"""Build, package and upload platform-specific releases without Xcode projects."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

from sign import sign_bundle, sign_store

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/ipad'))
from bundle import copy_tree


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def apps(path=None):
    records = json.loads((path or ROOT / 'scripts/release/apps.json').read_text())
    seen = set()
    for record in records:
        if not all(record.get(key) for key in ('app', 'product', 'platform', 'channels')):
            raise ValueError('Every release app must declare app, product, platform and channels')
        slug = record['app']
        if not re.fullmatch(r'[a-z][a-z0-9-]*', slug) or slug in seen:
            raise ValueError('Invalid or duplicate release app: ' + slug)
        seen.add(slug)
        if record['platform'] not in ('macos', 'ios', 'iphone', 'ipad'):
            raise ValueError('Unknown release platform for ' + slug)
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', record['product']):
            raise ValueError('Invalid release product for ' + slug)
        channels = record['channels']
        if not channels or any(c not in ('github', 'appStore') for c in channels) or len(channels) != len(set(channels)):
            raise ValueError('Invalid release channels for ' + slug)
        if record['platform'] != 'macos' and 'appStore' not in channels:
            raise ValueError('iOS releases require App Store signing')
        if 'appStore' in channels and not record.get('profileSecret'):
            raise ValueError('Missing profile secret for ' + slug)
        if 'appStore' in channels and not record.get('appStoreIdVariable'):
            raise ValueError('Missing App Store ID variable for ' + slug)
        for plugin in record.get('plugins', []):
            if plugin not in ('StorageScan', 'AudioStream'):
                raise ValueError('Unsupported macOS release plugin: ' + plugin)
    return records


def release_version(version):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('Expected a version like 1.2.3')
    return version


def build_number(number):
    # Apple's CFBundleVersion limits: major <= 4 digits, minor/patch <= 2.
    if not re.fullmatch(r'[1-9][0-9]{0,3}(?:\.[0-9]{1,2}){0,2}', number):
        raise ValueError('BUILD_NUMBER must be an Apple build number, e.g. 123 or 123.1')
    return number


def sdk_metadata(sdk):
    developer = Path(os.environ.get('DEVELOPER_DIR') or subprocess.check_output(
        ['xcode-select', '-p'], text=True).strip())
    version = plistlib.loads((developer.parent / 'version.plist').read_bytes())
    sdk_path = Path(subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip())
    settings = plistlib.loads((sdk_path / 'SDKSettings.plist').read_bytes())
    system = plistlib.loads((sdk_path / 'System/Library/CoreServices/SystemVersion.plist').read_bytes())
    xcode = version['CFBundleShortVersionString'].split('.')
    return {'DTPlatformName': sdk, 'DTSDKName': settings['CanonicalName'],
            'DTPlatformVersion': settings['Version'], 'DTSDKBuild': system['ProductBuildVersion'],
            'DTPlatformBuild': system['ProductBuildVersion'],
            'DTXcode': ''.join([xcode[0], *(part.zfill(1) for part in (xcode[1:] + ['0', '0'])[:2])]),
            'DTXcodeBuild': version['ProductBuildVersion'],
            'BuildMachineOSBuild': subprocess.check_output(['sw_vers', '-buildVersion'], text=True).strip()}


def compile_command(record, out):
    if record['platform'] == 'macos':
        return ['make', '-f', 'scripts/release/macos.mk', 'PLUGINS=' + ' '.join(record.get('plugins', []))]
    return ['make', '-f', 'scripts/ipad/build.mk', 'SDK=iphoneos', 'app', 'APP=' + record['app'],
            'APP_BUNDLE=' + record['product'], 'BUNDLE_ID=' + record['identifier'],
            'APP_DISPLAY_NAME=' + record['displayName'],
            'DEVICE_FAMILY=' + {'ios': '1,2', 'iphone': '1', 'ipad': '2'}[record['platform']],
            'FILE_SHARING=0', 'BUNDLE=' + str(out)]


def bundle_macos(record, bundle):
    native = Path('build/release/native/macos-arm64')
    contents = bundle / 'Contents'
    for folder in ('MacOS', 'Frameworks', 'Resources'):
        (contents / folder).mkdir(parents=True, exist_ok=True)
    shutil.copy2(native / 'Launcher', contents / 'MacOS' / record['product'])
    for library in ['AppKit', *record.get('plugins', [])]:
        shutil.copy2(native / (library + '.dylib'), contents / 'Frameworks' / (library + '.dylib'))
    copy_tree('lua', contents / 'Resources', lua_only=True)
    copy_tree('apps/' + record['app'], contents / 'Resources', runtime_only=True)
    shutil.copy2(record['plist'], contents / 'Info.plist')
    (contents / 'PkgInfo').write_bytes(b'APPL????')


def compile_assets(record, bundle, sdk):
    if not record.get('assets'):
        return {}
    resources = bundle / 'Contents/Resources' if sdk == 'macosx' else bundle
    partial = bundle.parent / 'asset-info.plist'
    targets = {'macos': ['mac'], 'ios': ['iphone', 'ipad'], 'iphone': ['iphone'], 'ipad': ['ipad']}[record['platform']]
    devices = [argument for target in targets for argument in ('--target-device', target)]
    run('xcrun', '--sdk', sdk, 'actool', record['assets'], '--compile', resources,
        '--platform', sdk, '--minimum-deployment-target', '26.0' if sdk == 'macosx' else '26.5',
        '--app-icon', 'AppIcon', '--output-partial-info-plist', partial, *devices)
    return plistlib.loads(partial.read_bytes())


def build(record, version, number):
    out = Path('build/release') / record['app']
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    bundle = out / 'unsigned' / (record['product'] + '.app')
    bundle.parent.mkdir()
    run(*compile_command(record, bundle))
    sdk = 'macosx' if record['platform'] == 'macos' else 'iphoneos'
    if sdk == 'macosx':
        bundle_macos(record, bundle)
    plist = bundle / ('Contents/Info.plist' if sdk == 'macosx' else 'Info.plist')
    info = plistlib.loads(plist.read_bytes())
    # Generated bundle metadata is never written back to the source plist.
    if sdk == 'iphoneos':
        info.pop('CFBundleIcons', None)
        info['ITSAppUsesNonExemptEncryption'] = False
    info.update(compile_assets(record, bundle, sdk))
    info.update(sdk_metadata(sdk))
    info.update(CFBundleShortVersionString=version, CFBundleVersion=number)
    plist.write_bytes(plistlib.dumps(info))
    executables = ([bundle / 'Contents/MacOS' / record['product'], *sorted((bundle / 'Contents/Frameworks').glob('*.dylib'))]
                   if sdk == 'macosx' else [bundle / info['CFBundleExecutable']])
    (out / 'symbols').mkdir()
    for executable in executables:
        run('xcrun', 'dsymutil', executable, '-o', out / 'symbols' / (executable.name + '.dSYM'))
    return bundle


def copy_bundle(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    run('ditto', source, destination)
    return destination


def notarize(path):
    run('xcrun', 'notarytool', 'submit', path, '--key', os.environ['NOTARY_KEY'],
        '--key-id', os.environ['NOTARY_KEY_ID'], '--issuer', os.environ['NOTARY_ISSUER_ID'], '--wait')


def dmg(record, source, version, unsigned):
    out = source.parent.parent
    bundle = copy_bundle(source, out / 'download' / source.name)
    identity = '-' if unsigned else 'Developer ID Application'
    requested = plistlib.loads(Path(record['entitlements']).read_bytes()) if record.get('entitlements') else None
    entitlements = out / 'download-entitlements.plist'
    if requested:
        entitlements.write_bytes(plistlib.dumps(requested))
    sign_bundle(bundle, identity, entitlements if requested else None, hardened=not unsigned)
    if not unsigned:
        archive = out / 'notary.zip'
        run('ditto', '-c', '-k', '--keepParent', bundle, archive)
        notarize(archive)
        run('xcrun', 'stapler', 'staple', bundle)
        run('spctl', '--assess', '--type', 'execute', bundle)
    stage = out / 'dmg'
    copy_bundle(bundle, stage / bundle.name)
    (stage / 'Applications').symlink_to('/Applications')
    artifact = out / (record['product'] + '-' + version + '.dmg')
    run('hdiutil', 'create', '-quiet', '-volname', record['product'] + ' ' + version,
        '-srcfolder', stage, '-fs', 'APFS', '-format', 'UDZO', artifact)
    if not unsigned:
        run('codesign', '--sign', identity, '--timestamp', artifact)
        notarize(artifact)
        run('xcrun', 'stapler', 'staple', artifact)
        run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', artifact)
    return artifact


def store_package(record, source, version, profile):
    out = source.parent.parent
    bundle = copy_bundle(source, out / 'store' / source.name)
    requested = plistlib.loads(Path(record['entitlements']).read_bytes()) if record.get('entitlements') else None
    sign_store(bundle, record['platform'], profile, requested)
    plist = bundle / ('Contents/Info.plist' if record['platform'] == 'macos' else 'Info.plist')
    shutil.copy2(plist, out / 'upload-info.plist')
    if record['platform'] == 'macos':
        identity = os.environ.get('APPSTORE_INSTALLER_IDENTITY', '3rd Party Mac Developer Installer')
        artifact = out / (record['product'] + '-' + version + '.pkg')
        run('productbuild', '--component', bundle, '/Applications', '--sign', identity, artifact)
        run('pkgutil', '--check-signature', artifact)
    else:
        artifact = out / (record['product'] + '-' + version + '.ipa')
        with tempfile.TemporaryDirectory(dir=out) as directory:
            payload = Path(directory) / 'Payload'
            copy_bundle(bundle, payload / bundle.name)
            run('ditto', '-c', '-k', '--keepParent', payload, artifact)
    return artifact


def upload_command(artifact, platform, info, validate=False):
    command = ['xcrun', 'altool', '--validate-app' if validate else '--upload-package', str(artifact),
               '--platform', 'macos' if platform == 'macos' else 'ios',
               '--apple-id', os.environ['APPSTORE_APP_ID'], '--bundle-id', info['CFBundleIdentifier'],
               '--bundle-version', info['CFBundleVersion'],
               '--bundle-short-version-string', info['CFBundleShortVersionString'],
               '--api-key', os.environ['APPSTORE_KEY_ID'], '--api-issuer', os.environ['APPSTORE_ISSUER_ID'],
               '--output-format', 'json']
    if not validate:
        command.append('--wait')
    return command


def upload(artifact, platform, info):
    # altool locates AuthKey_<id>.p8 here; use a disposable directory, never HOME.
    with tempfile.TemporaryDirectory() as directory:
        key = Path(directory) / ('AuthKey_' + os.environ['APPSTORE_KEY_ID'] + '.p8')
        shutil.copyfile(os.environ['APPSTORE_KEY'], key)
        key.chmod(0o600)
        environment = dict(os.environ, API_PRIVATE_KEYS_DIR=directory)
        run(*upload_command(artifact, platform, info, validate=True), env=environment)
        run(*upload_command(artifact, platform, info), env=environment)


def publish(records, version):
    artifacts = []
    for record in records:
        if 'github' not in record['channels']:
            continue
        extension = 'dmg' if record['platform'] == 'macos' else 'ipa'
        path = Path('build/release') / record['app'] / (record['product'] + '-' + version + '.' + extension)
        if not path.is_file() or not path.with_suffix(path.suffix + '.signed').is_file():
            raise ValueError('Missing signed release artifact: ' + str(path))
        artifacts.append(str(path))
        # Store packages are downloadable too, and are the exact upload input.
        package = path.with_suffix('.pkg')
        if package.is_file() and package.with_suffix('.pkg.signed').is_file():
            artifacts.append(str(package))
    tag = 'v' + version
    exists = subprocess.run(['gh', 'release', 'view', tag], stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL).returncode == 0
    if exists:
        run('gh', 'release', 'upload', tag, *artifacts, '--clobber')
    else:
        run('gh', 'release', 'create', tag, *artifacts, '--title', version, '--generate-notes',
            '--target', subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('matrix', 'build', 'release', 'publish', 'upload'))
    parser.add_argument('--app')
    parser.add_argument('--version')
    parser.add_argument('--build-number', default='1')
    parser.add_argument('--unsigned', action='store_true')
    parser.add_argument('--store', action='store_true')
    parser.add_argument('--profile', type=Path)
    args = parser.parse_args()
    os.chdir(ROOT)
    records = apps()
    if args.app:
        records = [record for record in records if record['app'] == args.app]
        if not records:
            parser.error('Unknown release app: ' + args.app)
    if args.command == 'matrix':
        print(json.dumps({'include': records}, separators=(',', ':')))
        return
    version = release_version(args.version or '')
    if args.command == 'publish':
        publish(records, version)
        return
    number = build_number(args.build_number)
    if args.unsigned and args.store:
        parser.error('App Store builds cannot be unsigned')
    if args.command == 'release':
        if args.store and (not args.profile or len(records) != 1):
            parser.error('--store requires --app and --profile for that app')
        if not args.store and not args.unsigned and any(record['platform'] != 'macos' for record in records):
            parser.error('iOS releases require --store and --profile; select --app to release a macOS app')
    for record in records:
        out = Path('build/release') / record['app']
        if args.command == 'upload':
            extension = 'pkg' if record['platform'] == 'macos' else 'ipa'
            artifact = out / (record['product'] + '-' + version + '.' + extension)
            if 'appStore' not in record['channels']:
                continue
            if not artifact.is_file() or not artifact.with_suffix(artifact.suffix + '.signed').is_file():
                raise ValueError('Missing signed App Store package: ' + str(artifact))
            upload(artifact, record['platform'], plistlib.loads((out / 'upload-info.plist').read_bytes()))
            continue
        source = build(record, version, number)
        if args.command == 'build':
            continue
        artifacts = []
        if record['platform'] == 'macos' and 'github' in record['channels']:
            artifacts.append(dmg(record, source, version, args.unsigned))
        if args.store and 'appStore' in record['channels']:
            artifacts.append(store_package(record, source, version, args.profile))
        if not args.unsigned:
            for artifact in artifacts:
                artifact.with_suffix(artifact.suffix + '.signed').touch()


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
