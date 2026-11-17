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

The two `.import` files are kept in the repository: they tell Godot to
store the pictures lossy (WebP, quality 0.9), a quarter of the size, with
nothing to see for it at the size they are shown.

Four columns of four 256 px tiles: a house, an office, a tower (ground
floor, a floor in between, top floor), then roof tiles, bricks, concrete
and gravel. `ShardMesh` cuts them into the layers of a texture and
`shaders/shards.gdshader` lays them on the boxes, bay by bay and floor by
floor.

# The small things of the city

`props.json` is made by `tools/blender/props.py` (a second or so):

    python3 tools/blender/props.py assets/city

A car, a van, a coach of the train, the crown of a tree and its trunk, 12
to 80 triangles each, made with Blender's bmesh (boxes, bevels, an
icosphere pulled about). Each stands for one box of the city that is never
cut; `ShardMesh.add_model` draws it in place of the box's six faces, in
the same single draw as everything else, and it flies off with the box
when it is kicked. A corner of a triangle is a place in the unit cube of
its box, the way it faces, and a colour with a mark saying whether the
box's own paint goes on it.

