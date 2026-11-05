"""Builds a puff of dust in Blender and renders it as a flipbook for the
game's dust clouds.

Run with Blender's Python module (pip install bpy), from the project root:

    python3 tools/make_smoke.py

The puff is a Geometry Nodes volume: a Volume Cube whose density is a ball
that swells, rises and thins out over time, broken up by 4D noise whose
fourth axis is time, so the billows churn as they grow. (A Mantaflow
simulation would be the obvious choice, but the fluid solver aborts in
Blender's Python module build.) Cycles renders it side-on, lit from above,
on a transparent film; 64 frames go into an 8 x 8 sheet:
  assets/textures/dust_flipbook.png   R = light on the cloud (lit from
                                      above), A = how dense it is
The game picks the frame from the puff's age (shaders/dust.gdshader).
"""

import os

import bpy  # first: it makes the other Blender modules importable
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "dust_flipbook.png")
FRAMES = 64
CELL = 128  # pixels per frame
GRID = 8
RES = 96  # voxels per side of the puff's volume


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.frame_start = 0
    scene.frame_end = FRAMES - 1
    scene.render.fps = 24
    mesh = bpy.data.meshes.new("puff")
    domain = bpy.data.objects.new("puff", mesh)
    scene.collection.objects.link(domain)
    ng = bpy.data.node_groups.new("Puff", "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    n = ng.nodes
    link = ng.links.new
    out = n.new("NodeGroupOutput")
    cube = n.new("GeometryNodeVolumeCube")
    cube.inputs["Min"].default_value = (-1.6, -1.6, -0.2)
    cube.inputs["Max"].default_value = (1.6, 1.6, 3.0)
    for axis in ("X", "Y", "Z"):
        cube.inputs["Resolution " + axis].default_value = RES
    link(cube.outputs["Volume"], out.inputs["Geometry"])
    # Age 0..1 over the clip.
    time = n.new("GeometryNodeInputSceneTime")
    age = math_node(n, link, "DIVIDE", time.outputs["Frame"], float(FRAMES))
    pos = n.new("GeometryNodeInputPosition").outputs["Position"]
    # The ball: swells fast then slowly (sqrt), rises, thins out.
    grow = math_node(n, link, "SQRT", age)
    radius = math_node(n, link, "MULTIPLY_ADD", grow, 0.95, 0.45)
    rise = math_node(n, link, "MULTIPLY_ADD", age, 0.9, 0.55)
    centre = n.new("ShaderNodeCombineXYZ")
    link(rise, centre.inputs["Z"])
    off = n.new("ShaderNodeVectorMath")
    off.operation = "SUBTRACT"
    link(pos, off.inputs[0])
    link(centre.outputs[0], off.inputs[1])
    # Squashed a little: dust spreads more than it climbs.
    squash = n.new("ShaderNodeVectorMath")
    squash.operation = "MULTIPLY"
    link(off.outputs[0], squash.inputs[0])
    squash.inputs[1].default_value = (1.0, 1.0, 1.25)
    dist = n.new("ShaderNodeVectorMath")
    dist.operation = "LENGTH"
    link(squash.outputs[0], dist.inputs[0])
    r = math_node(n, link, "DIVIDE", dist.outputs["Value"], radius)
    # Billows: 4D noise, its fourth axis is time, churning the edge.
    noise = n.new("ShaderNodeTexNoise")
    noise.noise_dimensions = "4D"
    link(pos, noise.inputs["Vector"])
    link(math_node(n, link, "MULTIPLY", age, 2.2), noise.inputs["W"])
    noise.inputs["Scale"].default_value = 0.85
    noise.inputs["Detail"].default_value = 5.0
    noise.inputs["Roughness"].default_value = 0.62
    # Cauliflower lobes: a slow, large noise moves the edge a lot.
    lobes = n.new("ShaderNodeTexNoise")
    lobes.noise_dimensions = "4D"
    link(pos, lobes.inputs["Vector"])
    link(math_node(n, link, "MULTIPLY_ADD", age, 1.3, 5.0), lobes.inputs["W"])
    lobes.inputs["Scale"].default_value = 0.45
    lobes.inputs["Detail"].default_value = 2.0
    # Billows push the edge in and out; the inside is lumpy too.
    lumpy = math_node(n, link, "MULTIPLY_ADD", noise.outputs["Fac"], 1.2, -0.6)
    big = math_node(n, link, "MULTIPLY_ADD", lobes.outputs["Fac"], 1.8, -0.9)
    edge = math_node(n, link, "ADD", r, math_node(n, link, "ADD", lumpy, big))
    inside = math_node(n, link, "MULTIPLY_ADD", noise.outputs["Fac"], 1.2, 0.1)
    ball = n.new("ShaderNodeMapRange")
    ball.inputs["From Min"].default_value = 1.0
    ball.inputs["From Max"].default_value = 0.35
    link(edge, ball.inputs["Value"])
    fade = math_node(n, link, "POWER", math_node(n, link, "SUBTRACT", 1.0, age), 1.6)
    density = math_node(n, link, "MULTIPLY", math_node(n, link, "MULTIPLY", ball.outputs["Result"], inside), fade)
    link(math_node(n, link, "MULTIPLY", density, 3.5), cube.inputs["Density"])
    mod = domain.modifiers.new("puff", "NODES")
    mod.node_group = ng
    return scene, domain


def math_node(nodes, link, op, a, b=None, c=None):
    m = nodes.new("ShaderNodeMath")
    m.operation = op
    for k, val in enumerate((a, b, c)):
        if val is None:
            continue
        if isinstance(val, (int, float)):
            m.inputs[k].default_value = val
        else:
            link(val, m.inputs[k])
    return m.outputs[0]


def shade(domain):
    mat = bpy.data.materials.new("dust")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    vol = nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    vol.inputs["Density"].default_value = 6.0
    attr = nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "density"
    mat.node_tree.links.new(attr.outputs["Fac"], vol.inputs["Density"])
    mul = nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 6.0
    mat.node_tree.links.new(attr.outputs["Fac"], mul.inputs[0])
    mat.node_tree.links.new(mul.outputs[0], vol.inputs["Density"])
    mat.node_tree.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    domain.data.materials.clear()
    domain.data.materials.append(mat)


def camera_and_light(scene):
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.9
    cam.location = (0.0, -8.0, 1.35)
    cam.rotation_euler = (1.5708, 0.0, 0.0)
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (0.75, 0.3, 0.0)  # from above and in front
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.25, 0.25, 0.27, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.cycles.volume_bounces = 1
    scene.render.film_transparent = True
    scene.render.resolution_x = CELL
    scene.render.resolution_y = CELL
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"


def main():
    scene, domain = setup()
    shade(domain)
    camera_and_light(scene)
    sheet = np.zeros((GRID * CELL, GRID * CELL, 4), dtype=np.float32)
    for k in range(FRAMES):
        scene.frame_set(k)
        path = "/tmp/gravity_smoke_%02d.png" % k
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(path)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL, CELL, 4)[::-1]
        bpy.data.images.remove(img)
        row, col = divmod(k, GRID)
        lum = px[..., :3].mean(axis=2) / np.maximum(px[..., 3], 1e-3)
        cell = np.stack([np.clip(lum, 0, 1), np.zeros_like(lum), np.zeros_like(lum), px[..., 3]], axis=2)
        sheet[row * CELL : (row + 1) * CELL, col * CELL : (col + 1) * CELL] = cell
        print("frame", k)
    out = bpy.data.images.new("dust", GRID * CELL, GRID * CELL, alpha=True)
    out.pixels[:] = sheet[::-1].reshape(-1).tolist()
    out.filepath_raw = OUT
    out.file_format = "PNG"
    out.save()
    print("wrote", OUT)


if __name__ == "__main__":
    main()
