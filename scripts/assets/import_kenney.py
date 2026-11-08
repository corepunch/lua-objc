#!/usr/bin/env python3
"""Import an unzipped Kenney kit into assets/kenney/<kit>/.

    python3 -I scripts/assets/import_kenney.py <unzipped-kit-folder> <kit-name>

Copies the kit's glTF models (models/*.glb), their palette textures
(models/Textures/), one preview image per model (previews/) and the license,
then the manifest is generated with scripts/assets/manifest.lua.

Every model is checked against its OBJ twin, which is Kenney's own export
and the reference for where a model stands. Newer kits match it as shipped.
Older kits (Racing Kit 2018, Space Kit 2020) were exported to glTF through
Unity, which left each model turned 180 degrees about the vertical axis and
moved by a stray root translation; for those the script rewrites the root
nodes' transforms (and makes the scene's roots real roots) so the model
matches its OBJ, and converts their sRGB colour factors to the linear values
glTF specifies. A model that matches neither way is refused, never copied.
"""
import json
import math
import shutil
import struct
import sys
from pathlib import Path

# Exports of one model may pose small moving parts a little differently
# (Space Kit's turret_single barrels differ by 0.022); misplacement is metres.
TOLERANCE = 0.03
TURN = [0.0, 1.0, 0.0, 0.0]  # quaternion x y z w: 180 degrees about +Y


def read_glb(path):
    data = path.read_bytes()
    if data[:4] != b'glTF':
        raise ValueError(f'{path.name}: not a binary glTF')
    length = struct.unpack_from('<I', data, 12)[0]
    document = json.loads(data[20:20 + length])
    rest = data[20 + ((length + 3) & ~3):]
    return document, rest


def write_glb(path, document, rest):
    text = json.dumps(document, separators=(',', ':')).encode()
    text += b' ' * ((4 - len(text) % 4) % 4)
    body = struct.pack('<I4s', len(text), b'JSON') + text + rest
    path.write_bytes(struct.pack('<4sII', b'glTF', 2, 12 + len(body)) + body)


def rotate(q, v):
    x, y, z, w = q
    tx, ty, tz = 2 * (y * v[2] - z * v[1]), 2 * (z * v[0] - x * v[2]), 2 * (x * v[1] - y * v[0])
    return (v[0] + w * tx + (y * tz - z * ty), v[1] + w * ty + (z * tx - x * tz), v[2] + w * tz + (x * ty - y * tx))


def scene_roots(document):
    scenes = document.get('scenes') or [{'nodes': list(range(len(document['nodes'])))}]
    return scenes[document.get('scene', 0)]['nodes']


def bounds(document, rest):
    """World bounds of the default scene, as a reader that trusts the scene's roots draws it."""
    binary = rest[8:] if rest[4:8] == b'BIN\x00' else b''
    nodes, low, high = document['nodes'], [math.inf] * 3, [-math.inf] * 3

    def walk(index, chain):
        node = nodes[index]
        chain = chain + [(node.get('translation', [0, 0, 0]), node.get('rotation', [0, 0, 0, 1]), node.get('scale', [1, 1, 1]))]
        if 'mesh' in node:
            for primitive in document['meshes'][node['mesh']]['primitives']:
                accessor = document['accessors'][primitive['attributes']['POSITION']]
                view = document['bufferViews'][accessor['bufferView']]
                stride = view.get('byteStride', 12)
                offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
                for k in range(accessor['count']):
                    v = struct.unpack_from('<3f', binary, offset + k * stride)
                    for t, r, s in reversed(chain):
                        v = rotate(r, (v[0] * s[0], v[1] * s[1], v[2] * s[2]))
                        v = (v[0] + t[0], v[1] + t[1], v[2] + t[2])
                    for d in range(3):
                        low[d], high[d] = min(low[d], v[d]), max(high[d], v[d])
        for child in node.get('children', []):
            walk(child, chain)

    for root in scene_roots(document):
        walk(root, [])
    return low, high


