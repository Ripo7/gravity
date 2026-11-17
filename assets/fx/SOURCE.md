# What flies and hangs in the air where something breaks

Both files are made by Blender, as a Python module (`pip install bpy`):

    python3 tools/blender/rubble.py assets/fx    # a second
    python3 tools/blender/dust.py assets/fx      # three or four minutes

`rubble.json`: six little models made with bmesh (a brick with one end
broken off, a lump of concrete with a bar sticking out, a shard of glass,
a piece of roof tile, two leaves, a splinter), 8 to 36 triangles each.
`Chips` draws each kind through a MultiMesh, every bit with its own size,
squash and colour.

`dust.png`: a cloud of dust, sixteen frames of its life in a sheet of 4
by 4 (128 px each). A ball of volume whose density is a noise that
swells, billows and is eaten away as it ages, lit by a sun from above and
a pale sky, rendered by Cycles (96 samples). White where the sun gets;
`Dust` tints it with what broke and plays it once through each puff.
