"""Makes the textures of the city's buildings: python3 tools/blender/facades.py assets/city

Each kind of wall is modelled for real, one bay of one floor at a time
(windows set back in the wall, frames, sills, shutters, awnings, cornices),
then baked by Cycles into two images the game lays on its boxes:

  facades_albedo.png   colours, with the shade the relief casts on itself;
                       alpha says where the box's own paint goes
  facades_normal.png   the relief, as a normal map

Four columns of four tiles. Columns 0 to 2 are a house, an office and a
tower, each with its ground floor, a floor in between, its top floor, and
(unused) a spare; column 3 is roof tiles, bricks, concrete (what shows in
a broken wall) and the gravel of a flat roof. Tiles repeat: each is baked
with copies of itself all round.

Needs Blender as a Python module (pip install bpy), numpy and Pillow.
"""

import math
import os
import random
import sys
import tempfile

import bpy  # (before bmesh: it is what makes bmesh importable)
import bmesh  # isort: skip
import numpy as np
from PIL import Image

TILE = 256
DEEP = 0.14  # how thick a wall is, in tiles

STONE = (0.78, 0.74, 0.66)
CREAM = (0.93, 0.9, 0.8)
GLASS = (0.16, 0.34, 0.6)
STEEL = (0.16, 0.18, 0.24)
PAINT = (0.92, 0.92, 0.92)  # takes the colour of the box


class Module:
    """One tile: boxes, each with its colour and whether the box's paint goes on it."""

    def __init__(self):
        self.parts = []

    def box(self, x, z, y, rgb, paint=False, bevel=0.012, lean=0.0, shade=None):
        """A box from x[0] to x[1] across, z[0] to z[1] up, y[0] (out, negative) to y[1] (in)."""
        mesh = bpy.data.meshes.new("part")
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        size = (x[1] - x[0], y[1] - y[0], z[1] - z[0])
        for v in bm.verts:
            v.co.x *= size[0]
            v.co.y *= size[1]
            v.co.z *= size[2]
        if bevel > 0 and min(size) > bevel * 2.5:
            bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=2, affect="EDGES", profile=0.5)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("part", mesh)
        obj.location = ((x[0] + x[1]) / 2, (y[0] + y[1]) / 2, (z[0] + z[1]) / 2)
        obj.rotation_euler = (lean, 0, 0)
        self.parts.append((obj, rgb, paint, shade))
        return obj

    def wall(self, hole, rgb=PAINT, paint=True):
        """A wall with a hole in it (x0, x1, z0, z1), in four strips."""
        x0, x1, z0, z1 = hole
        for x, z in (((0, x0), (0, 1)), ((x1, 1), (0, 1)), ((x0, x1), (0, z0)), ((x0, x1), (z1, 1))):
            if x[1] - x[0] > 0.001 and z[1] - z[0] > 0.001:
                self.box(x, z, (0, DEEP), rgb, paint, bevel=0)

    def window(self, hole, glass=GLASS, frame=CREAM, bars=(1, 1), back=0.09):
        """Glass set back in a hole, with a frame and bars."""
        x0, x1, z0, z1 = hole
        self.box((x0, x1), (z0, z1), (back, back + 0.02), glass, bevel=0, shade=(z0, z1))
        t = 0.025
        for x, z in (((x0, x0 + t), (z0, z1)), ((x1 - t, x1), (z0, z1)), ((x0, x1), (z0, z0 + t)), ((x0, x1), (z1 - t, z1))):
            self.box(x, z, (back - 0.035, back), frame, bevel=0.006)
        for k in range(1, bars[0] + 1):
            at = x0 + (x1 - x0) * k / (bars[0] + 1)
            self.box((at - 0.011, at + 0.011), (z0, z1), (back - 0.03, back), frame, bevel=0.004)
        for k in range(1, bars[1] + 1):
            at = z0 + (z1 - z0) * k / (bars[1] + 1)
            self.box((x0, x1), (at - 0.011, at + 0.011), (back - 0.03, back), frame, bevel=0.004)


