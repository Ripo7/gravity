"""Builds the shard library: how concrete, wood and metal blocks break.

Run with Blender's Python module (pip install bpy), from the project root:

    python3 tools/make_shards.py

Blender does the cutting: every pattern is a unit cube split into Voronoi
cells with bmesh bisects (the same method as Blender's Cell Fracture),
stretched along the grain for wood, cut across into torn lengths for metal.
Each shard is then sampled onto one shared vertex layout (a subdivided cube
wrapped around the shard) so the game can draw every shard of every
pattern with a single mesh, one draw call, reading the shape from a
texture. The fracture faces are roughened while sampling.

Outputs:
  assets/shards/shards.json   the library the game loads
  art/shards_preview.glb      every pattern laid out, to look at in Blender
                              or Godot (art/ is ignored by Godot)
"""

import base64
import json
import math
import os
import random
import struct

import bpy  # first: it makes bmesh and mathutils importable
import bmesh
from mathutils import Vector, noise
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_JSON = os.path.join(ROOT, "assets", "shards", "shards.json")
OUT_GLB = os.path.join(ROOT, "art", "shards_preview.glb")

GRID = 5  # base layout: cube faces split GRID x GRID -> 6*GRID^2+2 vertices
MAX_HULL = 20  # collision hull points per shard

# Patterns per material: (piece count, variants).
PATTERNS = {
    "concrete": [(2, 3), (3, 2), (4, 2), (5, 2), (6, 2), (8, 2), (10, 2)],
    "wood": [(2, 2), (3, 2), (4, 2), (6, 2), (8, 2)],
    "metal": [(2, 3), (3, 3)],
}
# Roughness of the fracture faces (unit-cube units, inward only).
ROUGH = {"concrete": 0.045, "wood": 0.06, "metal": 0.05}


# --- Shared vertex layout -------------------------------------------------------


def base_layout():
    """Unique points on the unit cube surface, GRID cells per face edge, and
    triangles wound clockwise seen from outside (Godot's front faces)."""
    index = {}
    points = []
    tris = []

    def vid(p):
        key = tuple(int(round(c * 2 * GRID)) for c in p)
        if key not in index:
            index[key] = len(points)
            points.append(Vector(p))
        return index[key]

    for axis in range(3):
        for sign in (-1.0, 1.0):
            u_axis = (axis + 1) % 3
            v_axis = (axis + 2) % 3
            grid = []
            for a in range(GRID + 1):
                row = []
                for b in range(GRID + 1):
                    p = [0.0, 0.0, 0.0]
                    p[axis] = 0.5 * sign
                    p[u_axis] = -0.5 + a / GRID
                    p[v_axis] = -0.5 + b / GRID
                    row.append(vid(p))
                grid.append(row)
            normal = Vector([0.0, 0.0, 0.0])
            normal[axis] = sign
            for a in range(GRID):
                for b in range(GRID):
                    q = [grid[a][b], grid[a + 1][b], grid[a + 1][b + 1], grid[a][b + 1]]
                    for t in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                        pa, pb, pc = (points[i] for i in t)
                        if (pb - pa).cross(pc - pa).dot(normal) > 0.0:
                            t = (t[0], t[2], t[1])
                        tris.extend(t)
    return points, tris


# --- Cutting ----------------------------------------------------------------------


