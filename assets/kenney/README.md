# Kenney asset kits

Shared 3-D kits by [Kenney](https://kenney.nl), CC0 (see each kit's
`License.txt`). Every app and game template uses these copies; apps do not
carry their own. A standalone bundle (`scripts/ipad/bundle.py`) copies the
kits whose path its sources name.

```
assets/kenney/<kit>/
  models/*.glb            glTF models as Kenney ships them
  models/Textures/        the kit's palette texture(s), shared by every model
  previews/*.png          one picture per model, for people and agents
  manifest.lua            generated: size, footprint and tags per model
  License.txt
```

Models are drawn by `<Node model="assets/kenney/<kit>/models/<name>.glb">`.

| Kit | Models | For | Scale |
|---|---|---|---|
| `platformer-kit` | 153 | platformers: blocks, coins, springs, five animated characters | a block is 1 unit |
| `racing-kit` | 112 | race tracks: road tiles, barriers, stands, race cars | a road tile is 1 x 1, origin at its corner |
| `car-kit` | 50 | road vehicles, karts with the platformer characters, wheels, debris | a sedan is 2.55 long: scale 0.5 beside racing-kit |
| `space-kit` | 153 | space bases, terrain, rockets, craft, rocks, astronauts | a terrain tile is 1 x 1 |

The manifest gives every model's size; scale pieces from different kits so
they agree. All four use Kenney's flat low-poly look and sit together.

## Adding a kit

Download the kit from kenney.nl, unzip it into an empty folder outside the
repository, then:

```sh
python3 -I scripts/assets/import_kenney.py <unzipped-folder> <kit-name>
./lua-objc scripts/assets/manifest.lua assets/kenney/<kit-name>
```

The import checks every glTF model against Kenney's OBJ export of the same
model. Older kits exported through Unity (Racing 2018, Space 2020) come out
turned 180 degrees, moved and with sRGB colours in a linear field; the import
corrects those in the file, and refuses any model it cannot match.
