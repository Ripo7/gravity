"""Bakes the palace's surface textures in Blender (Cycles, CPU).

Run with Blender's Python module (pip install bpy), from the project root:

    python3 tools/make_textures.py

Every finish is a procedural Blender material built here from nodes (brick
and Voronoi patterns, 4D noise, a bump for the relief), baked onto a plane
into seamless tiles: the noise is sampled on a 4D torus (two circles, one
per texture axis) and the brick patterns fit a whole number of stones, so
the tiles repeat without a seam. No photos, no outside images.

Outputs, one layer per finish stacked vertically (Godot imports them as
Texture2DArray, see the .import files next to them):
  assets/textures/finish_albedo.png   colour (linear)
  assets/textures/finish_detail.png   normal x, normal y (tangent space),
                                      roughness, cavity (0 = deep joint);
                                      half the resolution
Layer order and tile sizes in metres must match shaders/block.gdshader.
"""

import math
import os

import bpy  # first: it makes the other Blender modules importable
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")
SIZE = 512
DETAIL_SIZE = 256  # relief, roughness and joints need less (and weigh 4 bytes a texel)
TAU = 2.0 * math.pi

# name, tile size in metres (u, v): keep in step with block.gdshader.
LAYERS = [
    ("stone", (3.12, 2.52)),  # ashlar: 4 x 6 stones of 0.78 x 0.42
    ("brick", (1.84, 2.4)),  # running bond: 8 x 32 bricks of 0.23 x 0.075
    ("plaster", (4.0, 4.0)),  # neutral render, tinted per finish
    ("travertine", (2.0, 2.0)),
    ("marble", (3.0, 3.0)),
    ("terracotta", (2.2, 2.0)),  # roof tiles: 10 x 10 of 0.22 x 0.2
]