def unit_cube(scale=(1.0, 1.0, 1.0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    for f in bm.faces:
        f.material_index = 0  # outside of the block
    return bm


def cut(bm, co, no):
    """Keeps the side of the plane behind `no`, closing the hole with a
    fracture face (material 1)."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True, dist=1e-6)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if not edges:
        return
    before = set(bm.faces)
    try:
        bmesh.ops.edgeloop_fill(bm, edges=edges)
    except RuntimeError:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    for f in bm.faces:
        if f not in before:
            f.material_index = 1


def voronoi_cells(count, rng, stretch=(1.0, 1.0, 1.0)):
    """Splits a box (unit cube times `stretch`) into Voronoi cells around
    random seeds, then scales them back into the unit cube."""
    seeds = []
    while len(seeds) < count:
        p = Vector((rng.uniform(-0.45, 0.45) * stretch[0],
                    rng.uniform(-0.45, 0.45) * stretch[1],
                    rng.uniform(-0.45, 0.45) * stretch[2]))
        if all((p - s).length > 0.18 * min(stretch) / math.sqrt(count) for s in seeds):
            seeds.append(p)
    cells = []
    for i, s in enumerate(seeds):
        bm = unit_cube(stretch)
        for j, t in enumerate(seeds):
            if i != j:
                cut(bm, (s + t) * 0.5, (t - s).normalized())
        if len(bm.faces) < 4:
            bm.free()
            continue
        for v in bm.verts:
            v.co = Vector((v.co.x / stretch[0], v.co.y / stretch[1], v.co.z / stretch[2]))
        cells.append(bm)
    return cells


def torn_lengths(count, rng):
    """Metal: cut across the length (x) into `count` pieces, along slightly
    tilted planes; the ragged look comes from the roughening."""
    edges = sorted(rng.uniform(-0.3, 0.3) for _ in range(count - 1))
    pieces = []
    bounds = [-1.0] + edges + [1.0]
    for k in range(count):
        bm = unit_cube()
        lo, hi = bounds[k], bounds[k + 1]
        tilt = lambda: Vector((1.0, rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35))).normalized()
        if lo > -0.9:
            cut(bm, Vector((lo, 0, 0)), -tilt())
        if hi < 0.9:
            cut(bm, Vector((hi, 0, 0)), tilt())
        pieces.append(bm)
    return pieces


# --- Sampling onto the shared layout ---------------------------------------------


def rough(kind, p, seed):
    q = p * 9.0 + Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    if kind == "wood":
        # Splinters: ridges that run along the grain (x).
        q = Vector((p.x * 3.0, p.y * 28.0, p.z * 28.0)) + Vector((seed * 5.0, 0, 0))
        return 0.5 + 0.5 * noise.noise(q)
    if kind == "metal":
        # Torn: sharp spikes.
        return abs(noise.noise(q * 2.5)) * 1.6
    return 0.5 + 0.5 * noise.fractal(q, 0.6, 2.0, 3)


def sample(bm, layout, kind, seed):
    bm.normal_update()
    tree = BVHTree.FromBMesh(bm)
    centre = Vector()
    for v in bm.verts:
        centre += v.co
    centre /= len(bm.verts)
    mats = [f.material_index for f in bm.faces]
    bm.faces.ensure_lookup_table()
    out = []
    for p in layout:
        d = p.normalized()
        hit = tree.ray_cast(centre, d)
        if hit[0] is None:
            loc, _, idx, _ = tree.find_nearest(centre + d)
        else:
            loc, _, idx, _ = hit
        outer = 1.0 if mats[idx] == 0 else 0.0
        if outer < 0.5:
            depth = (loc - centre).length
            loc = loc - d * min(ROUGH[kind] * rough(kind, loc, seed), depth * 0.35)
        out.append((loc, outer))
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
    mid = (lo + hi) * 0.5
    verts = [((loc - mid), outer) for loc, outer in out]
    hull = farthest_points([v.co - mid for v in bm.verts], MAX_HULL)
    return {
        "verts": verts,
        "center": list(mid),
        "size": list(hi - lo),
        "hull": [c for v in hull for c in v],
        "volume": bm.calc_volume(),
    }


def farthest_points(points, k):
    unique = []
    for p in points:
        if all((p - q).length > 1e-4 for q in unique):
            unique.append(p)
    if len(unique) <= k:
        return unique
    chosen = [max(unique, key=lambda p: p.length)]
    while len(chosen) < k:
        chosen.append(max(unique, key=lambda p: min((p - c).length for c in chosen)))
    return chosen


def half(x):
    return struct.pack("<e", x)


# --- Preview ----------------------------------------------------------------------


def add_preview(bm, name, offset, material_kind):
    mesh = bpy.data.meshes.new(name)
    copy = bm.copy()
    for v in copy.verts:
        v.co = v.co * 0.96 + offset
    copy.to_mesh(mesh)
    copy.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.get(material_kind) or bpy.data.materials.new(material_kind)
    mesh.materials.append(mat)


def main():
    rng = random.Random(1234)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    layout, tris = base_layout()
    rows = []
    library = {}
    for kind, plan in PATTERNS.items():
        library[kind] = []
        row_y = list(PATTERNS).index(kind) * 3.0
        col = 0
        for count, variants in plan:
            for _ in range(variants):
                if kind == "metal":
                    cells = torn_lengths(count, rng)
                elif kind == "wood":
                    # Squashed along the grain before cutting, so the cells come
                    # out long and thin along it once scaled back: splinters.
                    cells = voronoi_cells(count, rng, (0.25, 1.0, 1.0))
                else:
                    cells = voronoi_cells(count, rng)
                pattern = {"count": len(cells), "shards": []}
                for k, bm in enumerate(cells):
                    s = sample(bm, layout, kind, rng.random())
                    s["id"] = len(rows)
                    rows.append(s.pop("verts"))
                    pattern["shards"].append(s)
                    explode = Vector(s["center"]) * 0.35
                    add_preview(bm, "%s_%d_%d" % (kind, col, k), Vector((col * 1.8, row_y, 0)) + explode, kind)
                    bm.free()
                library[kind].append(pattern)
                col += 1
                print("%s: pattern %d with %d pieces" % (kind, col, pattern["count"]))
    data = bytearray()
    for row in rows:
        for loc, outer in row:
            data += half(loc.x) + half(loc.y) + half(loc.z) + half(outer)
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w") as f:
        json.dump(
            {
                "grid": GRID,
                "base_vertices": [c for p in layout for c in p],
                "indices": tris,
                "vertex_count": len(layout),
                "shard_count": len(rows),
                "shapes_rgba16f_b64": base64.b64encode(bytes(data)).decode(),
                "materials": library,
            },
            f,
            separators=(",", ":"),
        )
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB")
    print("%d shards, %d vertices each -> %s" % (len(rows), len(layout), OUT_JSON))


if __name__ == "__main__":
    main()
