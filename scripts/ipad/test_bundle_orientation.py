"""Offline checks for Studio's orientations: portrait on iPhone, landscape on iPad."""
import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ipad_bundle', Path(__file__).with_name('bundle.py'))
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)
STUDIO = plistlib.loads((ROOT / 'apps/studio/Info.plist').read_bytes())
LANDSCAPE = ['UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']
PORTRAIT = ['UIInterfaceOrientationPortrait']


class OrientationTest(unittest.TestCase):
    def test_studio_declares_portrait_phone_and_landscape_pad(self):
        self.assertEqual(STUDIO['UISupportedInterfaceOrientations'], PORTRAIT)
        self.assertEqual(STUDIO['UISupportedInterfaceOrientations~ipad'], LANDSCAPE)
        self.assertNotIn('UIRequiresFullScreen', STUDIO)

    def test_device_and_simulator_preserve_app_orientation(self):
        previous = Path.cwd()
        for sdk in ['iphoneos', 'iphonesimulator']:
            with self.subTest(sdk=sdk), tempfile.TemporaryDirectory() as directory:
                try:
                    os.chdir(directory)
                    Path('apps/test').mkdir(parents=True)
                    Path('apps/test/init.lua').write_text('return {}')
                    Path('apps/test/Info.plist').write_bytes(plistlib.dumps(STUDIO))
                    Path('ios/LuaRuntime').mkdir(parents=True)
                    Path('ios/LuaRuntime/Info.plist').write_bytes(plistlib.dumps({
                        'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait']}))
                    Path('ios/LuaRuntime/AppIcon.png').write_bytes(b'icon')
                    Path('runtime').write_bytes(b'runtime')
                    args = ['bundle.py', '--binary', 'runtime', '--bundle', 'Test.app',
                            '--sdk', sdk, '--identifier', 'org.luaobjc.test', '--minimum', '26.5',
                            '--app', 'apps/test', '--entry', 'apps/test/init.lua',
                            '--display-name', 'Test', '--device-family', '1,2']
                    with patch('sys.argv', args):
                        bundle.main()
                    info = plistlib.loads(Path('Test.app/Info.plist').read_bytes())
                    self.assertEqual(info['UISupportedInterfaceOrientations'], PORTRAIT)
                    self.assertEqual(info['UISupportedInterfaceOrientations~ipad'], LANDSCAPE)
                    self.assertEqual(info['UIDeviceFamily'], [1, 2])
                    self.assertEqual(info['CFBundleIdentifier'], 'org.luaobjc.test')
                finally:
                    os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
