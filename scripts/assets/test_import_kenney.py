"""Offline checks for scripts/assets/import_kenney.py on a hand-made kit:
a model that matches its OBJ is copied byte for byte; a Unity-era export
(turned 180 degrees, moved, sRGB colours, a scene root parented elsewhere)
is corrected; a model that matches neither way is refused."""
import importlib.util
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).with_name('import_kenney.py')
spec = importlib.util.spec_from_file_location('import_kenney', SCRIPT)
imp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(imp)

TRIANGLE = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 2.0)]


def glb(path, points, root, generator='Kenney', colour=(1, 1, 1, 1)):
    binary = b''.join(struct.pack('<3f', *p) for p in points)
    nodes = [{'name': 'tmpParent', 'children': [1]}, dict(root, name='model', mesh=0)]
    document = {
        'asset': {'version': '2.0', 'generator': generator}, 'scene': 0, 'scenes': [{'nodes': [1]}], 'nodes': nodes,
        'meshes': [{'primitives': [{'attributes': {'POSITION': 0}, 'material': 0}]}],
        'materials': [{'pbrMetallicRoughness': {'baseColorFactor': list(colour)}}],
        'buffers': [{'byteLength': len(binary)}],
        'bufferViews': [{'buffer': 0, 'byteOffset': 0, 'byteLength': len(binary)}],
        'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': len(points), 'type': 'VEC3'}],
    }
    imp.write_glb(path, document, struct.pack('<I4s', len(binary), b'BIN\x00') + binary)


def obj(path, points):
    path.write_text(''.join(f'v {x} {y} {z}\n' for x, y, z in points))


class ImportTest(unittest.TestCase):
    def test_import(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            kit = work / 'kit'
            (kit / 'Models' / 'GLB format').mkdir(parents=True)
            (kit / 'Models' / 'OBJ format').mkdir(parents=True)
            (kit / 'License.txt').write_text('CC0')
            models, objs = kit / 'Models' / 'GLB format', kit / 'Models' / 'OBJ format'
            glb(models / 'clean.glb', TRIANGLE, {})
            obj(objs / 'clean.obj', TRIANGLE)
            turned = [(-x, y, -z) for x, y, z in TRIANGLE]
            glb(models / 'unity.glb', turned, {'translation': [2, 0, 1.5]}, 'UniGLTF-1.27', (0.91, 0.333, 0.325, 1))
            obj(objs / 'unity.obj', TRIANGLE)
            os.chdir(work)
            result = subprocess.run([sys.executable, '-I', str(SCRIPT), str(kit), 'kit'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            target = work / 'assets' / 'kenney' / 'kit' / 'models'
            self.assertEqual((target / 'clean.glb').read_bytes(), (models / 'clean.glb').read_bytes())
            document, rest = imp.read_glb(target / 'unity.glb')
            low, high = imp.bounds(document, rest)
            self.assertTrue(imp.matches((low, high), imp.obj_bounds(objs / 'unity.obj')))
            red = document['materials'][0]['pbrMetallicRoughness']['baseColorFactor']
            self.assertAlmostEqual(red[1], 0.0908, places=3)  # sRGB 85/255 as linear
            self.assertNotIn('children', document['nodes'][0])  # the scene's root is a real root

            glb(models / 'broken.glb', [(5, 5, 5), (6, 5, 5), (5, 6, 5)], {})
            obj(objs / 'broken.obj', TRIANGLE)
            result = subprocess.run([sys.executable, '-I', str(SCRIPT), str(kit), 'kit'], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('broken', result.stderr)
            self.assertFalse((target / 'broken.glb').exists())
            os.chdir(ROOT)


if __name__ == '__main__':
    unittest.main()
