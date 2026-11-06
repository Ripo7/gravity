"""Bakes the sky's clouds in Blender: a layer of cumulus lit by the game's
late-afternoon sun, rendered by Cycles as a panorama of the upper half of
the sky, for the sky shader to lay over its colours.

Run with Blender's Python module (pip install bpy), from the project root:

    python3 tools/make_sky.py            # about 6 min on 2 cores
    python3 tools/make_sky.py --test     # small and quick (orientation check)

The clouds are a slab of volume 1.4 to 2.2 km up, 30 km across, whose
density is fractal noise cut off at a coverage level and thinned towards the
slab's top and bottom (flat-ish bases, billowing tops). The sun lamp shines
from the same direction as the game's sun (SUN below, Godot axes); a pale
blue world lights the shadowed sides. Film transparent:
  assets/textures/sky_clouds.png   RGB = the light on the clouds,
                                   A = how much of the sky they hide
Equirectangular, longitude across (u = 0.5 looks toward Godot -z), latitude
0 (the horizon) at the bottom to 90 degrees at the top. The game's sky shader
(shaders/sky.gdshader) reads it with the same mapping.
"""

import math
import os
import sys

import bpy  # first: it makes the other Blender modules importable
import bmesh
import numpy as np
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "sky_clouds.png")
TEST = "--test" in sys.argv
WIDTH = 512 if TEST else 2048
HEIGHT = WIDTH // 4  # 360 x 90 degrees, square pixels
SAMPLES = 8 if TEST else 64
## Toward the sun, in Godot axes (y up); the game's Sun light is set to it.
SUN = Vector((0.775, 0.407, 0.484)).normalized()
SUN_COLOR = (1.0, 0.74, 0.5)
BASE = 1400.0  # m
TOP = 2200.0
SPAN = 15000.0  # half width of the layer, m


def godot_to_blender(v):
    return Vector((v.x, -v.z, v.y))


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.volume_bounces = 2
    scene.cycles.volume_step_rate = 4.0 if TEST else 2.0
    scene.cycles.volume_max_steps = 512
    scene.render.film_transparent = True
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    return scene


def clouds(scene):
    mesh = bpy.data.meshes.new("clouds")
    h = SPAN
    verts = [(x, y, z) for z in (BASE, TOP) for y in (-h, h) for x in (-h, h)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # outward: a closed volume
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("clouds", mesh)
    scene.collection.objects.link(obj)
    mat = bpy.data.materials.new("clouds")
    mat.use_nodes = True
    nt = mat.node_tree
    n = nt.nodes
    n.clear()
    link = nt.links.new
    out = n.new("ShaderNodeOutputMaterial")
    vol = n.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    vol.inputs["Anisotropy"].default_value = 0.35  # bright edges toward the sun
    coord = n.new("ShaderNodeTexCoord")
    # Big billows: low frequency fractal noise, cut at a coverage level.
    big = n.new("ShaderNodeTexNoise")
    big.inputs["Scale"].default_value = 0.00042
    big.inputs["Detail"].default_value = 7.0
    big.inputs["Roughness"].default_value = 0.58
    link(coord.outputs["Object"], big.inputs["Vector"])
    # Height in the slab: 0 at the base, 1 at the top.
    sep = n.new("ShaderNodeSeparateXYZ")
    link(coord.outputs["Object"], sep.inputs["Vector"])
    hgt = n.new("ShaderNodeMapRange")
    hgt.inputs["From Min"].default_value = BASE
    hgt.inputs["From Max"].default_value = TOP
    link(sep.outputs["Z"], hgt.inputs["Value"])
    # Flat bases, rounded tops: thin out fast at the base, slowly above.
    base = n.new("ShaderNodeMapRange")
    base.inputs["From Min"].default_value = 0.0
    base.inputs["From Max"].default_value = 0.12
    link(hgt.outputs["Result"], base.inputs["Value"])
    top = n.new("ShaderNodeMapRange")
    top.inputs["From Min"].default_value = 1.0
    top.inputs["From Max"].default_value = 0.35
    link(hgt.outputs["Result"], top.inputs["Value"])
    shape = n.new("ShaderNodeMath")
    shape.operation = "MULTIPLY"
    link(base.outputs["Result"], shape.inputs[0])
    link(top.outputs["Result"], shape.inputs[1])
    # The taller the cloud, the more of the slab it fills: cut the noise
    # higher near the top.
    cut = n.new("ShaderNodeMath")
    cut.operation = "MULTIPLY_ADD"
    link(hgt.outputs["Result"], cut.inputs[0])
    cut.inputs[1].default_value = 0.16
    cut.inputs[2].default_value = 0.5
    dens = n.new("ShaderNodeMath")
    dens.operation = "SUBTRACT"
    link(big.outputs["Fac"], dens.inputs[0])
    link(cut.outputs[0], dens.inputs[1])
    dens.use_clamp = True
    d2 = n.new("ShaderNodeMath")
    d2.operation = "MULTIPLY"
    link(dens.outputs[0], d2.inputs[0])
    link(shape.outputs[0], d2.inputs[1])
    scale = n.new("ShaderNodeMath")
    scale.operation = "MULTIPLY"
    link(d2.outputs[0], scale.inputs[0])
    scale.inputs[1].default_value = 0.09  # per metre
    link(scale.outputs[0], vol.inputs["Density"])
    link(vol.outputs["Volume"], out.inputs["Volume"])
    obj.data.materials.append(mat)
    if TEST:
        # Markers: red toward Godot +x, green toward Godot -z (Blender +y).
        for name, pos, col in (
            ("x", godot_to_blender(Vector((1, 0.3, 0))) * 3000, (1, 0, 0, 1)),
            ("nz", godot_to_blender(Vector((0, 0.3, -1))) * 3000, (0, 1, 0, 1)),
        ):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=250, location=pos)
            m = bpy.data.materials.new(name)
            m.use_nodes = True
            em = m.node_tree.nodes.new("ShaderNodeEmission")
            em.inputs["Color"].default_value = col
            em.inputs["Strength"].default_value = 5.0
            m.node_tree.links.new(em.outputs[0], m.node_tree.nodes["Material Output"].inputs["Surface"])
            bpy.context.active_object.data.materials.append(m)


