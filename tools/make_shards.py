"""Builds the shard library: how concrete, wood and metal blocks break.

Run with Blender's Python module (pip install bpy), from the project root:

    python3 tools/make_shards.py

Blender does the cutting: every pattern is a unit cube split into Voronoi
cells with bmesh bisects (the same method as Blender's Cell Fracture),
stretched along the grain for wood, cut across into torn lengths for metal.
Each concrete and wood shard is then cut again into a few sub-shards that
tile it exactly (the cascade): when a piece breaks a second time it splits
along cracks that were already inside it. The fracture seeds come from a
Geometry Nodes group (Mesh to Volume -> Distribute Points in Volume), so
they fill any closed shape, not just boxes.

Wall patterns are cut for walls that crack open in place: a unit cube split
into prisms through its thickness (z), seeded by a Geometry Nodes Poisson
disk on the face (Distribute Points on Faces with a minimum distance), so
the cells come out even, like stones. Their cut faces stay flat (a cracked
wall shows no gaps), and each cell lists the cells it touches and the area
of the face they share: the game links them into the wall's load paths.
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

# Patterns per material: (piece count, variants). A break asks for at most
# five pieces (see Fracture.max_pieces), so bigger patterns would never be used.
PATTERNS = {
    "concrete": [(2, 3), (3, 3), (4, 2), (5, 2), (6, 2)],
    "wood": [(2, 2), (3, 2), (4, 2), (6, 2)],
    "metal": [(2, 3), (3, 3)],
}
STATS = {"gn_points": 0, "fallbacks": 0}
# Wall patterns: face width / height they are cut for, and cell counts.
WALL_ASPECTS = (0.4, 1.0, 2.5)
WALL_COUNTS = (8, 16, 28)
# Materials whose shards are cut again into sub-shards (metal tears, it
# does not crumble).
CASCADE = ("concrete", "wood")
# Grain of the cut for wood (squashed along x before cutting: splinters).
STRETCH = {"concrete": (1.0, 1.0, 1.0), "wood": (0.25, 1.0, 1.0)}
# Roughness of the fracture faces (unit-cube units, inward only).
ROUGH = {"concrete": 0.045, "wood": 0.06, "metal": 0.05, "wall": 0.0}


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


def cut(bm, co, no, mat=1):
    """Keeps the side of the plane behind `no`, closing the hole with a
    fracture face (material `mat`: 1 for the first break, 2 for the cascade)."""
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
            f.material_index = mat


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


# --- The cascade: sub-shards ---------------------------------------------------


def seed_group():
    """Geometry Nodes: candidate fracture seeds scattered inside a closed
    mesh (Mesh to Volume -> Distribute Points in Volume -> Points to
    Vertices, so the evaluated object is a mesh whose vertices we read)."""
    ng = bpy.data.node_groups.get("FractureSeeds")
    if ng is not None:
        return ng
    ng = bpy.data.node_groups.new("FractureSeeds", "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    gin = ng.nodes.new("NodeGroupInput")
    gout = ng.nodes.new("NodeGroupOutput")
    to_volume = ng.nodes.new("GeometryNodeMeshToVolume")
    scatter = ng.nodes.new("GeometryNodeDistributePointsInVolume")
    scatter.name = "Scatter"  # its density and seed are set per shard
    to_verts = ng.nodes.new("GeometryNodePointsToVertices")
    set_input(to_volume, "Resolution Mode", "Amount", "resolution_mode", "VOXEL_AMOUNT")
    set_input(to_volume, "Voxel Amount", 48.0)
    link = ng.links.new
    link(gin.outputs["Geometry"], to_volume.inputs["Mesh"])
    link(to_volume.outputs["Volume"], scatter.inputs["Volume"])
    link(scatter.outputs["Points"], to_verts.inputs["Points"])
    link(to_verts.outputs["Mesh"], gout.inputs["Geometry"])
    return ng


def set_input(node, name, value, prop=None, prop_value=None):
    """Sets a node option that is a socket in newer Blender (5.x), a
    property in older ones."""
    sock = node.inputs.get(name)
    if sock is not None:
        sock.default_value = value
    elif prop is not None and hasattr(node, prop):
        setattr(node, prop, value if prop_value is None else prop_value)


def gn_seeds(bm, count, rng):
    """`count` well spread fracture seeds inside the closed mesh `bm`."""
    volume = max(bm.calc_volume(), 1e-6)
    mesh = bpy.data.meshes.new("cell")
    bm.to_mesh(mesh)
    obj = bpy.data.objects.new("cell", mesh)
    bpy.context.scene.collection.objects.link(obj)
    group = seed_group()
    scatter = group.nodes["Scatter"]
    scatter.inputs["Density"].default_value = 60.0 / volume
    scatter.inputs["Seed"].default_value = rng.randrange(1 << 20)
    mod = obj.modifiers.new("seeds", "NODES")
    mod.node_group = group
    obj.update_tag()
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    candidates = [v.co.copy() for v in evaluated.data.vertices]
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    STATS["gn_points"] += len(candidates)
    if len(candidates) < count:
        STATS["fallbacks"] += 1
        candidates += inside_points(bm, count * 8, rng)
    rng.shuffle(candidates)
    # Farthest-point picks: even-ish pieces, never two seeds side by side.
    chosen = [candidates[0]]
    while len(chosen) < count and len(chosen) < len(candidates):
        chosen.append(max(candidates, key=lambda p: min((p - c).length for c in chosen) * rng.uniform(0.7, 1.0)))
    return chosen


def inside_points(bm, n, rng):
    """Fallback seeds: random points inside a convex cell (behind every face)."""
    lo = Vector((min(v.co[k] for v in bm.verts) for k in range(3)))
    hi = Vector((max(v.co[k] for v in bm.verts) for k in range(3)))
    bm.normal_update()
    planes = [(f.calc_center_median(), f.normal.copy()) for f in bm.faces]
    out = []
    for _ in range(n * 50):
        p = Vector((rng.uniform(lo.x, hi.x), rng.uniform(lo.y, hi.y), rng.uniform(lo.z, hi.z)))
        if all((p - c).dot(no) < -1e-4 for c, no in planes):
            out.append(p)
            if len(out) >= n:
                break
    return out


def split_cell(cell, count, rng, stretch):
    """Cuts a shard (a closed bmesh in unit pattern space) into `count`
    sub-shards that tile it, along the grain given by `stretch`."""
    squashed = cell.copy()
    for v in squashed.verts:
        v.co = Vector((v.co.x * stretch[0], v.co.y * stretch[1], v.co.z * stretch[2]))
    seeds = gn_seeds(squashed, count, rng)
    parts = []
    for i, s in enumerate(seeds):
        bm = squashed.copy()
        for j, t in enumerate(seeds):
            if i != j:
                cut(bm, (s + t) * 0.5, (t - s).normalized(), 2)
        if len(bm.faces) < 4 or bm.calc_volume() < 1e-5:
            bm.free()
            continue
        for v in bm.verts:
            v.co = Vector((v.co.x / stretch[0], v.co.y / stretch[1], v.co.z / stretch[2]))
        parts.append(bm)
    squashed.free()
    return parts


def child_count(volume):
    """Sub-shards per shard: bigger shards crack into more pieces."""
    return 3 if volume < 0.12 else (4 if volume < 0.28 else 5)


# --- Wall patterns ------------------------------------------------------------------


def poisson_group():
    """Geometry Nodes: Poisson-disk points on a face (Distribute Points on
    Faces, minimum distance), as mesh vertices."""
    ng = bpy.data.node_groups.get("WallSeeds")
    if ng is not None:
        return ng
    ng = bpy.data.node_groups.new("WallSeeds", "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    gin = ng.nodes.new("NodeGroupInput")
    gout = ng.nodes.new("NodeGroupOutput")
    scatter = ng.nodes.new("GeometryNodeDistributePointsOnFaces")
    scatter.name = "Scatter"
    scatter.distribute_method = "POISSON"
    to_verts = ng.nodes.new("GeometryNodePointsToVertices")
    ng.links.new(gin.outputs["Geometry"], scatter.inputs["Mesh"])
    ng.links.new(scatter.outputs["Points"], to_verts.inputs["Points"])
    ng.links.new(to_verts.outputs["Mesh"], gout.inputs["Geometry"])
    return ng


def wall_seeds(aspect, count, rng):
    """`count` seeds on a face `aspect` wide and 1 high (z = 0)."""
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.5)
    for v in bm.verts:
        v.co.x *= aspect
    mesh = bpy.data.meshes.new("face")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("face", mesh)
    bpy.context.scene.collection.objects.link(obj)
    group = poisson_group()
    scatter = group.nodes["Scatter"]
    scatter.inputs["Distance Min"].default_value = 0.8 * math.sqrt(aspect / count)
    scatter.inputs["Density Max"].default_value = 40.0 * count / aspect
    scatter.inputs["Seed"].default_value = rng.randrange(1 << 20)
    mod = obj.modifiers.new("seeds", "NODES")
    mod.node_group = group
    obj.update_tag()
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    points = [Vector((v.co.x, v.co.y, 0.0)) for v in evaluated.data.vertices]
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    STATS["gn_points"] += len(points)
    while len(points) < count:
        STATS["fallbacks"] += 1
        points.append(Vector((rng.uniform(-0.48, 0.48) * aspect, rng.uniform(-0.48, 0.48), 0.0)))
    rng.shuffle(points)
    chosen = [points[0]]
    while len(chosen) < count:
        chosen.append(max(points, key=lambda p: min((p - c).length for c in chosen)))
    return chosen


def wall_cells(aspect, count, rng):
    """Prisms through the thickness of a unit cube, cut around seeds on a
    face `aspect` wide; returns (bmesh, links) per cell, links being
    (other cell, shared face area, normal x, normal y) in unit space."""
    seeds = wall_seeds(aspect, count, rng)
    stretch = (aspect, 1.0, 1.0)
    cells = []
    for i, s in enumerate(seeds):
        bm = unit_cube(stretch)
        for j, t in enumerate(seeds):
            if i != j:
                cut(bm, (s + t) * 0.5, (t - s).normalized())
        if len(bm.faces) < 4 or bm.calc_volume() < 1e-6:
            bm.free()
            continue
        # Which face lies on which bisector: that cell is a neighbour.
        faces = []
        for f in bm.faces:
            if f.material_index != 1:
                continue
            c = f.calc_center_median()
            for j, t in enumerate(seeds):
                if j == i:
                    continue
                n = (t - s).normalized()
                if abs((c - (s + t) * 0.5).dot(n)) < 1e-4 and f.normal.dot(n) > 0.99:
                    faces.append((j, f))
                    break
        for v in bm.verts:
            v.co.x /= aspect
        bm.normal_update()
        links = []
        for j, f in faces:
            n = f.normal
            links.append((j, f.calc_area(), n.x, n.y))
        cells.append((i, bm, links))
    # Seed index -> cell index (a seed whose cell vanished has none).
    index = {seed: k for k, (seed, _, _) in enumerate(cells)}
    out = []
    for seed, bm, links in cells:
        kept = [(index[j], a, nx, ny) for j, a, nx, ny in links if j in index and a > 1e-5]
        out.append((bm, kept))
    return out


def square_param(x, y):
    """Where (x, y) on the unit square's border lies along it, 0..1, going
    round counter-clockwise from the corner (0.5, -0.5)."""
    if abs(x - 0.5) < 1e-6:
        return (y + 0.5) * 0.25
    if abs(y - 0.5) < 1e-6:
        return 0.25 + (0.5 - x) * 0.25
    if abs(x + 0.5) < 1e-6:
        return 0.5 + (0.5 - y) * 0.25
    return 0.75 + (x + 0.5) * 0.25


def sample_prism(bm, layout):
    """Samples a wall cell (a prism through z) onto the shared layout
    exactly: the layout's front and back faces map onto the cell's polygon
    (radially from its centre, corners on layout points), its sides onto
    the cell's sides. Flat faces, sharp corners: a standing cell looks like
    the wall it is part of. Sides on the cube's border are outer surface."""
    bm.normal_update()
    front = max(bm.faces, key=lambda f: f.normal.z)
    poly = [Vector((v.co.x, v.co.y)) for v in front.verts]
    # Counter-clockwise, starting at the vertex nearest the -45 degree ray.
    c = sum(poly, Vector((0.0, 0.0))) / len(poly)
    area2 = sum(poly[k].x * poly[(k + 1) % len(poly)].y - poly[(k + 1) % len(poly)].x * poly[k].y for k in range(len(poly)))
    if area2 < 0:
        poly.reverse()
    start = min(range(len(poly)), key=lambda k: abs(math.atan2(poly[k].y - c.y, poly[k].x - c.x) + math.pi / 4))
    poly = poly[start:] + poly[:start]
    n = len(poly)
    lengths = [(poly[(k + 1) % n] - poly[k]).length for k in range(n)]
    total = sum(lengths)
    # Snap each polygon corner to a perimeter sample of the layout (4*GRID).
    steps = 4 * GRID
    marks = []
    acc = 0.0
    for k in range(n):
        marks.append(min(steps - 1, max(marks[-1] + 1 if marks else 0, round(acc / total * steps))))
        acc += lengths[k]
    def border(t):
        """Point of the polygon's border for square parameter t (0..1)."""
        t = (t % 1.0) * steps
        for k in range(n):
            a = marks[k]
            b = marks[k + 1] if k + 1 < n else steps
            if a <= t <= b:
                f = (t - a) / max(b - a, 1e-6)
                return poly[k].lerp(poly[(k + 1) % n], f), k
        return poly[0], 0
    on_edge = []
    for k in range(n):
        p, q = poly[k], poly[(k + 1) % n]
        on_edge.append(any(abs(p[a] - side) < 1e-4 and abs(q[a] - side) < 1e-4 for a in (0, 1) for side in (-0.5, 0.5)))
    out = []
    for p in layout:
        r = 2.0 * max(abs(p.x), abs(p.y))
        if r < 1e-6:
            xy = c
            k = 0
        else:
            q = Vector((p.x, p.y)) / r
            point, k = border(square_param(q.x, q.y))
            xy = c.lerp(point, min(r, 1.0))
        face = abs(abs(p.z) - 0.5) < 1e-6 and r < 1.0 - 1e-6
        outer = 1.0 if (face or abs(abs(p.z) - 0.5) < 1e-6 or on_edge[k]) else 0.0
        out.append((Vector((xy.x, xy.y, p.z)), outer))
    lo = Vector((min(v.x for v in poly), min(v.y for v in poly), -0.5))
    hi = Vector((max(v.x for v in poly), max(v.y for v in poly), 0.5))
    mid = (lo + hi) * 0.5
    corners = [Vector((v.x, v.y, z)) - mid for v in poly for z in (-0.5, 0.5)]
    return {
        "verts": [(loc - mid, outer) for loc, outer in out],
        "center": [round(x, 4) for x in mid],
        "size": [round(x, 4) for x in hi - lo],
        "hull": [round(x, 4) for v in farthest_points(corners, MAX_HULL) for x in v],
        "volume": round(abs(area2) * 0.5, 6),
    }


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


