#!/usr/bin/env python3
"""Opt-in live publishing proof against an existing verification repository."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def review_token(environment):
    token = environment.get('STUDIO_REVIEW_GITHUB_TOKEN', '').strip()
    if not token:
        raise RuntimeError('Set STUDIO_REVIEW_GITHUB_TOKEN in the environment; Keychain lookup is disabled')
    return token


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--repository', required=True, help='Existing owner/repository with Contents write access')
    parser.add_argument('--identifier', default='org.luaobjc.studio.workflowcheck')
    parser.add_argument('--branch', help='New destination branch for the prepared payload')
    parser.add_argument('--runtime-root', default='build/studio-verification/runtime')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/studio-verification/github')
    args = parser.parse_args()
    owner, repository = args.repository.split('/')
    if owner != 'corepunch':
        parser.error('The live harness targets the corepunch verification account')
    approved = json.loads((ROOT / 'build/studio-verification/prepared-payload.json').read_text())
    branch = args.branch or approved['branch']
    if approved['repository'] != args.repository or approved['branch'] != branch:
        parser.error('The repository and branch must match the reviewed payload')
    for entry in approved['files']:
        content = (ROOT / 'build/studio-verification/prepared' / approved['projectId'] / entry['path']).read_bytes()
        assert hashlib.sha256(content).hexdigest() == entry['sha256'], 'The reviewed payload changed before publishing'
    # Share Fastlane's explicit environment input. Never trigger a desktop
    # Keychain password dialog while running verification unattended.
    token = review_token(os.environ)
    env = os.environ.copy()
    env.update(SIMCTL_CHILD_STUDIO_GITHUB_TEST_TOKEN=token,
               SIMCTL_CHILD_STUDIO_GITHUB_TEST_REPOSITORY=repository,
               SIMCTL_CHILD_STUDIO_GITHUB_TEST_BRANCH=branch)
    command = [sys.executable, 'scripts/ipad/studio_smoke.py', '--device', args.device,
               '--identifier', args.identifier, '--runtime-root', args.runtime_root,
               '--scenarios', 'github-live,github-live-reopen,github-live-delete',
               '--layouts', 'standard', '--output', str(args.output)]
    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    for line in process.stdout:
        print(line.replace(token, '[REDACTED]'), end='', flush=True)
    if process.wait():
        raise RuntimeError('Live UIKit GitHub workflow failed; inspect the redacted test output')
    evidence = json.loads((args.output / 'github-evidence.json').read_text())

    def get(path):
        request = urllib.request.Request('https://api.github.com' + path,
                                         headers={'Authorization': 'Bearer ' + token,
                                                  'Accept': 'application/vnd.github+json',
                                                  'User-Agent': 'Lua-Studio-Verification'})
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    commit = get(f'/repos/{args.repository}/commits/{branch}')
    assert commit['sha'] == evidence['head'], 'Remote HEAD differs from the iPad commit'
    content = get(f'/repos/{args.repository}/contents/views/pages/Main.etlua?ref={branch}')
    assert b'Published Workflow' in base64.b64decode(content['content']), 'The edited source was not published'
    tree = get(f'/repos/{args.repository}/git/trees/{evidence["head"]}?recursive=1')
    blobs = {item['path']: item['sha'] for item in tree['tree'] if item['type'] == 'blob'}
    paths = list(blobs)
    assert 'project.lua' in paths and 'AppIcon.png' in paths
    assert not any(path == 'settings.json' or path.startswith(('data/', '.git/')) for path in paths)
    assert approved['repository'] == args.repository and approved['branch'] == branch
    assert approved['head'] == evidence['head'], 'Published history differs from the approved commits'
    assert set(blobs) == {entry['path'] for entry in approved['files']}, 'Published file list differs from the approved payload'
    for entry in approved['files']:
        content = (ROOT / 'build/studio-verification/prepared' / approved['projectId'] / entry['path']).read_bytes()
        assert hashlib.sha256(content).hexdigest() == entry['sha256'], 'The preserved approval payload changed'
        blob = b'blob ' + str(len(content)).encode() + b'\0' + content
        assert blobs[entry['path']] == hashlib.sha1(blob).hexdigest(), 'Remote file differs from the approved payload'
    evidence.update(remoteSourceVerified=True, privateFilesExcluded=True,
                    localDeletionPreservedRemote=True, publishedFileCount=len(paths), approvedPayloadVerified=True)
    (args.output / 'github-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
