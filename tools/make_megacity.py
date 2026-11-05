#!/usr/bin/env python3
"""Builds the megacity kit in Blender: the colossal, non-destructible city
that rises around the playable district (imperial antiquity rebuilt by a
far future: temple towers, giant statues, chimneys, viaducts).

Run:  python3 tools/make_megacity.py     (pip install bpy)
Writes assets/megacity/kit.glb: one mesh per piece, at real scale (metres),
with four materials the game replaces by its own: marble, bronze, steel,
amber (lit openings).

Stylised and clean: few, readable shapes with chamfered edges, no
textures; the shader and the haze do the rest.
"""
import math
import os

import bpy  # first: it makes bmesh and mathutils importable
import bmesh
from mathutils import Matrix, Vector

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "megacity", "kit.glb")
MATS = ["marble", "bronze", "steel", "amber", "cloth"]
MARBLE, BRONZE, STEEL, AMBER, CLOTH = range(5)


def materials():
    out = []
    colors = [(0.92, 0.88, 0.8, 1), (0.76, 0.55, 0.28, 1), (0.12, 0.12, 0.14, 1), (1.0, 0.7, 0.35, 1), (0.5, 0.08, 0.08, 1)]
    for name, c in zip(MATS, colors):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.diffuse_color = c
        out.append(m)
    return out