def light_and_camera(scene):
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 5.5
    sun.data.color = SUN_COLOR
    sun.data.angle = math.radians(1.0)
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(godot_to_blender(SUN))
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.34, 0.46, 0.75, 1.0)
    bg.inputs["Strength"].default_value = 0.7
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.data.type = "PANO"
    pano = cam.data
    pano.panorama_type = "EQUIRECTANGULAR"
    pano.latitude_min = 0.0
    pano.latitude_max = math.radians(90.0)
    pano.longitude_min = -math.pi
    pano.longitude_max = math.pi
    pano.clip_start = 1.0
    pano.clip_end = 100000.0  # the clouds are kilometres away
    cam.location = (0.0, 0.0, 2.0)
    # Blender's panorama camera looks along its local x axis; turn it to
    # look along Blender +y (Godot -z) with z up.
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.camera = cam


def main():
    scene = setup()
    clouds(scene)
    light_and_camera(scene)
    path = "/tmp/gravity_sky_test.png" if TEST else "/tmp/gravity_sky.png"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    if TEST:
        print("wrote", path)
        return
    img = bpy.data.images.load(path)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(HEIGHT, WIDTH, 4)
    bpy.data.images.remove(img)
    # Soften the last of the sampling noise at the wispy edges (a 3 x 3
    # blur of the premultiplied colour and the cover).
    pad = np.pad(px, ((1, 1), (1, 1), (0, 0)), mode="edge")
    pad[:, 0] = pad[:, -2]  # the panorama wraps round
    pad[:, -1] = pad[:, 1]
    px = sum(pad[1 + dy : 1 + dy + HEIGHT, 1 + dx : 1 + dx + WIDTH] for dy in (-1, 0, 1) for dx in (-1, 0, 1)) / 9.0
    # Straight (not premultiplied) colour where there is cloud, so the
    # shader can mix it over the sky.
    a = px[..., 3:4]
    rgb = np.where(a > 1e-3, px[..., :3] / np.maximum(a, 1e-3), 0.0)
    px = np.concatenate([np.clip(rgb, 0.0, 1.0), a], axis=2)
    out = bpy.data.images.new("clouds", WIDTH, HEIGHT, alpha=True)
    out.pixels[:] = px.reshape(-1).tolist()
    out.filepath_raw = OUT
    out.file_format = "PNG"
    out.save()
    print("wrote", OUT)


if __name__ == "__main__":
    main()