def house(row):
    m = Module()
    teal = (0.16, 0.42, 0.4)
    if row == 0:  # a door, up two steps
        hole = (0.33, 0.67, 0.0, 0.74)
        m.wall(hole)
        m.box((0.33, 0.67), (0.06, 0.74), (0.07, 0.09), (0.5, 0.24, 0.14), bevel=0)
        for z in ((0.12, 0.36), (0.42, 0.68)):
            m.box((0.38, 0.62), z, (0.055, 0.07), (0.58, 0.29, 0.17), bevel=0.01)
        m.box((0.585, 0.615), (0.37, 0.4), (0.04, 0.07), (0.9, 0.75, 0.3), bevel=0.008)
        m.box((0.26, 0.74), (0.0, 0.06), (-0.1, 0.07), STONE)
        m.box((0.29, 0.71), (0.74, 0.8), (-0.035, 0.0), CREAM)
        for x in ((0.29, 0.33), (0.67, 0.71)):
            m.box(x, (0.06, 0.74), (-0.02, 0.0), CREAM, bevel=0.008)
        m.box((0.76, 0.84), (0.52, 0.64), (-0.05, 0.0), (0.95, 0.85, 0.45), bevel=0.02)
        return m
    hole = (0.31, 0.69, 0.24, 0.76) if row == 1 else (0.31, 0.69, 0.2, 0.7)
    m.wall(hole)
    m.window(hole)
    m.box((0.27, 0.73), (hole[2] - 0.06, hole[2]), (-0.06, 0.02), STONE)
    for x in ((0.17, 0.3), (0.7, 0.83)):  # shutters
        m.box(x, (hole[2], hole[3]), (-0.03, 0.0), teal, bevel=0.008)
        for k in range(5):
            z = hole[2] + 0.03 + (hole[3] - hole[2] - 0.06) * k / 5
            m.box((x[0] + 0.015, x[1] - 0.015), (z, z + 0.05), (-0.042, -0.03), teal, bevel=0.006, lean=0.25)
    if row == 2:  # under the eaves
        m.box((0, 1), (0.84, 0.91), (-0.04, 0.0), CREAM, bevel=0.01)
        m.box((0, 1), (0.91, 1.0), (-0.09, 0.0), STONE, bevel=0.015)
    return m


def office(row):
    m = Module()
    red = (0.82, 0.24, 0.2)
    if row == 0:  # a shop front under its awning
        hole = (0.1, 0.9, 0.0, 0.72)
        m.wall(hole)
        m.window((0.1, 0.9, 0.08, 0.72), glass=(0.12, 0.26, 0.42), frame=STEEL, bars=(2, 0), back=0.1)
        m.box((0.1, 0.9), (0.0, 0.08), (0.0, 0.12), STONE, bevel=0.008)
        m.box((0.04, 0.96), (0.66, 0.74), (-0.2, 0.0), red, bevel=0.012, lean=0.45)
        for k in range(4):  # its stripes
            x0 = 0.04 + 0.23 * k + 0.115
            m.box((x0, x0 + 0.115), (0.659, 0.741), (-0.202, 0.0), CREAM, bevel=0, lean=0.45)
    else:
        hole = (0.12, 0.88, 0.26, 0.84) if row == 1 else (0.12, 0.88, 0.2, 0.7)
        m.wall(hole)
        m.window(hole, frame=STEEL, bars=(1, 0))
        m.box((0.12, 0.88), (hole[2] - 0.18, hole[2] - 0.04), (-0.012, 0.0), (0.4, 0.42, 0.46), bevel=0.006)
        m.box((0.1, 0.9), (hole[2] - 0.04, hole[2]), (-0.04, 0.02), STONE)
    for x in ((0.0, 0.055), (0.945, 1.0)):  # a pilaster between two bays
        m.box(x, (0, 1), (-0.035, 0.0), PAINT, paint=True, bevel=0.01)
    if row == 2:  # the cornice
        m.box((0, 1), (0.82, 0.9), (-0.06, 0.0), STONE, bevel=0.012)
        m.box((0, 1), (0.9, 1.0), (-0.11, 0.0), CREAM, bevel=0.018)
    return m


def tower(row):
    m = Module()
    pane = (0.86, 0.9, 0.94)
    if row == 0:  # the lobby
        m.box((0.07, 0.93), (0.0, 0.8), (0.1, 0.12), (0.1, 0.2, 0.32), bevel=0, shade=(0.0, 0.8))
        m.box((0.49, 0.51), (0.0, 0.8), (0.07, 0.1), STEEL, bevel=0.004)
        m.box((0.07, 0.93), (0.5, 0.52), (0.07, 0.1), STEEL, bevel=0.004)
        for x in ((0.0, 0.07), (0.93, 1.0)):
            m.box(x, (0, 0.8), (-0.03, DEEP), STONE, bevel=0.012)
        m.box((0, 1), (0.8, 1.0), (0.0, DEEP), STONE, bevel=0)
        m.box((0, 1), (0.8, 0.9), (-0.14, 0.0), CREAM, bevel=0.015)
        return m
    top = 0.84 if row == 2 else 1.0
    m.box((0.035, 0.965), (0.2, top), (0.04, 0.06), pane, paint=True, bevel=0, shade=(0.2, top))
    m.box((0.035, 0.965), (0.0, 0.2), (0.015, 0.06), (0.62, 0.66, 0.72), paint=True, bevel=0.006)
    m.box((0.0, 1.0), (0.19, 0.215), (0.0, 0.04), STEEL, bevel=0.005)
    for x in ((0.0, 0.035), (0.965, 1.0)):
        m.box(x, (0, 1), (-0.03, 0.06), STEEL, bevel=0.008)
    m.box((0.49, 0.51), (0.2, top), (0.015, 0.04), STEEL, bevel=0.004)
    if row == 2:
        m.box((0, 1), (0.84, 1.0), (-0.05, 0.06), CREAM, bevel=0.015)
    return m


