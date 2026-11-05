"""Models the palace's carved pieces in Blender: column capitals and bases,
the cornice brackets, the bands of the campanile's dome and the bell.

Run with Blender's Python module (pip install bpy), from the project root:

    python3 tools/make_sculptures.py

Each piece is built with bmesh from its profile (turned on a lathe, or
drawn and pushed out), smoothed where it is round and kept sharp where it
is cut square, then fitted into the unit cube: the game stretches it to the
block it stands for (scripts/destruction/shape_library.gd), so a carved
piece is still a block of the building, breaks like one and is drawn with
the same shader, one draw call per kind of piece.

Output: assets/shapes/shapes.json (vertices, normals, triangles wound the
way Godot draws front faces) and art/sculptures_preview.glb.
"""

import json
import math
import os

import bpy  # first: it makes bmesh and mathutils importable
import bmesh
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_JSON = os.path.join(ROOT, "assets", "shapes", "shapes.json")
OUT_GLB = os.path.join(ROOT, "art", "sculptures_preview.glb")
SIDES = 16  # around a turned piece (phones draw every column)

# The campanile's dome: (diameter, height) of each copper band, bottom up,
# and the top of the last one (keep in step with scripts/destruction/palazzo.gd).
DOME = [(3.4, 0.6), (2.8, 0.55), (2.1, 0.5), (1.3, 0.45), (0.7, 0.5)]
DOME_TOP = 0.36


def lathe(bm, profile, smooth=True):
    """Turns a profile [(radius, y), ...] (bottom to top) round the y axis.
    Rings with radius 0 close the ends."""
    rings = []
    for r, y in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((0.0, y, 0.0))])
            continue
        rings.append([bm.verts.new((r * math.cos(a), y, r * math.sin(a))) for a in
                      (2 * math.pi * k / SIDES for k in range(SIDES))])
    for a, b in zip(rings, rings[1:]):
        for k in range(SIDES):
            pa = a[k % len(a)]
            pb = a[(k + 1) % len(a)]
            qa = b[k % len(b)]
            qb = b[(k + 1) % len(b)]
            quad = [v for v in (pa, pb, qb, qa)]
            uniq = list(dict.fromkeys(quad))
            if len(uniq) >= 3:
                f = bm.faces.new(uniq)
                f.smooth = smooth
    for ring in (rings[0], rings[-1]):
        if len(ring) > 2:
            f = bm.faces.new(ring)
            f.smooth = False


def box(bm, lo, hi):
    """A square block from corner `lo` to `hi` (sharp edges)."""
    res = bmesh.ops.create_cube(bm, size=1.0)
    for v in res["verts"]:
        v.co = Vector(tuple(lo[k] + (v.co[k] + 0.5) * (hi[k] - lo[k]) for k in range(3)))
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.smooth = False


def arc(r0, y0, r1, y1, bulge, steps):
    """Points of a curved profile from (r0, y0) to (r1, y1), bowed out by
    `bulge` (radius units)."""
    out = []
    for k in range(steps + 1):
        t = k / steps
        out.append((r0 + (r1 - r0) * t + bulge * math.sin(math.pi * t), y0 + (y1 - y0) * t))
    return out


def capital():
    """Tuscan capital: necking, a bead, the echinus (a quarter round) and a
    square abacus; the shaft below is 0.74 of its width."""
    bm = bmesh.new()
    shaft = 0.37
    prof = [(0.0, 0.0), (shaft, 0.0), (shaft, 0.1)]
    prof += [(shaft + 0.045 * math.sin(math.pi * k / 6), 0.1 + 0.1 * k / 6) for k in range(1, 7)]  # bead
    prof += [(shaft, 0.24), (shaft, 0.4)]
    prof += [(shaft + 0.13 * math.sin(0.5 * math.pi * k / 8), 0.4 + 0.28 * (1 - math.cos(0.5 * math.pi * k / 8))) for k in range(1, 9)]
    prof += [(0.0, 0.68)]
    lathe(bm, prof)
    box(bm, (-0.5, 0.68, -0.5), (0.5, 1.0, 0.5))
    return bm


def base():
    """Attic base: square plinth, a big torus, a hollow, a small torus."""
    bm = bmesh.new()
    box(bm, (-0.5, 0.0, -0.5), (0.5, 0.3, 0.5))
    prof = [(0.0, 0.3)]
    prof += arc(0.44, 0.3, 0.44, 0.55, 0.05, 6)  # lower torus
    prof += arc(0.4, 0.58, 0.4, 0.74, -0.03, 4)  # hollow (scotia)
    prof += arc(0.4, 0.76, 0.39, 0.9, 0.03, 4)  # upper torus
    prof += [(0.37, 0.92), (0.37, 1.0), (0.0, 1.0)]
    lathe(bm, prof)
    return bm


