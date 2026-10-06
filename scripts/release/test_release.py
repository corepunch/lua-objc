"""Offline release regression tests; no keychain, windows or network."""
from copy import deepcopy
from datetime import datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile
from unittest.mock import patch

from credentials import required_secrets
from release import apps, build_number, bundle_macos, compile_command, publish, release_version, store_package, upload
from bundle import copy_tree, main as bundle_app
from sign import distribution_identity, profile_entitlements, sign_bundle
from toolchain import select_xcode


def profile(platform='iphone'):
    return {
        'ExpirationDate': datetime.now() + timedelta(days=1),
        'Platform': ['OSX' if platform == 'macos' else 'iOS'],
        'ApplicationIdentifierPrefix': ['PREFIX'], 'TeamIdentifier': ['TEAM'],
        'DeveloperCertificates': [b'certificate'],
        'Entitlements': {
            'com.apple.application-identifier' if platform == 'macos' else 'application-identifier': 'PREFIX.org.luaobjc.test',
            'com.apple.developer.team-identifier': 'TEAM',
            'keychain-access-groups': ['PREFIX.*'], 'get-task-allow': False,
        },
    }


class SigningTests(unittest.TestCase):
    def test_distribution_entitlements_keep_prefix_separate_from_team(self):
        source = profile()
        original = deepcopy(source)
        result = profile_entitlements(source, 'org.luaobjc.test', 'iphone')
        self.assertEqual(result['application-identifier'], 'PREFIX.org.luaobjc.test')
        self.assertEqual(result['com.apple.developer.team-identifier'], 'TEAM')
        self.assertEqual(result['keychain-access-groups'], ['PREFIX.org.luaobjc.test'])
        self.assertIs(result['get-task-allow'], False)
        self.assertEqual(source, original)

    def test_development_adhoc_enterprise_expired_and_wrong_profiles_rejected(self):
        for mutation in (
            lambda p: p['Entitlements'].update({'get-task-allow': True}),
            lambda p: p.update(ProvisionedDevices=['device']),
            lambda p: p.update(ProvisionsAllDevices=True),
            lambda p: p.update(ExpirationDate=datetime.now() - timedelta(days=1)),
            lambda p: p.update(Platform=['OSX']),
            lambda p: p['Entitlements'].update({'application-identifier': 'PREFIX.*'}),
            lambda p: p['Entitlements'].update({'application-identifier': 'PREFIX.org.luaobjc.other'}),
            lambda p: p.update(TeamIdentifier=['OTHER']),
            lambda p: p['Entitlements'].update({'keychain-access-groups': ['OTHER.*']}),
        ):
            source = profile()
            mutation(source)
            with self.assertRaises(ValueError):
                profile_entitlements(source, 'org.luaobjc.test', 'iphone')

    def test_macos_keeps_sandbox_and_bookmark_permissions(self):
        permissions = {'com.apple.security.app-sandbox': True, 'com.apple.security.files.bookmarks.app-scope': True}
        result = profile_entitlements(profile('macos'), 'org.luaobjc.test', 'macos', requested=permissions)
        self.assertTrue(result['com.apple.security.app-sandbox'])
        self.assertTrue(result['com.apple.security.files.bookmarks.app-scope'])
        self.assertEqual(result['com.apple.application-identifier'], 'PREFIX.org.luaobjc.test')
        self.assertNotIn('application-identifier', result)
        with self.assertRaises(ValueError):
            profile_entitlements(profile('macos'), 'org.luaobjc.test', 'macos')
        with self.assertRaises(ValueError):
            profile_entitlements(profile(), 'org.luaobjc.test', 'iphone', requested={'aps-environment': 'production'})

    def test_only_profile_distribution_certificate_is_accepted(self):
        digest = hashlib.sha1(b'certificate').hexdigest().upper()
        for platform in ('iphone', 'macos'):
            self.assertEqual(distribution_identity(profile(platform), f'1) {digest} "Apple Distribution: Test (TEAM)"', platform), digest)
            for identities in ('', f'1) {digest} "Apple Development: Test (TEAM)"',
                               f'1) {digest} "Developer ID Application: Test (TEAM)"',
                               '1) ' + 'A' * 40 + ' "Apple Distribution: Test (TEAM)"',
                               f'1) {digest} "Apple Distribution: Test (TEAM)" (CSSMERR_TP_CERT_EXPIRED)'):
                with self.assertRaises(ValueError):
                    distribution_identity(profile(platform), identities, platform)

    def test_nested_code_signed_before_bundle(self):
        with tempfile.TemporaryDirectory() as directory, patch('sign.subprocess.run') as run:
            bundle = Path(directory) / 'Test.app'
            libraries = bundle / 'Contents/Frameworks'
            libraries.mkdir(parents=True)
            (libraries / 'AppKit.dylib').touch()
            sign_bundle(bundle, 'identity', Path('entitlements.plist'), hardened=True)
            calls = [call.args[0] for call in run.call_args_list]
            self.assertEqual(calls[0][-1], str(libraries / 'AppKit.dylib'))
            self.assertNotIn('--entitlements', calls[0])
            self.assertIn('--entitlements', calls[1])
            self.assertNotIn('--deep', calls[1])
            self.assertEqual(calls[2], ['codesign', '--verify', '--deep', '--strict', str(bundle)])