def scattered(row):
    rng = random.Random(7 + row)
    m = Module()
    if row == 0:  # roof tiles, in rows that overlap
        for line in range(4):
            for k in range(-1, 5):
                x0 = k * 0.25 + (0.125 if line % 2 else 0.0)
                light = rng.uniform(0.8, 1.0)
                z0 = line * 0.25
                m.box((x0 + 0.008, x0 + 0.242), (z0, z0 + 0.3), (-0.05, -0.02), (light, light, light), paint=True, bevel=0.015, lean=0.1)
        m.box((0, 1), (0, 1), (0.0, 0.02), (0.3, 0.3, 0.3), paint=True, bevel=0)
    elif row == 1:  # bricks
        m.box((0, 1), (0, 1), (0.0, 0.02), (0.8, 0.76, 0.68), bevel=0)
        for line in range(5):
            for k in range(-1, 3):
                x0 = k * 0.5 + (0.25 if line % 2 else 0.0)
                tone = rng.uniform(0.8, 1.1)
                out = rng.uniform(-0.035, -0.02)
                m.box((x0 + 0.015, x0 + 0.485), (line * 0.2 + 0.015, line * 0.2 + 0.185), (out, 0.0), (0.72 * tone, 0.33 * tone, 0.22 * tone), bevel=0.012)
    elif row == 2:  # concrete, its stones showing
        m.box((0, 1), (0, 1), (0.0, 0.02), (0.56, 0.56, 0.57), bevel=0)
        for k in range(60):
            x0, z0, s = rng.random(), rng.random(), rng.uniform(0.02, 0.07)
            tone = rng.uniform(0.38, 0.7)
            m.box((x0, x0 + s), (z0, z0 + s * rng.uniform(0.6, 1.2)), (-rng.uniform(0.004, 0.02), 0.0), (tone, tone, tone * 1.03), bevel=s * 0.3, lean=rng.uniform(-0.3, 0.3))
    else:  # the gravel of a flat roof
        m.box((0, 1), (0, 1), (0.0, 0.02), (0.42, 0.42, 0.44), bevel=0)
        for k in range(220):
            x0, z0, s = rng.random(), rng.random(), rng.uniform(0.015, 0.04)
            tone = rng.uniform(0.4, 0.62)
            m.box((x0, x0 + s), (z0, z0 + s), (-rng.uniform(0.004, 0.012), 0.0), (tone, tone, tone * 1.04), bevel=s * 0.3)
    return m


def emission(colour, shade=None):
    """A material that shows `colour` as it is; `shade` (z0, z1) makes it darker low down."""
    mat = bpy.data.materials.new("flat")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    links.new(emit.outputs[0], out.inputs[0])
    emit.inputs[0].default_value = (*colour, 1.0)
    if shade is not None:
        # Shader nodes: the height of the point drives how light the glass is.
        geometry = nodes.new("ShaderNodeNewGeometry")
        apart = nodes.new("ShaderNodeSeparateXYZ")
        ramp = nodes.new("ShaderNodeMapRange")
        scale = nodes.new("ShaderNodeVectorMath")
        scale.operation = "SCALE"
        links.new(geometry.outputs["Position"], apart.inputs[0])
        links.new(apart.outputs["Z"], ramp.inputs[0])
        z0, z1 = shade
        ramp.inputs[1].default_value = math.floor(z0) + (z0 - math.floor(z0))
        ramp.inputs[2].default_value = z1
        ramp.inputs[3].default_value = 0.7
        ramp.inputs[4].default_value = 1.25
        scale.inputs[0].default_value = colour
        links.new(ramp.outputs[0], scale.inputs[3])
        links.new(scale.outputs[0], emit.inputs[0])
    return mat


