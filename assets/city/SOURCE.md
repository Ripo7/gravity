# The walls of the city

`facades_albedo.png` and `facades_normal.png` are made by
`tools/blender/facades.py`: nothing here is drawn by hand or taken from
elsewhere.

    pip install bpy numpy pillow
    python3 tools/blender/facades.py assets/city     # about 75 s

Each tile is one bay of one floor of a wall, modelled in Blender (bmesh
boxes with bevels: windows set back in the wall, frames, sills, shutters,
an awning, cornices; bricks, concrete, gravel and roof tiles) and baked by
Cycles, seen straight on, with copies of itself all round so that it
repeats: its colours, the shade its relief casts on itself, where the
box's own paint goes (alpha), and its relief as a normal map.

Four columns of four 256 px tiles: a house, an office, a tower (ground
floor, a floor in between, top floor), then roof tiles, bricks, concrete
and gravel. `ShardMesh` cuts them into the layers of a texture and
`shaders/shards.gdshader` lays them on the boxes, bay by bay and floor by
floor.