class Graph:
    """Small helper to build a material's node tree."""

    def __init__(self, name):
        self.mat = bpy.data.materials.new(name)
        self.mat.use_nodes = True
        self.nodes = self.mat.node_tree.nodes
        self.links = self.mat.node_tree.links
        self.nodes.clear()
        self.out = self.node("ShaderNodeOutputMaterial")
        self.bsdf = self.node("ShaderNodeBsdfPrincipled")
        self.link(self.bsdf.outputs["BSDF"], self.out.inputs["Surface"])
        uv = self.node("ShaderNodeTexCoord").outputs["UV"]
        self.uv = uv
        # The torus: (cos u, sin u, cos v) and w = sin v, all periodic in u, v.
        sep = self.node("ShaderNodeSeparateXYZ")
        self.link(uv, sep.inputs["Vector"])
        self.u = sep.outputs["X"]
        self.v = sep.outputs["Y"]

    def node(self, kind, **props):
        n = self.nodes.new(kind)
        for k, val in props.items():
            setattr(n, k, val)
        return n

    def link(self, a, b):
        self.links.new(a, b)

    def math(self, op, a, b=None, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self._feed(n.inputs[0], a)
        if b is not None:
            self._feed(n.inputs[1], b)
        return n.outputs[0]

    def _feed(self, sock, val):
        if isinstance(val, (int, float)):
            sock.default_value = val
        else:
            self.link(val, sock)

    def torus(self, radius_u, radius_v):
        """4D point on two circles: radius = tile size / 2 pi in metres, so
        noise scale stays in metres."""
        cu = self.math("COSINE", self.math("MULTIPLY", self.u, TAU))
        su = self.math("SINE", self.math("MULTIPLY", self.u, TAU))
        cv = self.math("COSINE", self.math("MULTIPLY", self.v, TAU))
        sv = self.math("SINE", self.math("MULTIPLY", self.v, TAU))
        xyz = self.node("ShaderNodeCombineXYZ")
        self.link(self.math("MULTIPLY", cu, radius_u), xyz.inputs["X"])
        self.link(self.math("MULTIPLY", su, radius_u), xyz.inputs["Y"])
        self.link(self.math("MULTIPLY", cv, radius_v), xyz.inputs["Z"])
        return xyz.outputs["Vector"], self.math("MULTIPLY", sv, radius_v)

    def noise(self, vec, w, scale, detail=4.0, rough=0.55):
        n = self.node("ShaderNodeTexNoise", noise_dimensions="4D")
        self.link(vec, n.inputs["Vector"])
        self.link(w, n.inputs["W"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        return n.outputs["Fac"]

    def voronoi(self, vec, w, scale, feature="F1", out="Distance"):
        n = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature=feature)
        self.link(vec, n.inputs["Vector"])
        self.link(w, n.inputs["W"])
        n.inputs["Scale"].default_value = scale
        return n.outputs[out]

    def brick(self, cols, rows, mortar, smooth=0.1, offset=0.5):
        n = self.node("ShaderNodeTexBrick", offset=offset, offset_frequency=2)
        self.link(self.uv, n.inputs["Vector"])
        n.inputs["Scale"].default_value = 1.0
        n.inputs["Brick Width"].default_value = 1.0 / cols
        n.inputs["Row Height"].default_value = 1.0 / rows
        n.inputs["Mortar Size"].default_value = mortar
        n.inputs["Mortar Smooth"].default_value = smooth
        n.inputs["Color1"].default_value = (0.0, 0.0, 0.0, 1.0)
        n.inputs["Color2"].default_value = (1.0, 1.0, 1.0, 1.0)
        n.inputs["Mortar"].default_value = (0.0, 0.0, 0.0, 1.0)
        n.inputs["Bias"].default_value = 0.0
        # Color: a random grey per brick (0..1); Fac: 1 in the mortar.
        return n.outputs["Color"], n.outputs["Fac"]

    def ramp(self, fac, stops):
        n = self.node("ShaderNodeValToRGB")
        self.link(fac, n.inputs["Fac"])
        els = n.color_ramp.elements
        while len(els) > 1:
            els.remove(els[-1])
        els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1.0)
        for pos, col in stops[1:]:
            e = els.new(pos)
            e.color = (*col, 1.0)
        return n.outputs["Color"]

    def mix(self, fac, a, b):
        """Colour a where fac is 0, b where it is 1 (an RGB tuple or a socket)."""
        n = self.node("ShaderNodeMix", data_type="RGBA")
        self._feed(n.inputs[0], fac)
        for sock, val in ((n.inputs[6], a), (n.inputs[7], b)):
            if isinstance(val, tuple):
                sock.default_value = (*val, 1.0)
            else:
                self.link(val, sock)
        return n.outputs[2]

    def scale(self, color, factor):
        """Colour times a grey factor (a float socket)."""
        gray = self.node("ShaderNodeCombineColor")
        for k in ("Red", "Green", "Blue"):
            self._feed(gray.inputs[k], factor)
        n = self.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        n.inputs[0].default_value = 1.0
        self.link(color, n.inputs[6])
        self.link(gray.outputs["Color"], n.inputs[7])
        return n.outputs[2]

    def finish(self, color, rough, height, strength):
        """Wires colour, roughness and a height field (bump) to the BSDF."""
        self.link(color, self.bsdf.inputs["Base Color"])
        self._feed(self.bsdf.inputs["Roughness"], rough)
        bump = self.node("ShaderNodeBump")
        bump.inputs["Strength"].default_value = strength
        bump.inputs["Distance"].default_value = 0.02
        self.link(height, bump.inputs["Height"])
        self.link(bump.outputs["Normal"], self.bsdf.inputs["Normal"])
        self.height = height
        return self


# --- The finishes --------------------------------------------------------------------


def stone(size):
    g = Graph("stone")
    vec, w = g.torus(size[0] / TAU, size[1] / TAU)
    tone, mortar = g.brick(4, 6, 0.011, 0.3, 0.5)
    grain = g.noise(vec, w, 2.2, 6.0, 0.6)
    pits = g.voronoi(vec, w, 9.0)
    base = g.ramp(grain, [(0.25, (0.55, 0.5, 0.42)), (0.7, (0.74, 0.68, 0.58))])
    stones = g.scale(base, g.math("ADD", g.math("MULTIPLY", tone, 0.28), 0.82))
    col = g.mix(mortar, stones, (0.33, 0.3, 0.27))
    # Rusticated: each stone bulges, chisel pits, deep joints.
    face = g.math("SUBTRACT", 1.0, mortar)
    height = g.math("ADD", g.math("MULTIPLY", face, 0.8), g.math("MULTIPLY", grain, 0.25))
    height = g.math("SUBTRACT", height, g.math("MULTIPLY", g.math("LESS_THAN", pits, 0.08), 0.15))
    return g.finish(col, 0.93, height, 0.9)


def brick(size):
    g = Graph("brick")
    vec, w = g.torus(size[0] / TAU, size[1] / TAU)
    tone, mortar = g.brick(8, 32, 0.0032, 0.15, 0.5)
    grain = g.noise(vec, w, 18.0, 4.0, 0.6)
    clay = g.ramp(tone, [(0.0, (0.48, 0.22, 0.15)), (0.5, (0.62, 0.3, 0.2)), (1.0, (0.7, 0.4, 0.27))])
    burnt = g.mix(g.math("MULTIPLY", grain, 0.35), clay, (0.3, 0.15, 0.1))
    col = g.mix(mortar, burnt, (0.74, 0.7, 0.63))
    height = g.math("ADD", g.math("MULTIPLY", g.math("SUBTRACT", 1.0, mortar), 0.7), g.math("MULTIPLY", grain, 0.2))
    return g.finish(col, 0.9, height, 0.7)


def plaster(size):
    g = Graph("plaster")
    vec, w = g.torus(size[0] / TAU, size[1] / TAU)
    mottle = g.noise(vec, w, 0.9, 5.0, 0.6)
    fine = g.noise(vec, w, 14.0, 3.0, 0.7)
    stains = g.noise(vec, w, 0.35, 3.0, 0.5)
    # Neutral light render: the shader tints it ochre, rose, sienna, cream.
    base = g.ramp(mottle, [(0.3, (0.8, 0.8, 0.8)), (0.7, (0.95, 0.95, 0.95))])
    col = g.mix(g.math("MULTIPLY", g.math("GREATER_THAN", stains, 0.62), 0.25), base, (0.62, 0.6, 0.58))
    height = g.math("ADD", g.math("MULTIPLY", fine, 0.6), g.math("MULTIPLY", mottle, 0.4))
    return g.finish(col, 0.88, height, 0.25)


def travertine(size):
    g = Graph("travertine")
    vec, w = g.torus(size[0] / TAU, size[1] / TAU)
    # Strata: noise stretched along u (horizontal bands).
    stretched = g.node("ShaderNodeVectorMath", operation="MULTIPLY")
    g.link(vec, stretched.inputs[0])
    stretched.inputs[1].default_value = (0.25, 0.25, 4.0)
    band = g.noise(stretched.outputs[0], w, 3.0, 5.0, 0.6)
    pores = g.voronoi(vec, w, 7.0)
    base = g.ramp(band, [(0.3, (0.8, 0.72, 0.58)), (0.7, (0.9, 0.84, 0.7))])
    hole = g.math("LESS_THAN", pores, 0.1)
    col = g.mix(g.math("MULTIPLY", hole, 0.6), base, (0.55, 0.48, 0.38))
    height = g.math("SUBTRACT", g.math("MULTIPLY", band, 0.3), g.math("MULTIPLY", hole, 0.6))
    return g.finish(col, 0.8, height, 0.5)


def marble(size):
    g = Graph("marble")
    vec, w = g.torus(size[0] / TAU, size[1] / TAU)
    warp = g.noise(vec, w, 0.8, 6.0, 0.6)
    vein_in = g.math("ADD", g.math("MULTIPLY", warp, 9.0), g.math("MULTIPLY", g.u, TAU * 2.0))
    vein = g.math("POWER", g.math("ABSOLUTE", g.math("SINE", vein_in)), 0.15)
    base = g.ramp(vein, [(0.55, (0.62, 0.62, 0.64)), (0.85, (0.93, 0.92, 0.89))])
    height = g.math("MULTIPLY", warp, 0.1)
    return g.finish(base, 0.32, height, 0.1)


def terracotta(size):
    g = Graph("terracotta")
    vec, w = g.torus(size[0] / TAU, size[1] / TAU)
    tone, lip = g.brick(10, 10, 0.012, 0.2, 0.5)
    grain = g.noise(vec, w, 12.0, 3.0, 0.6)
    clay = g.ramp(tone, [(0.0, (0.56, 0.27, 0.16)), (1.0, (0.78, 0.43, 0.26))])
    # Each tile is a half pipe: brighter along its crown.
    across = g.math("FRACT", g.math("MULTIPLY", g.u, 10.0))
    crown = g.math("SINE", g.math("MULTIPLY", across, math.pi))
    shaded = g.scale(clay, g.math("ADD", g.math("MULTIPLY", crown, 0.3), 0.75))
    col = g.mix(g.math("MULTIPLY", lip, 0.6), shaded, (0.3, 0.16, 0.1))
    height = g.math("ADD", g.math("MULTIPLY", crown, 0.8), g.math("MULTIPLY", grain, 0.15))
    height = g.math("SUBTRACT", height, g.math("MULTIPLY", lip, 0.5))
    return g.finish(col, 0.85, height, 1.0)


BUILDERS = {"stone": stone, "brick": brick, "plaster": plaster, "travertine": travertine,
            "marble": marble, "terracotta": terracotta}


# --- Baking ----------------------------------------------------------------------------


def bake(obj, graph, kind, image):
    """Bakes one pass of `graph` into `image` (float RGBA), returns pixels."""
    tree = graph.mat.node_tree
    target = tree.nodes.new("ShaderNodeTexImage")
    target.image = image
    tree.nodes.active = target
    scene = bpy.context.scene
    if kind == "HEIGHT":
        # Height as light: an emission shader shows the field itself.
        emit = tree.nodes.new("ShaderNodeEmission")
        tree.links.new(graph.height, emit.inputs["Color"])
        tree.links.new(emit.outputs["Emission"], graph.out.inputs["Surface"])
        bpy.ops.object.bake(type="EMIT")
        tree.links.new(graph.bsdf.outputs["BSDF"], graph.out.inputs["Surface"])
        tree.nodes.remove(emit)
    elif kind == "DIFFUSE":
        scene.render.bake.use_pass_direct = False
        scene.render.bake.use_pass_indirect = False
        scene.render.bake.use_pass_color = True
        bpy.ops.object.bake(type="DIFFUSE")
    else:
        bpy.ops.object.bake(type=kind)
    tree.nodes.remove(target)
    px = np.array(image.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)
    return px[::-1]  # Blender rows go bottom-up


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.render.bake.margin = 0
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    plane = bpy.context.active_object
    plane.select_set(True)
    albedo = []
    detail = []
    for name, size in LAYERS:
        graph = BUILDERS[name](size)
        plane.data.materials.clear()
        plane.data.materials.append(graph.mat)
        img = bpy.data.images.new(name, SIZE, SIZE, alpha=True, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        color = bake(plane, graph, "DIFFUSE", img)
        normal = bake(plane, graph, "NORMAL", img)
        rough = bake(plane, graph, "ROUGHNESS", img)
        height = bake(plane, graph, "HEIGHT", img)
        # Colour is stored linear, as baked (the shader reads it raw: arrays
        # get no sRGB decoding on every renderer).
        rgb = np.clip(color[..., :3], 0.0, 1.0)
        albedo.append(np.concatenate([rgb, np.ones((SIZE, SIZE, 1))], axis=2))
        h = height[..., 0]
        cavity = np.clip((h - h.min()) / max(h.max() - h.min(), 1e-6), 0.0, 1.0)
        d = np.stack([normal[..., 0], normal[..., 1], rough[..., 0], cavity], axis=2)
        k = SIZE // DETAIL_SIZE
        detail.append(d.reshape(DETAIL_SIZE, k, DETAIL_SIZE, k, 4).mean(axis=(1, 3)))
        print("baked", name)
    os.makedirs(OUT, exist_ok=True)
    for label, layers in (("finish_albedo", albedo), ("finish_detail", detail)):
        stack = np.clip(np.concatenate(layers, axis=0), 0.0, 1.0)
        side = layers[0].shape[0]
        img = bpy.data.images.new(label, side, side * len(layers), alpha=True)
        img.pixels[:] = stack[::-1].reshape(-1).tolist()
        img.filepath_raw = os.path.join(OUT, label + ".png")
        img.file_format = "PNG"
        img.save()
        print("wrote", img.filepath_raw)


if __name__ == "__main__":
    main()