def console():
    """Cornice bracket (modillion): an S-curved scroll pushed out of the
    wall; its profile in (depth z, height y), extruded along x."""
    bm = bmesh.new()
    pts = [(-0.5, 0.0), (-0.5, 1.0), (0.5, 1.0), (0.5, 0.82)]
    # Underside: a reverse curve from the tip back to the wall, with a
    # rolled end (volute) under the tip.
    for k in range(1, 7):
        a = math.pi * 0.5 * k / 6
        pts.append((0.5 - 0.18 * (1 - math.cos(a)), 0.82 - 0.18 * math.sin(a)))
    for k in range(1, 11):
        t = k / 10
        z = 0.32 - 0.82 * t
        y = 0.64 - 0.6 * (0.5 - 0.5 * math.cos(math.pi * t))
        pts.append((z, y))
    verts_l = [bm.verts.new((-0.5, y, z)) for z, y in pts]
    verts_r = [bm.verts.new((0.5, y, z)) for z, y in pts]
    n = len(pts)
    for k in range(n):
        f = bm.faces.new([verts_l[k], verts_l[(k + 1) % n], verts_r[(k + 1) % n], verts_r[k]])
        f.smooth = k >= 3
    for side in (verts_l, verts_r):
        f = bm.faces.new(side)
        f.smooth = False
    return bm


def dome_profile():
    """Radius of the dome by height (all bands), a smooth curve through
    the bands' edges."""
    edges = []
    y = 0.0
    for d, h in DOME:
        edges.append((d * 0.5, y))
        y += h
    edges.append((DOME_TOP * 0.5, y))
    return edges


def dome_band(k):
    """Band k of the copper dome, its own block: bottom radius 0.5."""
    edges = dome_profile()
    (r0, y0), (r1, y1) = edges[k], edges[k + 1]
    d, h = DOME[k]
    # Bowed out a little, more toward the top of the dome.
    bulge = (r0 - r1) * 0.18
    prof = [(0.0, 0.0)] + arc(r0, 0.0, r1, h, bulge, 6) + [(0.0, h)]
    bm = bmesh.new()
    lathe(bm, [(r / d, y / h) for r, y in prof])
    # Ribs: shallow ridges down the band (copper seams).
    return bm


def bell():
    """A bronze bell: shoulder, waist, flared lip; crown on top."""
    prof = [(0.0, 0.02), (0.5, 0.0), (0.49, 0.08), (0.42, 0.2), (0.34, 0.45), (0.31, 0.7),
            (0.3, 0.85), (0.24, 0.94), (0.12, 0.97), (0.1, 1.0), (0.0, 1.0)]
    bm = bmesh.new()
    lathe(bm, prof)
    return bm


SHAPES = {"capital": capital, "base": base, "console": console, "bell": bell}
for _k in range(len(DOME)):
    SHAPES["dome_%d" % _k] = (lambda k: lambda: dome_band(k))(_k)


def export(bm):
    """Fits the piece into the unit cube and lists it the way Godot wants:
    per-corner normals (smooth or sharp), clockwise front faces."""
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    lo = Vector((min(v.co[k] for v in bm.verts) for k in range(3)))
    hi = Vector((max(v.co[k] for v in bm.verts) for k in range(3)))
    size = hi - lo
    mid = (lo + hi) * 0.5
    for v in bm.verts:
        v.co = Vector(tuple((v.co[k] - mid[k]) / max(size[k], 1e-6) for k in range(3)))
    bm.normal_update()
    bmesh.ops.triangulate(bm, faces=bm.faces)
    verts, normals, index = [], [], []
    for f in bm.faces:
        corners = []
        for loop in f.loops:
            n = loop.vert.normal if f.smooth else f.normal
            verts.append([round(c, 5) for c in loop.vert.co])
            normals.append([round(c, 4) for c in n])
            corners.append(len(verts) - 1)
        index.extend([corners[0], corners[2], corners[1]])  # Blender CCW -> Godot CW
    return {"vertices": [c for v in verts for c in v], "normals": [c for n in normals for c in n],
            "indices": index}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    data = {}
    for k, (name, build) in enumerate(SHAPES.items()):
        bm = build()
        data[name] = export(bm)
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        obj = bpy.data.objects.new(name, mesh)
        obj.location = (k * 1.6, 0.0, 0.0)
        bpy.context.scene.collection.objects.link(obj)
        bm.free()
        print("%s: %d triangles" % (name, len(data[name]["indices"]) // 3))
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w") as f:
        json.dump({"shapes": data}, f, separators=(",", ":"))
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB")
    print("wrote", OUT_JSON)


if __name__ == "__main__":
    main()