def facing():
    """A material that shows which way each point faces, as a normal map does."""
    mat = bpy.data.materials.new("facing")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    geometry = nodes.new("ShaderNodeNewGeometry")
    apart = nodes.new("ShaderNodeSeparateXYZ")
    together = nodes.new("ShaderNodeCombineXYZ")
    links.new(geometry.outputs["Normal"], apart.inputs[0])
    # Right is +X, up is +Z, and out of the wall is -Y.
    for k, (axis, sign) in enumerate((("X", 0.5), ("Z", 0.5), ("Y", -0.5))):
        half = nodes.new("ShaderNodeMath")
        half.operation = "MULTIPLY_ADD"
        half.inputs[1].default_value = sign
        half.inputs[2].default_value = 0.5
        links.new(apart.outputs[axis], half.inputs[0])
        links.new(half.outputs[0], together.inputs[k])
    links.new(together.outputs[0], emit.inputs[0])
    links.new(emit.outputs[0], out.inputs[0])
    return mat


def white():
    mat = bpy.data.materials.new("white")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1.0)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    return mat


def render(scene, path, samples, raw, sky):
    scene.cycles.samples = samples
    scene.view_settings.view_transform = "Raw" if raw else "Standard"
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (sky, sky, sky, 1.0)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return Image.open(path).convert("RGB")


def bake(module, scratch):
    """The four pictures of a tile: colour, where the paint goes, shade, facing."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 2
    scene.render.resolution_x = scene.render.resolution_y = TILE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.look = "None"
    scene.world = bpy.data.worlds.new("sky")
    scene.world.use_nodes = True
    camera = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.0
    camera.location = (0.5, -5.0, 0.5)
    camera.rotation_euler = (math.pi / 2, 0, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera
    objects = []
    for obj, rgb, paint, shade in module.parts:
        scene.collection.objects.link(obj)
        objects.append((obj, rgb, paint, shade))
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                if dx or dz:  # the same tile all round, so that it repeats
                    twin = obj.copy()
                    twin.location.x += dx
                    twin.location.z += dz
                    scene.collection.objects.link(twin)
                    objects.append((twin, rgb, paint, shade))
    flat = {}
    passes = {}
    for name in ("colour", "paint", "shade", "facing"):
        for obj, rgb, paint, shade in objects:
            key = (name, rgb, paint, shade)
            if key not in flat:
                if name == "colour":
                    flat[key] = emission(rgb, shade)
                elif name == "paint":
                    flat[key] = emission((1, 1, 1) if paint else (0, 0, 0))
                elif name == "shade":
                    flat[key] = flat.get("white") or white()
                    flat["white"] = flat[key]
                else:
                    flat[key] = flat.get("facing") or facing()
                    flat["facing"] = flat[key]
            obj.data.materials.clear()
            obj.data.materials.append(flat[key])
        lit = name == "shade"
        passes[name] = render(scene, os.path.join(scratch, name + ".png"), 160 if lit else 8, name != "colour", 1.0 if lit else 0.0)
    return passes


def main(out):
    albedo = Image.new("RGBA", (TILE * 4, TILE * 4))
    normal = Image.new("RGB", (TILE * 4, TILE * 4), (128, 128, 255))
    with tempfile.TemporaryDirectory() as scratch:
        for col, make in enumerate((house, office, tower, scattered)):
            for row in range(4):
                if col < 3 and row == 3:
                    continue
                bpy.ops.wm.read_factory_settings(use_empty=True)
                got = bake(make(row), scratch)
                colour = np.asarray(got["colour"], dtype=np.float32) / 255.0
                shade = np.asarray(got["shade"].convert("L"), dtype=np.float32) / 255.0
                # As light as the open wall is: only what is in a corner goes darker.
                lit = (0.25 + 0.75 * np.clip(shade / np.percentile(shade, 90), 0.0, 1.0)) ** 0.6
                rgb = np.round(colour * lit[..., None] * 255.0).astype(np.uint8)
                paint = np.asarray(got["paint"].convert("L"))
                tile = Image.fromarray(np.dstack([rgb, paint]), "RGBA")
                albedo.paste(tile, (col * TILE, row * TILE))
                normal.paste(got["facing"], (col * TILE, row * TILE))
                print("baked", make.__name__, row, flush=True)
    albedo.save(os.path.join(out, "facades_albedo.png"), optimize=True)
    normal.save(os.path.join(out, "facades_normal.png"), optimize=True)


if __name__ == "__main__":
    main(sys.argv[1])
