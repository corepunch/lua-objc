#!/usr/bin/env python3
"""Import only the signing/upload secrets needed by this app's platform."""
import base64
import os
from pathlib import Path
import secrets
import shlex
import subprocess


def required_secrets(platform, store):
    required = []
    if platform == 'macos':
        required.extend(['MACOS_CERTIFICATE_P12', 'NOTARY_KEY_P8', 'NOTARY_KEY_ID', 'NOTARY_ISSUER_ID'])
    if store:
        required.extend(['APPSTORE_CERTIFICATE_P12', 'APPSTORE_PROFILE'])
        if platform == 'macos':
            required.append('APPSTORE_INSTALLER_P12')
    return required


def write_secret(name, path):
    path.write_bytes(base64.b64decode(''.join(os.environ[name].split()), validate=True))
    path.chmod(0o600)


def main():
    platform = os.environ['PLATFORM']
    store = os.environ['STORE'] == '1'
    missing = [name if name != 'APPSTORE_PROFILE' else os.environ['PROFILE_SECRET']
               for name in required_secrets(platform, store) if not os.environ.get(name)]
    if missing:
        raise SystemExit('Missing GitHub Actions secrets: ' + ', '.join(missing))
    temporary = Path(os.environ['RUNNER_TEMP'])
    keychain = temporary / 'release.keychain-db'
    password = secrets.token_urlsafe(32)
    print('::add-mask::' + password, flush=True)
    def security(*args):
        subprocess.run(['security', *map(str, args)], check=True)
    security('create-keychain', '-p', password, keychain)
    security('set-keychain-settings', '-lut', '21600', keychain)
    security('unlock-keychain', '-p', password, keychain)
    certificates = []
    if platform == 'macos':
        certificates.append(('MACOS_CERTIFICATE_P12', 'MACOS_CERTIFICATE_PASSWORD'))
        write_secret('NOTARY_KEY_P8', temporary / 'notary.p8')
    if store:
        certificates.append(('APPSTORE_CERTIFICATE_P12', 'APPSTORE_CERTIFICATE_PASSWORD'))
        if platform == 'macos':
            certificates.append(('APPSTORE_INSTALLER_P12', 'APPSTORE_INSTALLER_PASSWORD'))
        write_secret('APPSTORE_PROFILE', temporary / 'appstore.mobileprovision')
    for name, passphrase in certificates:
        path = temporary / (name + '.p12')
        write_secret(name, path)
        security('import', path, '-k', keychain, '-P', os.environ.get(passphrase, ''),
                 '-T', '/usr/bin/codesign', '-T', '/usr/bin/productbuild', '-T', '/usr/bin/security')
        path.unlink()
    security('set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, keychain)
    existing = subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True)
    security('list-keychains', '-d', 'user', '-s', keychain, *shlex.split(existing))
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        print('NOTARY_KEY=' + str(temporary / 'notary.p8'), file=output)


if __name__ == '__main__':
    main()