def obj_bounds(path):
    vertices = [list(map(float, line.split()[1:4])) for line in path.read_text().splitlines() if line.startswith('v ')]
    return [min(v[d] for v in vertices) for d in range(3)], [max(v[d] for v in vertices) for d in range(3)]


def linearized(document):
    """UniGLTF (Racing and Space kits) wrote sRGB colours, such as #E85553,
    into baseColorFactor, which glTF defines as linear. Converted, the
    colours render as Kenney's previews show them; as shipped, washed out."""
    if not str(document.get('asset', {}).get('generator', '')).startswith('UniGLTF'):
        return None
    fixed = json.loads(json.dumps(document))
    for material in fixed.get('materials', []):
        factor = material.get('pbrMetallicRoughness', {}).get('baseColorFactor')
        if factor:
            factor[:3] = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in factor[:3]]
    return fixed


def matches(a, b):
    return all(abs(a[i][d] - b[i][d]) <= TOLERANCE for i in (0, 1) for d in range(3))


def turned(document):
    """The document with Unity's turn and stray translation taken off its roots."""
    fixed = json.loads(json.dumps(document))
    roots = scene_roots(fixed)
    for node in fixed['nodes']:
        node['children'] = [c for c in node.get('children', []) if c not in roots]
        if not node['children']:
            node.pop('children')
    for root in roots:
        node = fixed['nodes'][root]
        if 'matrix' in node:
            raise ValueError('a root with a matrix cannot be corrected')
        node['translation'] = [0, 0, 0]
        node['rotation'] = multiply(TURN, node.get('rotation', [0, 0, 0, 1]))
    return fixed


def multiply(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz]


def main():
    source, kit = Path(sys.argv[1]), sys.argv[2]
    models = next((source / 'Models' / name for name in ('GLB format', 'GLTF format') if (source / 'Models' / name).is_dir()), None)
    if not models:
        sys.exit(f'{source}: no Models/GLB format or Models/GLTF format folder')
    objs = source / 'Models' / 'OBJ format'
    target = Path('assets/kenney') / kit
    if target.exists():
        shutil.rmtree(target)
    (target / 'models').mkdir(parents=True)
    (target / 'previews').mkdir()
    corrected, refused = [], []
    for glb in sorted(models.glob('*.glb')):
        document, rest = read_glb(glb)
        twin = objs / (glb.stem + '.obj')
        if twin.exists():
            reference = obj_bounds(twin)
            if not matches(bounds(document, rest), reference):
                try:
                    fixed = turned(document)
                except ValueError:
                    fixed = None
                if not fixed or not matches(bounds(fixed, rest), reference):
                    refused.append(glb.stem)
                    continue
                document = fixed
                corrected.append(glb.stem)
        colours = linearized(document)
        if colours is not None:
            document = colours
        if colours is not None or glb.stem in corrected:
            write_glb(target / 'models' / glb.name, document, rest)
        else:
            shutil.copy2(glb, target / 'models' / glb.name)  # as shipped, byte for byte
    if (models / 'Textures').is_dir():
        shutil.copytree(models / 'Textures', target / 'models' / 'Textures')
    for glb in (target / 'models').glob('*.glb'):
        candidates = [source / 'Previews' / f'{glb.stem}.png'] + sorted((source / 'Isometric').glob(f'{glb.stem}_NE.png')) \
            + sorted((source / 'Isometric').glob(f'{glb.stem}_*.png'))
        preview = next((p for p in candidates if p.exists()), None)
        if preview:
            shutil.copy2(preview, target / 'previews' / f'{glb.stem}.png')
    shutil.copy2(source / 'License.txt', target / 'License.txt')
    print(f'{kit}: {len(list((target / "models").glob("*.glb")))} models, {len(corrected)} corrected to match their OBJ')
    if refused:
        sys.exit(f'{kit}: refused, matching their OBJ neither as shipped nor corrected: {", ".join(refused)}')


if __name__ == '__main__':
    main()
