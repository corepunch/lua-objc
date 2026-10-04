"""App Store signing of already-built macOS and iOS bundles."""
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import plistlib
import re
import shutil
import subprocess


def profile_entitlements(profile, bundle_id, platform, now=None, requested=None):
    now = now or datetime.now(timezone.utc).replace(tzinfo=None)
    if profile['ExpirationDate'] <= now:
        raise ValueError('App Store provisioning profile has expired')
    allowed = profile['Entitlements']
    if (allowed.get('get-task-allow') or allowed.get('com.apple.security.get-task-allow')
            or 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices')):
        raise ValueError('App Store distribution profile required; development/ad hoc profiles are rejected')
    platforms = profile.get('Platform', [])
    if platform == 'macos' and not any(p in platforms for p in ('OSX', 'macOS')):
        raise ValueError('macOS provisioning profile required')
    if platform in ('ios', 'iphone', 'ipad') and 'iOS' not in platforms:
        raise ValueError('iOS provisioning profile required')
    key = 'com.apple.application-identifier' if platform == 'macos' else 'application-identifier'
    identifier = profile['ApplicationIdentifierPrefix'][0] + '.' + bundle_id
    if allowed.get(key) != identifier:
        raise ValueError('App Store profile must name the exact bundle identifier: ' + bundle_id)
    team = allowed.get('com.apple.developer.team-identifier')
    if not team or team not in profile.get('TeamIdentifier', []):
        raise ValueError('Invalid signing team in provisioning profile')
    result = dict(requested or {})
    # Sandbox permissions are app-owned; developer capabilities are profile-owned.
    for name, value in result.items():
        if name.startswith('com.apple.security.') and 'get-task-allow' not in name:
            continue
        if allowed.get(name) != value:
            raise ValueError('Provisioning profile does not allow entitlement: ' + name)
    if result.get('get-task-allow') or result.get('com.apple.security.get-task-allow'):
        raise ValueError('App Store apps cannot allow debugging')
    result.update({key: identifier, 'com.apple.developer.team-identifier': team})
    if 'get-task-allow' in allowed:
        result['get-task-allow'] = False
    groups = allowed.get('keychain-access-groups', [])
    if groups:
        if not any(group == identifier or (group.endswith('.*') and identifier.startswith(group[:-1]))
                   for group in groups):
            raise ValueError('Profile does not allow the app Keychain group')
        result['keychain-access-groups'] = [identifier]
    if platform == 'macos' and not result.get('com.apple.security.app-sandbox'):
        raise ValueError('Mac App Store apps require App Sandbox entitlements')
    return result


def distribution_identity(profile, identities, platform):
    certificates = {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
    names = ('Apple Distribution:', '3rd Party Mac Developer Application:') if platform == 'macos' else (
        'Apple Distribution:', 'iPhone Distribution:')
    for line in identities.splitlines():
        match = re.search(r'\b([A-F0-9]{40})\s+"([^"]+)"', line)
        if (match and 'CSSMERR_' not in line and match[1] in certificates
                and match[2].startswith(names)):
            return match[1]
    raise ValueError('No installed distribution certificate/private key matching the provisioning profile')


def sign_bundle(bundle, identity, entitlements=None, hardened=False):
    flags = ['--options', 'runtime'] if hardened else []
    # Sign nested native code before the enclosing app; never sign with --deep.
    for library in sorted((bundle / 'Contents/Frameworks').glob('*.dylib')):
        subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp', *flags, str(library)], check=True)
    command = ['codesign', '--force', '--sign', identity, '--timestamp', *flags]
    if entitlements:
        command.extend(['--entitlements', str(entitlements), '--generate-entitlement-der'])
    subprocess.run([*command, str(bundle)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)


def sign_store(bundle, platform, profile_path, requested=None):
    decoded = subprocess.check_output(['security', 'cms', '-D', '-i', str(profile_path)])
    profile = plistlib.loads(decoded)
    plist = bundle / ('Contents/Info.plist' if platform == 'macos' else 'Info.plist')
    bundle_id = plistlib.loads(plist.read_bytes())['CFBundleIdentifier']
    entitlements = profile_entitlements(profile, bundle_id, platform, requested=requested)
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    identity = distribution_identity(profile, identities, platform)
    embedded = bundle / ('Contents/embedded.provisionprofile' if platform == 'macos' else 'embedded.mobileprovision')
    shutil.copy2(profile_path, embedded)
    path = bundle.parent / 'store-entitlements.plist'
    path.write_bytes(plistlib.dumps(entitlements))
    sign_bundle(bundle, identity, path)