class ReleaseTests(unittest.TestCase):
    def test_universal_ios_bundle_has_both_device_families(self):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                Path('apps/test').mkdir(parents=True)
                Path('apps/test/init.lua').write_text('return App')
                Path('ios/LuaRuntime').mkdir(parents=True)
                Path('ios/LuaRuntime/Info.plist').write_bytes(plistlib.dumps({}))
                Path('ios/LuaRuntime/AppIcon.png').write_bytes(b'icon')
                Path('runtime').write_bytes(b'compiled-binary')
                arguments = ['bundle.py', '--binary', 'runtime', '--bundle', 'Test.app',
                             '--sdk', 'iphoneos', '--identifier', 'org.luaobjc.test',
                             '--minimum', '26.5', '--app', 'apps/test', '--entry', 'apps/test/init.lua',
                             '--display-name', 'Test', '--device-family', '1,2']
                with patch('sys.argv', arguments):
                    bundle_app()
                info = plistlib.loads(Path('Test.app/Info.plist').read_bytes())
                self.assertEqual(info['UIDeviceFamily'], [1, 2])
                self.assertEqual(set(info['UISupportedInterfaceOrientations~ipad']), {
                    'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
                    'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'})
                self.assertEqual(info['CFBundleSupportedPlatforms'], ['iPhoneOS'])
                self.assertEqual(Path('Test.app/Workspace/apps/test/init.lua').read_text(), 'return App')
                self.assertEqual(Path('Test.app/AppIcon.png').read_bytes(), b'icon')
            finally:
                os.chdir(previous)

    def test_app_icon_catalog_replaces_host_icon_for_device_and_simulator(self):
        previous = Path.cwd()
        for sdk, families, targets in (('iphoneos', '1', ['iphone']),
                                       ('iphonesimulator', '1,2', ['iphone', 'ipad'])):
            with self.subTest(sdk=sdk), tempfile.TemporaryDirectory() as directory:
                try:
                    os.chdir(directory)
                    Path('apps/test/Assets.xcassets/AppIcon.appiconset').mkdir(parents=True)
                    Path('apps/test/init.lua').write_text('return App')
                    Path('ios/LuaRuntime').mkdir(parents=True)
                    host_info = {'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconFiles': ['HostIcon']}},
                                 'CFBundleIcons~ipad': {'CFBundlePrimaryIcon': {'CFBundleIconFiles': ['HostIcon']}}}
                    Path('ios/LuaRuntime/Info.plist').write_bytes(plistlib.dumps(host_info))
                    Path('ios/LuaRuntime/AppIcon.png').write_bytes(b'host-icon')
                    Path('runtime').write_bytes(b'compiled-binary')
                    Path('Test.app').mkdir()
                    Path('Test.app/AppIcon.png').write_bytes(b'old-host-icon')
                    icon_info = {'CFBundleIcons': {'CFBundlePrimaryIcon': {
                        'CFBundleIconName': 'AppIcon', 'CFBundleIconFiles': ['AppIcon60x60']}}}
                    def compile_icon(command, check):
                        self.assertTrue(check)
                        self.assertEqual(command[:4], ['xcrun', '--sdk', sdk, 'actool'])
                        self.assertEqual(command[4], 'apps/test/Assets.xcassets')
                        self.assertEqual(command[command.index('--platform') + 1], sdk)
                        self.assertEqual(command[command.index('--minimum-deployment-target') + 1], '26.5')
                        self.assertEqual(command[command.index('--app-icon') + 1], 'AppIcon')
                        self.assertEqual([command[i + 1] for i, value in enumerate(command)
                                          if value == '--target-device'], targets)
                        Path(command[command.index('--output-partial-info-plist') + 1]).write_bytes(plistlib.dumps(icon_info))
                        (Path(command[command.index('--compile') + 1]) / 'Assets.car').write_bytes(b'compiled-icons')
                    arguments = ['bundle.py', '--binary', 'runtime', '--bundle', 'Test.app',
                                 '--sdk', sdk, '--identifier', 'org.luaobjc.test', '--minimum', '26.5',
                                 '--app', 'test', '--entry', 'test/init.lua',
                                 '--display-name', 'Test', '--device-family', families]
                    with patch('sys.argv', arguments), patch('bundle.subprocess.run', side_effect=compile_icon) as compiler:
                        bundle_app()
                    compiler.assert_called_once()
                    info = plistlib.loads(Path('Test.app/Info.plist').read_bytes())
                    self.assertEqual(info['CFBundleIcons'], icon_info['CFBundleIcons'])
                    self.assertNotIn('CFBundleIcons~ipad', info)
                    self.assertEqual(info['CFBundleIdentifier'], 'org.luaobjc.test')
                    self.assertEqual(info['UIDeviceFamily'], [int(family) for family in families.split(',')])
                    self.assertEqual(info['LRTLocalEntry'], 'apps/test/init.lua')
                    self.assertEqual(Path('Test.app/Assets.car').read_bytes(), b'compiled-icons')
                    self.assertFalse(Path('Test.app/AppIcon.png').exists())
                    self.assertFalse(Path('Test.app/Workspace/apps/test/Assets.xcassets').exists())
                    self.assertEqual(Path('ios/LuaRuntime/AppIcon.png').read_bytes(), b'host-icon')
                finally:
                    os.chdir(previous)

    def test_runtime_assets_are_preserved_and_build_material_is_excluded(self):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                source = Path('apps/test')
                runtime = ('init.lua', 'views/pages/Main.etlua', 'app.xml', 'shaders/Main.metal',
                           'data/model.bin', 'tour/page.jpg', 'assets/manifest.json')
                excluded = ('README.md', 'Info.plist', 'AppStore.entitlements',
                            'Build/main.lua', 'Test.xcodeproj/project.pbxproj',
                            'Assets.xcassets/AppIcon.png', '.git/config', 'ci_scripts/build.sh')
                for name in (*runtime, *excluded):
                    path = source / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(name)
                destination = Path('workspace')
                copy_tree(source, destination, runtime_only=True)
                for name in runtime:
                    self.assertEqual((destination / source / name).read_text(), name)
                for name in excluded:
                    self.assertFalse((destination / source / name).exists())
            finally:
                os.chdir(previous)

    @unittest.skipUnless(__import__('shutil').which('ditto'), 'Requires Apple bundle archiver')
    def test_ipa_contains_payload_and_the_signed_copy_of_the_compiled_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'unsigned/Test.app'
            source.mkdir(parents=True)
            info = {'CFBundleIdentifier': 'org.luaobjc.test', 'CFBundleVersion': '7.2',
                    'CFBundleShortVersionString': '1.2.3', 'UIDeviceFamily': [1]}
            (source / 'Info.plist').write_bytes(plistlib.dumps(info))
            (source / 'Test').write_bytes(b'compiled-binary')
            (source / 'Workspace').mkdir()
            (source / 'Workspace/init.lua').write_text('return App')
            def signed_copy(bundle, *args):
                (bundle / '_CodeSignature').mkdir()
                (bundle / '_CodeSignature/CodeResources').write_bytes(b'signature-fixture')
            with patch('release.sign_store', side_effect=signed_copy):
                artifact = store_package({'platform': 'iphone', 'product': 'Test'}, source, '1.2.3', Path('profile'))
            with zipfile.ZipFile(artifact) as archive:
                self.assertEqual(archive.read('Payload/Test.app/Test'), b'compiled-binary')
                self.assertEqual(archive.read('Payload/Test.app/_CodeSignature/CodeResources'), b'signature-fixture')
                packaged = plistlib.loads(archive.read('Payload/Test.app/Info.plist'))
                self.assertEqual(packaged, info)
            self.assertFalse((source / '_CodeSignature').exists())
            self.assertEqual(plistlib.loads((Path(directory) / 'upload-info.plist').read_bytes()), info)

    def test_toolchain_prefers_latest_stable_and_rejects_betas(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, version, build in (('Xcode_26.6.app', '26.6', '17F47'),
                                         ('Xcode_26.2.app', '26.2', '17C52'),
                                         ('Xcode.app', '27.0', '27A266a'),
                                         ('Xcode_27_RC.app', '27.0', '27A266')):
                path = root / name / 'Contents'
                path.mkdir(parents=True)
                (path / 'version.plist').write_bytes(plistlib.dumps(
                    {'CFBundleShortVersionString': version, 'ProductBuildVersion': build}))
            self.assertEqual(select_xcode(root), root / 'Xcode_26.6.app/Contents/Developer')
            (root / 'Xcode_26.6.app/Contents/version.plist').unlink()
            with self.assertRaises(ValueError):
                select_xcode(root)

    def test_platform_drives_compilation_and_device_family(self):
        records = {record['app']: record for record in apps()}
        self.assertEqual(records['diskmap']['platform'], 'macos')
        self.assertEqual(records['adventure-arena']['platform'], 'ios')
        universal = compile_command(records['adventure-arena'], Path('/tmp/app.app'))
        self.assertIn('DEVICE_FAMILY=1,2', universal)
        phone = compile_command(dict(records['adventure-arena'], platform='iphone'), Path('/tmp/app.app'))
        self.assertIn('SDK=iphoneos', phone)
        self.assertIn('DEVICE_FAMILY=1', phone)
        self.assertIn('FILE_SHARING=0', phone)
        tablet = dict(records['adventure-arena'], platform='ipad')
        self.assertIn('DEVICE_FAMILY=2', compile_command(tablet, Path('/tmp/app.app')))
        for slug in ('diskmap', 'dnb'):
            command = compile_command(records[slug], Path('/tmp/app.app'))
            self.assertIn('scripts/release/macos.mk', command)
            self.assertNotIn('SDK=iphoneos', command)

    def test_invalid_or_missing_platform_never_falls_back(self):
        for change in ({'platform': 'watch'}, {'platform': ''}, {'channels': []}, {'profileSecret': ''},
                       {'appStoreIdVariable': ''}, {'app': '../test'}):
            records = apps()
            records[0].update(change)
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'apps.json'
                path.write_text(json.dumps(records))
                with self.assertRaises(ValueError):
                    apps(path)

    def test_versions_are_validated_before_use_in_paths(self):
        self.assertEqual(release_version('1.2.3'), '1.2.3')
        self.assertEqual(build_number('123.2'), '123.2')
        for value in ('1.2', 'v1.2.3', '1.2.3/other', '1.2.3;false'):
            with self.assertRaises(ValueError):
                release_version(value)
        for value in ('0', '10000', '1.100', '1.2.3.4', ''):
            with self.assertRaises(ValueError):
                build_number(value)

    def test_iphone_credentials_do_not_require_macos_certificates(self):
        phone = required_secrets('iphone', True)
        self.assertIn('APPSTORE_PROFILE', phone)
        self.assertNotIn('MACOS_CERTIFICATE_P12', phone)
        self.assertNotIn('APPSTORE_INSTALLER_P12', phone)
        self.assertIn('APPSTORE_INSTALLER_P12', required_secrets('macos', True))
        self.assertNotIn('APPSTORE_CERTIFICATE_P12', required_secrets('macos', False))

    def test_packaging_uses_same_signed_bundle(self):
        with tempfile.TemporaryDirectory() as directory, patch('release.copy_bundle', side_effect=lambda s, d: d), \
                patch('release.sign_store') as sign, patch('release.run') as run, patch('release.shutil.copy2'):
            source = Path(directory) / 'unsigned/Test.app'
            record = {'platform': 'iphone', 'product': 'Test'}
            artifact = store_package(record, source, '1.2.3', Path('profile'))
            self.assertEqual(artifact.name, 'Test-1.2.3.ipa')
            self.assertEqual(sign.call_args.args[0], Path(directory) / 'store/Test.app')
            self.assertEqual(run.call_args.args[0], 'ditto')
            self.assertEqual(run.call_args.args[-2].name, 'Payload')
            self.assertEqual(run.call_args.args[-1], artifact)
            record['platform'] = 'macos'
            artifact = store_package(record, source, '1.2.3', Path('profile'))
            self.assertEqual(artifact.suffix, '.pkg')
            self.assertEqual(run.call_args_list[-2].args[0], 'productbuild')

    def test_validate_precedes_upload_and_private_key_is_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory) / 'key.p8'
            key.write_text('private-key-fixture')
            environment = {'APPSTORE_KEY': str(key), 'APPSTORE_KEY_ID': 'KEYID', 'APPSTORE_ISSUER_ID': 'ISSUER',
                           'APPSTORE_APP_ID': '1234567890'}
            info = {'CFBundleIdentifier': 'org.luaobjc.test', 'CFBundleVersion': '7.2', 'CFBundleShortVersionString': '1.2.3'}
            with patch.dict(os.environ, environment), patch('release.run') as run:
                upload(Path('Test.ipa'), 'iphone', info)
                validate, transfer = run.call_args_list
                self.assertIn('--validate-app', validate.args)
                self.assertIn('--upload-package', transfer.args)
                self.assertIn('--wait', transfer.args)
                self.assertIn('7.2', transfer.args)
                self.assertIn('1234567890', transfer.args)
                self.assertIn('ios', transfer.args)
                self.assertIn('Test.ipa', transfer.args)
                temporary = transfer.kwargs['env']['API_PRIVATE_KEYS_DIR']
                self.assertFalse(Path(temporary).exists())
            with patch.dict(os.environ, environment), patch('release.run', side_effect=ValueError('rejected')) as run:
                with self.assertRaises(ValueError):
                    upload(Path('Test.ipa'), 'iphone', info)
                self.assertEqual(run.call_count, 1)

    def test_unsigned_artifacts_cannot_be_published(self):
        with patch('release.run') as run:
            with self.assertRaisesRegex(ValueError, 'Missing signed release artifact'):
                publish([{'app': 'missing-app', 'product': 'Test', 'platform': 'macos', 'channels': ['github']}], '1.2.3')
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