def sample(bm, layout, kind, seed, first_seed=None):
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
            # A sub-shard keeps its parent's roughness on the parent's own
            # fracture faces, so nothing jumps when the parent splits.
            face_seed = first_seed if (mats[idx] == 1 and first_seed is not None) else seed
            depth = (loc - centre).length
            loc = loc - d * min(ROUGH[kind] * rough(kind, loc, face_seed), depth * 0.35)
        out.append((loc, outer))
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
    mid = (lo + hi) * 0.5
    verts = [((loc - mid), outer) for loc, outer in out]
    hull = farthest_points([v.co - mid for v in bm.verts], MAX_HULL)
    return {
        "verts": verts,
        "center": [round(c, 4) for c in mid],
        "size": [round(c, 4) for c in hi - lo],
        "hull": [round(c, 4) for v in hull for c in v],
        "volume": round(bm.calc_volume(), 6),
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
                    first_seed = rng.random()
                    s = sample(bm, layout, kind, first_seed)
                    s["id"] = len(rows)
                    rows.append(s.pop("verts"))
                    explode = Vector(s["center"]) * 0.35
                    at = Vector((col * 1.8, row_y, 0)) + explode
                    if kind in CASCADE:
                        s["children"] = []
                        for c, part in enumerate(split_cell(bm, child_count(s["volume"]), rng, STRETCH[kind])):
                            child = sample(part, layout, kind, rng.random(), first_seed)
                            child["id"] = len(rows)
                            rows.append(child.pop("verts"))
                            s["children"].append(child)
                            spread = (Vector(child["center"]) - Vector(s["center"])) * 0.25
                            add_preview(part, "%s_%d_%d_%d" % (kind, col, k, c), at + spread, kind)
                            part.free()
                    else:
                        add_preview(bm, "%s_%d_%d" % (kind, col, k), at, kind)
                    pattern["shards"].append(s)
                    bm.free()
                library[kind].append(pattern)
                col += 1
                print("%s: pattern %d with %d pieces" % (kind, col, pattern["count"]))
    walls = []
    for a_k, aspect in enumerate(WALL_ASPECTS):
        for c_k, count in enumerate(WALL_COUNTS):
            pattern = {"aspect": aspect, "count": count, "shards": []}
            for k, (bm, links) in enumerate(wall_cells(aspect, count, rng)):
                s = sample_prism(bm, layout)
                s["id"] = len(rows)
                rows.append(s.pop("verts"))
                s["links"] = [[j, round(area, 5), round(nx, 4), round(ny, 4)] for j, area, nx, ny in links]
                pattern["shards"].append(s)
                at = Vector((c_k * 1.8, -3.0 - a_k * 2.0, 0)) + Vector(s["center"]) * 1.15
                add_preview(bm, "wall_%d_%d_%d" % (a_k, c_k, k), at, "wall")
                bm.free()
            walls.append(pattern)
            print("wall: aspect %.1f, %d cells" % (aspect, len(pattern["shards"])))
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
                "walls": walls,
            },
            f,
            separators=(",", ":"),
        )
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB")
    print("%d shards, %d vertices each -> %s" % (len(rows), len(layout), OUT_JSON))
    print("Geometry Nodes seeds: %d candidates, %d fallbacks" % (STATS["gn_points"], STATS["fallbacks"]))


if __name__ == "__main__":
    main()
