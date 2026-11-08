#!/usr/bin/env python3
"""Unattended UIKit verification using the installed runtime; no network or key."""
import argparse
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import struct
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = ROOT / 'build/studio-smoke-runtime/iphonesimulator-arm64/LuaStudioSmoke.app'
IDENTIFIER = 'org.luaobjc.studio.smoke'
SCENARIOS = ('github', 'github-busy', 'github-error', 'agent', 'preview-error', 'interaction', 'provider-error', 'code', 'long', 'busy', 'settings', 'popup-settings', 'popup-delete', 'project', 'templates', 'template-create', 'export', 'share', 'attach', 'appearance', 'create')
LIFECYCLE = ('lifecycle-create', 'lifecycle-settings', 'lifecycle-edit', 'lifecycle-invalid', 'lifecycle-reopen',
             'lifecycle-delete-confirm', 'lifecycle-delete', 'lifecycle-empty', 'lifecycle-recreate')
SCENARIOS += LIFECYCLE
SCENARIOS += ('orientation',)
LIVE_SCENARIOS = ('github-live', 'github-live-reopen', 'github-live-delete')


def run(*args, env=None, timeout=180):
    result = subprocess.run(args, cwd=ROOT, env=env, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed: {result.stdout}\n{result.stderr}')
    return result.stdout.strip()


def sim(*args, **kwargs):
    return run('xcrun', 'simctl', *args, **kwargs)


def validate_layout(path):
    root = json.loads(path.read_text())
    tracked = {'columns', 'previewPane', 'chatPane', 'chatCard', 'stageBar', 'codePane',
               'sourceCode', 'codeFileTitle', 'projectMenu', 'composer', 'runButton', 'chatVisibility'}
    def rect(value):
        return list(map(float, re.findall(r'-?[0-9]+(?:\.[0-9]+)?', value)))
    def visit(node, parent=None, menu=None):
        if node['hidden']:
            return
        current = rect(node['window'])
        if node.get('identifier') in ('settingsPopup',):
            rx, ry, rw, rh = rect(root['window'])
            x, y, width, height = current
            if width * height >= rw * rh * 0.85:
                raise RuntimeError('A compact popup covered the workspace like a full-screen sheet')
            if x < rx - 1 or y < ry - 1 or x + width > rx + rw + 1 or y + height > ry + rh + 1:
                raise RuntimeError('The popup extends beyond the application window')
        if node.get('identifier') == 'projectMenu':
            menu = current
        if menu and node.get('text'):
            if current[1] < menu[1] - 1 or current[1] + current[3] > menu[1] + menu[3] + 1:
                raise RuntimeError('The menu title wraps outside its native button')
        if parent and (node.get('identifier') in tracked or node.get('identifier', '').startswith('bubble/')):
            x, y, width, height = current
            px, py, pw, ph = parent
            if x < px - 1 or x + width > px + pw + 1 or y < py - 1 or y + height > py + ph + 1:
                raise RuntimeError(f"Clipped {node['identifier']}: {current} outside {parent}")
        if node.get('identifier', '').startswith('bubble/') and node['children']:
            content = rect(node['children'][-1]['window'])
            if abs(current[3] - content[3]) > 1:
                raise RuntimeError('A resized bubble retained the gradient’s old height')
        for child in node['children']:
            visit(child, current, menu)
    visit(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', help='Reuse an explicitly selected simulator; otherwise create and remove a temporary iPad (about 2 GB).')
    parser.add_argument('--identifier', default=IDENTIFIER, help='Isolate simultaneous smoke runs with a distinct app identifier.')
    parser.add_argument('--runtime-root', type=Path, default=BUNDLE.parent, help='Build directory for the smoke runtime.')
    parser.add_argument('--scenarios', default=','.join(SCENARIOS))
    parser.add_argument('--layouts', default='standard,wide')
    parser.add_argument('--appearance', choices=('light', 'dark'), default='light')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/studio-smoke')
    args = parser.parse_args()
    identifier = args.identifier
    bundle = args.runtime_root / BUNDLE.name
    scenarios = args.scenarios.split(',')
    layouts = args.layouts.split(',')
    if any(item not in SCENARIOS + LIVE_SCENARIOS + ('github-prepare',) for item in scenarios):
        parser.error('Unknown scenario')
    if any(item not in ('standard', 'wide', 'small') for item in layouts):
        parser.error('Unknown layout')
    args.output.mkdir(parents=True, exist_ok=True)
    for name in ('failure.txt', 'failure.log', 'failure.png'):
        (args.output / name).unlink(missing_ok=True)
    (args.output / "results.json").unlink(missing_ok=True)
    device, owned = args.device, False
    results = []
    try:
        with tempfile.TemporaryDirectory(prefix='studio-smoke-') as overlay:
            target = Path(overlay) / 'test/studio-smoke'
            shutil.copytree(ROOT / 'test/studio-smoke', target)
            print('Building the UIKit smoke app…', flush=True)
            run('make', '-f', 'scripts/ipad/build.mk', 'SDK=iphonesimulator', 'APP=studio', 'APP_BUNDLE=LuaStudioSmoke', f'ROOT={args.runtime_root}',
                f'BUNDLE_ID={identifier}', 'APP_DISPLAY_NAME=Lua Studio Tests',
                'APP_ENTRY=test/studio-smoke/init.lua', f'OVERLAY={overlay}')
        if not device:
            runtimes = json.loads(sim('list', 'runtimes', '--json'))['runtimes']
            runtime = next(item['identifier'] for item in reversed(runtimes)
                           if item.get('isAvailable') and item['name'].startswith('iOS '))
            device = sim('create', 'Studio Headless Test', 'com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB', runtime)
            owned = True
            sim('boot', device)
        print('Waiting for the simulator…', flush=True)
        sim('bootstatus', device, '-b', timeout=600)
        sim('ui', device, 'appearance', args.appearance)
        sim('install', device, str(bundle))
        container = Path(sim('get_app_container', device, identifier, 'data'))
        marker = container / 'Documents/smoke-result.txt'
        for layout_name in layouts:
            for scenario in scenarios:
                # System modal presentations follow the actual scene. Their
                # real screenshots are checked at the standard landscape size.
                if layout_name != 'standard' and (scenario.startswith(('github', 'lifecycle-')) or scenario in ('settings','project','templates','export','share','attach')):
                    continue
                label = f'{scenario}-{layout_name}'
                marker.unlink(missing_ok=True)
                (container / "Documents/layout.json").unlink(missing_ok=True)
                (container / "Documents/smoke.png").unlink(missing_ok=True)
                env = os.environ.copy()
                env.update(SIMCTL_CHILD_STUDIO_SMOKE_SCENARIO=scenario,
                           SIMCTL_CHILD_LUA_OBJC_INTERNAL_CAPTURE_MANUAL="1",
                           SIMCTL_CHILD_LUA_OBJC_INTERNAL_CAPTURE_SIZE={"standard":"1210x834", "wide":"1366x834", "small":"1024x768"}[layout_name],
                           SIMCTL_CHILD_LUA_OBJC_INTERNAL_SCREENSHOT=str(container / "Documents/smoke.png"),
                           SIMCTL_CHILD_LUA_OBJC_INTERNAL_LAYOUT=str(container / 'Documents/layout.json'))
                stdout = container / 'Documents' / f'{label}.stdout.log'
                stderr = container / 'Documents' / f'{label}.stderr.log'
                stdout.parent.mkdir(parents=True, exist_ok=True)
                stdout.touch(); stderr.touch()
                for attempt in range(3):
                    try:
                        sim('launch', '--terminate-running-process', f'--stdout={stdout}', f'--stderr={stderr}', device, identifier, env=env)
                        break
                    except RuntimeError as error:
                        if attempt == 2 or 'FBSOpenApplicationServiceErrorDomain' not in str(error):
                            raise
                        time.sleep(1)
                deadline = time.monotonic() + 45
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.1)
                if not marker.exists() or marker.read_text() != f'PASS {scenario}':
                    raise RuntimeError(f'UIKit scenario failed: {label}: {marker.read_text() if marker.exists() else "no result"}')
                # Let the one-shot native snapshot settle; app logic uses no sleeps.
                time.sleep(1)
                shot = args.output / f'{label}.png'
                native_shot = container / 'Documents/smoke.png'
                deadline = time.monotonic() + 10
                while not native_shot.exists() and time.monotonic() < deadline:
                    time.sleep(0.1)
                shutil.copy2(native_shot, shot)
                width, height = struct.unpack('>II', shot.read_bytes()[16:24])
                expected = {'standard': (2420, 1668), 'wide': (2732, 1668), 'small': (2048, 1536)}[layout_name]
                if (width, height) != expected:
                    raise RuntimeError(f'{label} lost native Retina resolution: {(width, height)} instead of {expected}')
                layout = container / 'Documents/layout.json'
                if layout.is_file():
                    shutil.copy2(layout, args.output / f'{label}.layout.json')
                    validate_layout(layout)
                if scenario == 'share':
                    archives = list((container / 'tmp').rglob('StarterApp.zip'))
                    if not archives:
                        raise RuntimeError('The native share action did not create an archive')
                    with zipfile.ZipFile(max(archives, key=lambda item: item.stat().st_mtime_ns)) as archive:
                        names = archive.namelist()
                        if not any(name.endswith('/Controller.lua') or name == 'Controller.lua' for name in names):
                            raise RuntimeError('Source is missing from the archive')
                        controller = next(name for name in names if name.endswith('/Controller.lua') or name == 'Controller.lua')
                        if b'demo.playground' in archive.read(controller):
                            raise RuntimeError('Exported modules still use the preview-only namespace')
                        if any('/.git/' in name or '/data/' in name or name.endswith('settings.json') for name in names):
                            raise RuntimeError('Private runtime state entered the archive')
                shutil.copy2(stdout, args.output / f'{label}.stdout.log')
                shutil.copy2(stderr, args.output / f'{label}.stderr.log')
                if scenario in LIVE_SCENARIOS:
                    shutil.copy2(container / 'Documents/github-evidence.json', args.output / 'github-evidence.json')
                results.append({'scenario': scenario, 'layout': layout_name, 'appearance': args.appearance, 'passed': True})
                print(f'PASS {label}', flush=True)
        (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    except Exception as error:
        (args.output / "failure.txt").write_text(str(error) + "\n")
        if device:
            try:
                sim('io', device, 'screenshot', str(args.output / 'failure.png'), timeout=15)
                log = sim('spawn', device, 'log', 'show', '--last', '2m', '--style', 'compact',
                          '--predicate', 'process == "LuaStudio" AND eventMessage CONTAINS "lua-objc"', timeout=15)
                (args.output / 'failure.log').write_text(log + '\n')
                print(log, flush=True)
            except Exception:
                pass
        raise
    finally:
        if owned:
            sim('shutdown', device)
            sim('delete', device)
        # The smoke app has its own bundle directory and cannot overwrite the product bundle.
    print(f'Captured {len(results)} UIKit states in {args.output}', flush=True)


if __name__ == '__main__':
    main()