class Piece:
    """A bmesh being built, with a material per face."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()

    def _tag(self, verts, mat):
        faces = set()
        for v in verts:
            faces.update(v.link_faces)
        for f in faces:
            f.material_index = mat

    def cyl(self, r1, r2, h, segs, at=(0, 0, 0), mat=MARBLE, rot=None):
        """Frustum standing on `at` (z up in Blender)."""
        m = Matrix.Translation(Vector(at) + Vector((0, 0, h / 2)))
        if rot is not None:
            m = Matrix.Translation(Vector(at)) @ rot @ Matrix.Translation((0, 0, h / 2))
        r = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h, matrix=m
        )
        self._tag(r["verts"], mat)
        return r["verts"]

    def box(self, size, at, mat=MARBLE, rot=None):
        m = Matrix.Translation(Vector(at))
        if rot is not None:
            m = m @ rot
        m = m @ Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0)))
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._tag(r["verts"], mat)
        return r["verts"]

    def sphere(self, r, at, mat=MARBLE, segs=16, rings=8, squash=1.0):
        m = Matrix.Translation(Vector(at)) @ Matrix.Diagonal(Vector((r, r, r * squash, 1.0)))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=1.0, matrix=m)
        self._tag(res["verts"], mat)
        return res["verts"]

    def build(self, mats):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in mats:
            me.materials.append(m)
        for p in me.polygons:
            p.use_smooth = False
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


# --- Pieces --------------------------------------------------------------------


def column(p, at, h, r, mat=MARBLE, capital=BRONZE):
    """A colossal column: stepped base, shaft (12 flat flutes), capital."""
    x, y, z = at
    p.cyl(r * 1.35, r * 1.35, h * 0.03, 12, (x, y, z), mat)
    p.cyl(r * 1.15, r * 1.05, h * 0.03, 12, (x, y, z + h * 0.03), mat)
    p.cyl(r, r * 0.88, h * 0.86, 12, (x, y, z + h * 0.06), mat)
    p.cyl(r * 0.9, r * 1.3, h * 0.05, 12, (x, y, z + h * 0.92), capital)
    p.box((r * 2.7, r * 2.7, h * 0.03), (x, y, z + h * 0.985), mat)


def ring_tier(name, radius, height, columns, core_mat=MARBLE):
    """One tier of a temple tower: a core drum with lit slit windows, a
    peristyle of colossal columns, an entablature and a stepped floor."""
    p = Piece(name)
    # Stylobate: three steps.
    for k in range(3):
        p.cyl(radius + 2.6 - k * 0.8, radius + 2.6 - k * 0.8, 0.7, 32, (0, 0, k * 0.7), MARBLE)
    base = 2.1
    core = radius * 0.72
    p.cyl(core, core, height, 24, (0, 0, base), core_mat)
    # Windows: tall amber slits round the core.
    for i in range(12):
        a = i / 12 * math.tau
        rot = Matrix.Rotation(a, 4, "Z")
        p.box((0.6, 1.4, height * 0.55), (math.cos(a) * core, math.sin(a) * core, base + height * 0.45), AMBER, rot)
    # Bronze bands where the tier was "printed" in layers.
    for k in range(1, 4):
        p.cyl(core + 0.15, core + 0.15, 0.35, 24, (0, 0, base + height * k / 4), BRONZE)
    for i in range(columns):
        a = i / columns * math.tau
        column(p, (math.cos(a) * radius, math.sin(a) * radius, base), height, radius * 0.06)
    # Entablature: architrave, bronze frieze, cornice.
    top = base + height
    p.cyl(radius + 1.2, radius + 1.2, 1.4, 32, (0, 0, top), MARBLE)
    p.cyl(radius + 1.25, radius + 1.25, 0.9, 32, (0, 0, top + 1.4), BRONZE)
    p.cyl(radius + 1.9, radius + 1.9, 0.8, 32, (0, 0, top + 2.3), MARBLE)
    p.cyl(radius + 0.4, radius * 0.75, 1.0, 32, (0, 0, top + 3.1), MARBLE)
    return p


def dome(name):
    """Unit dome (radius 1): ribbed bronze-and-marble dome, a lantern, a
    spike."""
    p = Piece(name)
    p.cyl(1.02, 1.02, 0.12, 32, (0, 0, 0), MARBLE)
    verts = p.sphere(1.0, (0, 0, 0.12), MARBLE, 32, 16, 1.0)
    # Keep the upper half only.
    p.bm.verts.ensure_lookup_table()
    low = [v for v in verts if v.co.z < 0.1]
    bmesh.ops.delete(p.bm, geom=low, context="VERTS")
    for i in range(16):
        a = i / 16 * math.tau
        for k in range(8):
            phi = (k + 0.5) / 8 * math.pi / 2
            at = (math.cos(a) * math.cos(phi) * 1.0, math.sin(a) * math.cos(phi) * 1.0, 0.12 + math.sin(phi))
            rot = Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(-phi, 4, "Y")
            p.box((0.04, 0.05, 0.21), at, BRONZE, rot)
    p.cyl(0.16, 0.16, 0.3, 12, (0, 0, 1.08), MARBLE)
    p.cyl(0.2, 0.0, 0.25, 12, (0, 0, 1.38), BRONZE)
    p.cyl(0.03, 0.0, 0.6, 6, (0, 0, 1.6), BRONZE)
    return p


def spire(name):
    """Unit spire (base radius 1, height ~5): stepped steel and bronze."""
    p = Piece(name)
    z = 0.0
    r = 1.0
    for k in range(6):
        h = 0.55 - k * 0.04
        p.cyl(r, r * 0.92, h, 16, (0, 0, z), STEEL if k % 2 == 0 else MARBLE)
        p.cyl(r * 0.96, r * 0.96, 0.06, 16, (0, 0, z + h), BRONZE)
        z += h + 0.06
        r *= 0.8
    p.cyl(r, 0.0, 2.2, 8, (0, 0, z), BRONZE)
    # Four buttress fins at the base.
    for i in range(4):
        a = i / 4 * math.tau + math.pi / 4
        rot = Matrix.Rotation(a, 4, "Z")
        p.box((1.6, 0.12, 1.4), (math.cos(a) * 0.95, math.sin(a) * 0.95, 0.7), STEEL, rot)
    return p


def statue(name):
    """A colossal guardian, ~32 m, stylised: plinth, long robe, cloak, a
    crested helm, one arm holding a spear upright, the other a shield."""
    p = Piece(name)
    p.box((9, 9, 3), (0, 0, 1.5), MARBLE)
    p.box((7.6, 7.6, 1.0), (0, 0, 3.5), BRONZE)
    z = 4.0
    p.cyl(3.6, 2.2, 13.0, 10, (0, 0, z), MARBLE)  # robe
    p.cyl(2.3, 2.9, 5.0, 10, (0, 0, z + 13.0), MARBLE)  # chest
    p.box((7.2, 2.6, 1.6), (0, 0, z + 18.4), BRONZE)  # pauldrons
    p.cyl(0.9, 0.9, 1.2, 10, (0, 0, z + 18.8), MARBLE)  # neck
    p.sphere(1.6, (0, 0, z + 21.4), BRONZE, 12, 8, 1.15)  # helm
    p.box((0.35, 3.6, 2.6), (0, -0.2, z + 23.2), BRONZE)  # crest
    p.box((2.0, 0.6, 0.5), (0, 1.45, z + 21.0), STEEL)  # visor
    # Cloak down the back.
    p.box((5.6, 0.6, 16.0), (0, -2.3, z + 9.5), BRONZE, Matrix.Rotation(-0.08, 4, "X"))
    # Right arm holds the spear upright.
    p.cyl(0.8, 0.7, 7.0, 8, (3.6, 0.6, z + 11.5), MARBLE)
    p.cyl(0.25, 0.25, 30.0, 6, (4.1, 1.4, 4.0), STEEL)
    p.cyl(0.7, 0.0, 3.2, 4, (4.1, 1.4, 34.0), BRONZE)
    # Left arm and a round shield.
    p.cyl(0.8, 0.7, 7.0, 8, (-3.6, 0.6, z + 11.5), MARBLE)
    p.cyl(3.4, 3.4, 0.6, 16, (-4.6, 1.2, z + 10.0), BRONZE, Matrix.Rotation(math.pi / 2, 4, "Y"))
    return p


def chimney(name):
    """A temple-factory stack: fluted drum, bronze bands, a flared crown
    (the smoke comes from the game)."""
    p = Piece(name)
    p.cyl(5.5, 5.5, 4.0, 16, (0, 0, 0), MARBLE)
    p.cyl(3.6, 2.8, 56.0, 16, (0, 0, 4.0), STEEL)
    for k in range(5):
        p.cyl(3.7 - k * 0.15, 3.7 - k * 0.15, 0.9, 16, (0, 0, 10.0 + k * 11.0), BRONZE)
    p.cyl(2.8, 3.8, 3.0, 16, (0, 0, 60.0), BRONZE)
    p.cyl(3.4, 3.4, 0.6, 16, (0, 0, 63.0), AMBER)
    return p


def viaduct(name):
    """30 m of aqueduct-viaduct: two piers, a round arch, a deck with a
    parapet and a bundle of pipes along the side (the factory)."""
    p = Piece(name)
    L, H, W = 30.0, 22.0, 9.0
    for sx in (-1, 1):
        p.box((4.0, W, H), (sx * (L / 2 - 2.0), 0, H / 2), MARBLE)
        p.box((5.0, W + 1.0, 1.2), (sx * (L / 2 - 2.0), 0, H - 0.6), BRONZE)
    # The arch: voussoirs between the piers.
    r = L / 2 - 4.0
    n = 15
    for k in range(n):
        a = math.pi * (k + 0.5) / n
        at = (math.cos(a) * (r + 1.2), 0, H - r * 0.35 + math.sin(a) * (r + 1.2) * 0.35 + 0.0)
        rot = Matrix.Rotation(-a + math.pi / 2, 4, "Y")
        p.box((2.4, W, math.pi * (r + 1.2) / n * 0.75), at, MARBLE, rot)
    p.box((L, W, 2.0), (0, 0, H + 1.0), MARBLE)
    for sy in (-1, 1):
        p.box((L, 0.6, 1.4), (0, sy * (W / 2 - 0.3), H + 2.7), MARBLE)
    for k in range(3):
        p.cyl(0.55, 0.55, L, 10, (-L / 2, W / 2 + 0.7 + k * 1.2, H - 2.0 - k * 0.4), STEEL, Matrix.Rotation(math.pi / 2, 4, "Y"))
    return p


def temple_front(name):
    """A hexastyle temple front, 30 m wide: steps, six columns, an
    entablature and a pediment with a bronze disc."""
    p = Piece(name)
    W, H = 30.0, 22.0
    for k in range(3):
        p.box((W + 4 - k * 1.2, 10 - k * 1.2, 0.8), (0, 0, 0.4 + k * 0.8), MARBLE)
    for i in range(6):
        x = -W / 2 + 2.5 + i * (W - 5) / 5
        column(p, (x, 2.0, 2.4), H, 1.25)
    p.box((W + 1, 6, 1.8), (0, 1.5, 2.4 + H + 0.9), MARBLE)
    p.box((W + 1.2, 6.2, 0.9), (0, 1.5, 2.4 + H + 2.25), BRONZE)
    # Pediment: a flat triangular prism.
    bm = p.bm
    top = 2.4 + H + 2.7
    pts = [(-W / 2 - 1, top), (W / 2 + 1, top), (0, top + 7.0)]
    vs = []
    for y in (-1.5, 4.5):
        vs.append([bm.verts.new((x, y, z)) for x, z in pts])
    faces = [vs[0], vs[1][::-1]]
    for i in range(3):
        j = (i + 1) % 3
        faces.append([vs[0][i], vs[0][j], vs[1][j], vs[1][i]])
    for f in faces:
        face = bm.faces.new(f)
        face.material_index = MARBLE
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    p.cyl(2.4, 2.4, 0.5, 20, (0, 4.6, top + 2.6), BRONZE, Matrix.Rotation(math.pi / 2, 4, "X"))
    return p


def insula(name, storeys, bays=4):
    """A city block of the lower city, 12 m deep, `bays` x 4.5 m wide:
    an arcade on the ground floor, pilasters between rows of windows (some
    lit), a cornice and a bronze-trimmed roof terrace. Facade faces -y."""
    p = Piece(name)
    W = bays * 4.5
    D = 12.0
    H = 6.0 + storeys * 4.2
    p.box((W, D, H), (0, 0, H / 2), MARBLE)
    # Ground-floor arcade: piers and arch heads in relief, dark openings.
    for b in range(bays):
        x = -W / 2 + 2.25 + b * 4.5
        p.box((3.0, 0.4, 4.2), (x, -D / 2 - 0.05, 2.1), STEEL)
        for k in range(7):
            a = math.pi * (k + 0.5) / 7
            at = (x + math.cos(a) * 1.75, -D / 2 - 0.2, 4.2 + math.sin(a) * 1.4)
            p.box((0.5, 0.5, 0.75), at, MARBLE, Matrix.Rotation(-a + math.pi / 2, 4, "Y"))
    p.box((W + 0.4, 0.8, 0.6), (0, -D / 2 - 0.3, 6.0), BRONZE)
    # Upper storeys: windows between pilasters.
    for s in range(storeys):
        z = 6.0 + s * 4.2
        for b in range(bays):
            x = -W / 2 + 2.25 + b * 4.5
            lit = (b * 7 + s * 3 + storeys) % 5 == 0
            p.box((1.4, 0.3, 2.4), (x, -D / 2 - 0.05, z + 1.9), AMBER if lit else STEEL)
        for b in range(bays + 1):
            x = -W / 2 + b * 4.5
            p.box((0.6, 0.5, 4.2), (x, -D / 2 - 0.15, z + 2.1), MARBLE)
    p.box((W + 1.2, D + 1.2, 0.9), (0, 0, H + 0.45), MARBLE)
    p.box((W + 1.3, D + 1.3, 0.35), (0, 0, H - 0.2), BRONZE)
    p.box((W - 2.0, D - 2.0, 1.2), (0, 0, H + 1.5), MARBLE)
    return p


# --- Street props (district scale) -------------------------------------------


def brazier(name):
    """A bronze fire bowl on a fluted marble stand, ~2 m."""
    p = Piece(name)
    p.cyl(0.55, 0.55, 0.25, 12, (0, 0, 0), MARBLE)
    p.cyl(0.22, 0.18, 1.2, 12, (0, 0, 0.25), MARBLE)
    p.cyl(0.3, 0.75, 0.45, 16, (0, 0, 1.45), BRONZE)
    p.cyl(0.66, 0.66, 0.08, 16, (0, 0, 1.86), AMBER)
    return p


def lamppost(name):
    """A tall bronze lamp: a column with an amber lantern, ~6 m."""
    p = Piece(name)
    p.box((0.7, 0.7, 0.5), (0, 0, 0.25), MARBLE)
    p.cyl(0.12, 0.09, 5.0, 8, (0, 0, 0.5), BRONZE)
    p.box((1.2, 0.08, 0.08), (0, 0, 5.3), BRONZE)
    for sx in (-1, 1):
        p.cyl(0.2, 0.2, 0.5, 8, (sx * 0.55, 0, 4.85), AMBER)
        p.cyl(0.24, 0.0, 0.25, 8, (sx * 0.55, 0, 5.35), BRONZE)
    return p


def standard(name):
    """A war standard: a tall steel pole, a crossbar, a long crimson
    banner with a bronze border and a bronze disc, ~9 m."""
    p = Piece(name)
    p.box((1.0, 1.0, 0.6), (0, 0, 0.3), MARBLE)
    p.cyl(0.09, 0.07, 9.0, 8, (0, 0, 0.6), STEEL)
    p.cyl(0.25, 0.0, 0.6, 6, (0, 0, 9.6), BRONZE)
    p.box((2.4, 0.1, 0.1), (0, 0, 8.6), BRONZE)
    p.box((2.0, 0.04, 4.6), (0, 0.06, 6.2), CLOTH)
    p.box((2.1, 0.03, 0.18), (0, 0.08, 3.95), BRONZE)
    p.cyl(0.45, 0.45, 0.05, 16, (0, 0.1, 6.6), BRONZE, Matrix.Rotation(math.pi / 2, 4, "X"))
    return p


def plinth_statue(name):
    """A guardian on a plinth, ~6 m: the colossus, small."""
    p = statue(name)
    bmesh.ops.scale(p.bm, vec=(0.17, 0.17, 0.17), verts=p.bm.verts[:])
    return p


def pipes(name):
    """A run of three pipes on brackets along a wall, 8 m."""
    p = Piece(name)
    for k in range(3):
        p.cyl(0.18, 0.18, 8.0, 10, (-4.0, 0.0, 0.5 + k * 0.45), STEEL, Matrix.Rotation(math.pi / 2, 4, "Y"))
    for x in (-3.0, 0.0, 3.0):
        p.box((0.15, 0.5, 1.6), (x, 0.0, 0.85), BRONZE)
        p.cyl(0.24, 0.24, 0.25, 10, (x - 0.12, 0.0, 0.95), BRONZE, Matrix.Rotation(math.pi / 2, 4, "Y"))
    return p


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = materials()
    pieces = [
        ring_tier("tier_xl", 16.0, 18.0, 20),
        ring_tier("tier_l", 12.0, 16.0, 16),
        ring_tier("tier_m", 8.5, 14.0, 12),
        ring_tier("tier_s", 5.5, 12.0, 10, STEEL),
        dome("dome"),
        spire("spire"),
        statue("statue"),
        chimney("chimney"),
        viaduct("viaduct"),
        temple_front("temple_front"),
        insula("insula_low", 2),
        insula("insula_mid", 4),
        insula("insula_high", 6, 3),
        brazier("brazier"),
        lamppost("lamppost"),
        standard("standard"),
        plinth_statue("plinth_statue"),
        pipes("pipes"),
    ]
    for p in pieces:
        bm = p.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        ob = p.build(mats)
        # Godot is y-up: rotate z-up modelling into it on export.
        print(ob.name, len(ob.data.polygons), "faces")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(OUT), export_format="GLB", export_yup=True, export_apply=True)
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
