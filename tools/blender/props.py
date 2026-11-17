"""Makes the small things of the city: python3 tools/blender/props.py assets/city

A car, a van, a coach of the train, the crown of a tree and its trunk, as
a few dozen triangles each, written to props.json. Each stands for one box
of the city that is never cut (see City and ShardMesh.add_model): it is
drawn in place of the box's six faces, and flies off with it when it is
kicked. Shapes are made with Blender's bmesh (boxes, bevels, an icosphere),
in metres, x across, y up, z along, then squeezed into the unit cube of the
box they stand for.

A corner of a triangle is a place, the way it faces, and a colour: r, g, b
and whether the box's own paint goes on it (then r, g, b only shade it).

Needs Blender as a Python module (pip install bpy).
"""

import json
import os
import random
import sys

import bpy  # noqa: F401 (before bmesh: it is what makes bmesh importable)
import bmesh  # isort: skip

PAINT = (1.0, 1.0, 1.0, 1)
GLASS = (0.1, 0.15, 0.22, 0)
TYRE = (0.05, 0.05, 0.06, 0)


def box(size, at, bevel=0.0, taper=1.0):
    """A box `size` big, its middle at `at`; `taper` narrows its top."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        narrow = taper if v.co.y > 0 else 1.0
        v.co.x = v.co.x * size[0] * narrow + at[0]
        v.co.z = v.co.z * size[2] * narrow + at[2]
        v.co.y = v.co.y * size[1] + at[1]
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES", profile=0.5)
    return bm


def corners(bm, colour, smooth=False):
    """The triangles of `bm`, clockwise as Godot wants them."""
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    out = []
    for face in bm.faces:
        rgbp = colour(face) if callable(colour) else colour
        verts = [loop.vert for loop in face.loops]
        for v in (verts[0], verts[2], verts[1]):
            facing = v.normal if smooth else face.normal
            out.append((tuple(v.co), tuple(facing), rgbp))
    bm.free()
    return out


def roofed(face):
    return PAINT if face.normal.y > 0.5 else GLASS


def car():
    parts = corners(box((0.24, 0.085, 0.5), (0, 0.0775, 0), bevel=0.015), PAINT)
    parts += corners(box((0.2, 0.08, 0.27), (0, 0.16, 0.02), taper=0.8), roofed)
    for z in (-0.15, 0.15):
        parts += corners(box((0.25, 0.075, 0.1), (0, 0.0375, z)), TYRE)
    return (0.24, 0.2, 0.5), parts


def van():
    parts = corners(box((0.24, 0.1, 0.5), (0, 0.085, 0), bevel=0.015), PAINT)
    parts += corners(box((0.225, 0.065, 0.44), (0, 0.1675, 0.02), taper=0.92), roofed)
    for z in (-0.15, 0.15):
        parts += corners(box((0.25, 0.075, 0.1), (0, 0.0375, z)), TYRE)
    return (0.24, 0.2, 0.5), parts


def coach():
    parts = corners(box((0.92, 0.26, 0.34), (0, 0.13, 0), bevel=0.03), PAINT)
    for z in (-0.166, 0.166):
        parts += corners(box((0.78, 0.09, 0.012), (0, 0.165, z)), GLASS)
    return (0.92, 0.26, 0.34), parts


def crown():
    rng = random.Random(3)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.46)
    for v in bm.verts:
        v.co *= rng.uniform(0.86, 1.08)
        v.co.y = v.co.y * 0.92 + 0.5

    def leaf(face):
        tone = rng.uniform(0.8, 1.12)
        return (tone, tone, tone, 1)

    return (1.0, 1.0, 1.0), corners(bm, leaf)


def trunk():
    return (1.0, 1.0, 1.0), corners(box((1.0, 1.0, 1.0), (0, 0.5, 0), taper=0.6), PAINT)


def main(out):
    props = {}
    for make in (car, van, coach, crown, trunk):
        size, parts = make()
        places, facings, colours = [], [], []
        for place, facing, rgbp in parts:
            places += [round(place[0] / size[0], 4), round(place[1] / size[1] - 0.5, 4), round(place[2] / size[2], 4)]
            facings += [round(c, 3) for c in facing]
            colours += [round(c, 3) for c in rgbp]
        props[make.__name__] = {"v": places, "n": facings, "c": colours}
        print(make.__name__, len(parts) // 3, "triangles")
    with open(os.path.join(out, "props.json"), "w") as f:
        json.dump(props, f, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1])
