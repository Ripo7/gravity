"""Makes the small bits that fly where something breaks: python3 tools/blender/rubble.py assets/fx

Each is a little model made with bmesh, a few triangles, a metre or so
across (the game gives each bit its own size, squash and colour):

  rubble.json   brick     a brick with one end broken off
                lump      a lump of concrete, a bar sticking out of it
                glass     a shard of a pane
                tile      a piece of a roof tile
                leaf      two leaves on a twig
                splinter  a splinter of wood

For each, per corner of each triangle (clockwise, as Godot draws them): "v"
where it is, "n" which way it faces, "c" how light it is there (the game
multiplies the colour of the bit by it: the broken end of a brick is paler,
the bar in the concrete is dark).

Needs Blender as a Python module (pip install bpy).
"""

import json
import math
import os
import random
import sys

import bpy  # (before bmesh: it is what makes bmesh importable)
import bmesh  # isort: skip
from mathutils import Matrix, Vector


def shade(bm, tone):
    """Marks every face not yet marked as `tone` light."""
    layer = bm.faces.layers.float.get("tone") or bm.faces.layers.float.new("tone")
    done = bm.faces.layers.int.get("done") or bm.faces.layers.int.new("done")
    for face in bm.faces:
        if not face[done]:
            face[layer] = tone
            face[done] = 1


def brick(rng):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= 2.0
        v.co.y *= 0.9
        v.co.z *= 1.2
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.06, segments=1, affect="EDGES")
    shade(bm, 1.0)
    # One end broken off, askew: the clay inside is paler.
    cut = bmesh.ops.bisect_plane(
        bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0.45, 0, 0), plane_no=(1.0, 0.35, 0.25), clear_outer=True
    )
    rim = [e for e in cut["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    bmesh.ops.edgeloop_fill(bm, edges=rim)
    for face in bm.faces:
        for v in face.verts:
            if v.co.x > 0.2:
                v.co += Vector((rng.uniform(-0.04, 0.04), rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03)))
    shade(bm, 1.35)
    return bm


def lump(rng):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in bm.verts:
        v.co *= rng.uniform(0.72, 1.12)
        v.co.z *= 0.7
    shade(bm, 1.0)
    # A bar of the reinforcement, bent, sticking out.
    bar = bmesh.ops.create_cube(bm, size=1.0)
    turn = Matrix.Rotation(math.radians(35), 4, "Y") @ Matrix.Rotation(math.radians(20), 4, "Z")
    for v in bar["verts"]:
        v.co.x *= 1.5
        v.co.y *= 0.09
        v.co.z *= 0.09
        v.co = turn @ v.co + Vector((0.75, 0.1, 0.3))
    shade(bm, 0.35)
    return bm


def flat(rng, corners, thick, tone, edge):
    """A flat bit through `corners` (x, y), `thick` thick; its edge is `edge` light."""
    bm = bmesh.new()
    low = [bm.verts.new((x, y, -thick / 2)) for x, y in corners]
    high = [bm.verts.new((x, y, thick / 2)) for x, y in corners]
    bm.faces.new(high)
    bm.faces.new(list(reversed(low)))
    shade(bm, tone)
    n = len(corners)
    for k in range(n):
        bm.faces.new([low[k], low[(k + 1) % n], high[(k + 1) % n], high[k]])
    shade(bm, edge)
    return bm


def glass(rng):
    return flat(rng, [(-1.0, -0.45), (0.2, -0.75), (1.0, 0.1), (0.1, 0.7), (-0.55, 0.3)], 0.06, 1.0, 1.5)


def tile(rng):
    bm = flat(rng, [(-1.0, -0.7), (0.6, -0.7), (1.0, 0.1), (0.3, 0.7), (-1.0, 0.7)], 0.16, 1.0, 1.3)
    for v in bm.verts:  # arched, like the tile it was
        v.co.z += 0.25 * (1.0 - (v.co.y / 0.7) ** 2)
    return bm


def leaf(rng):
    bm = bmesh.new()
    for side in (-1.0, 1.0):
        blade = [(0.0, 0.0), (0.45 * side, 0.3), (1.0 * side, 0.1), (0.5 * side, -0.25)]
        bm.faces.new([bm.verts.new((x, y, 0.12 * abs(x))) for x, y in blade])
        bm.faces.new([bm.verts.new((x, y, 0.12 * abs(x) - 0.01)) for x, y in reversed(blade)])
    shade(bm, 1.0)
    return bm


def splinter(rng):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= 2.0
        thin = 0.35 if v.co.x > 0 else 1.0  # it tapers to a point
        v.co.y *= 0.22 * thin
        v.co.z *= 0.16 * thin
    shade(bm, 1.0)
    return bm


def flatten(bm):
    """The model as a list of triangles, turned from Blender's z up to the game's y up."""
    tone = bm.faces.layers.float["tone"]
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    far = max(v.co.length for v in bm.verts)
    out = {"v": [], "n": [], "c": []}
    for face in bm.faces:
        n = face.normal
        for v in reversed(face.verts):
            out["v"] += [round(v.co.x / far, 4), round(v.co.z / far, 4), round(-v.co.y / far, 4)]
            out["n"] += [round(n.x, 3), round(n.z, 3), round(-n.y, 3)]
            out["c"].append(round(face[tone], 2))
    return out


def main(out):
    rng = random.Random(11)
    models = {}
    for make in (brick, lump, glass, tile, leaf, splinter):
        bm = make(rng)
        models[make.__name__] = flatten(bm)
        print(make.__name__, len(models[make.__name__]["c"]) // 3, "triangles")
        bm.free()
    with open(os.path.join(out, "rubble.json"), "w") as f:
        json.dump(models, f, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1])
