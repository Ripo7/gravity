"""Makes the cloud of dust the game puffs where something breaks: python3 tools/blender/dust.py assets/fx

A real cloud, not a blob: a volume whose density is a noise that swells,
thins and drifts over sixteen frames, lit by a sun from above and a pale
sky, rendered by Cycles and laid out as a sheet of 4 x 4 frames:

  dust.png   white where the sun gets, grey underneath, with its alpha;
             the game tints it with what broke (brick dust, concrete, ...)

Needs Blender as a Python module (pip install bpy), numpy and Pillow.
"""

import math
import os
import sys
import tempfile

import bpy
import numpy as np
from PIL import Image

FRAME = 128
ACROSS = 4
FRAMES = ACROSS * ACROSS


def cloud():
    """A ball of dust, with what drives it: how far along its life it is (0 to 1)."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.25, segments=24, ring_count=12)
    ball = bpy.context.object
    mat = bpy.data.materials.new("dust")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    volume = nodes.new("ShaderNodeVolumePrincipled")
    volume.inputs["Color"].default_value = (0.92, 0.92, 0.92, 1.0)
    volume.inputs["Anisotropy"].default_value = 0.25
    links.new(volume.outputs[0], out.inputs["Volume"])
    where = nodes.new("ShaderNodeTexCoord")
    age = nodes.new("ShaderNodeValue")  # 0 as it bursts, 1 as it is gone
    age.name = "age"
    # Billows: a noise that changes as the cloud ages (its fourth dimension)
    # and rises a little.
    noise = nodes.new("ShaderNodeTexNoise")
    noise.noise_dimensions = "4D"
    noise.inputs["Scale"].default_value = 1.5
    noise.inputs["Detail"].default_value = 5.0
    noise.inputs["Roughness"].default_value = 0.6
    drift = nodes.new("ShaderNodeMath")
    drift.operation = "MULTIPLY"
    drift.inputs[1].default_value = 0.9
    links.new(age.outputs[0], drift.inputs[0])
    links.new(where.outputs["Object"], noise.inputs["Vector"])
    links.new(drift.outputs[0], noise.inputs["W"])
    # It fills a ball that swells fast, then slowly: radius = 0.7 + 0.5 * (1 - (1 - age)^3).
    left = nodes.new("ShaderNodeMath")
    left.operation = "SUBTRACT"
    left.inputs[0].default_value = 1.0
    links.new(age.outputs[0], left.inputs[1])
    cubed = nodes.new("ShaderNodeMath")
    cubed.operation = "POWER"
    cubed.inputs[1].default_value = 3.0
    links.new(left.outputs[0], cubed.inputs[0])
    radius = nodes.new("ShaderNodeMath")
    radius.operation = "MULTIPLY_ADD"
    radius.inputs[1].default_value = -0.5
    radius.inputs[2].default_value = 1.2
    links.new(cubed.outputs[0], radius.inputs[0])
    far = nodes.new("ShaderNodeVectorMath")
    far.operation = "LENGTH"
    links.new(where.outputs["Object"], far.inputs[0])
    share = nodes.new("ShaderNodeMath")
    share.operation = "DIVIDE"
    links.new(far.outputs["Value"], share.inputs[0])
    links.new(radius.outputs[0], share.inputs[1])
    # Dense in the middle, nothing at the edge, which the noise pushes in
    # and out (billows); the noise eats into it too, the more the older it is.
    lumpy = nodes.new("ShaderNodeMath")
    lumpy.operation = "MULTIPLY_ADD"  # share + (0.5 - noise) * 0.9
    lumpy.inputs[1].default_value = -0.9
    links.new(noise.outputs["Fac"], lumpy.inputs[0])
    pushed = nodes.new("ShaderNodeMath")
    pushed.operation = "ADD"
    pushed.inputs[1].default_value = 0.45
    links.new(share.outputs[0], pushed.inputs[0])
    links.new(pushed.outputs[0], lumpy.inputs[2])
    body = nodes.new("ShaderNodeMapRange")
    body.inputs["From Min"].default_value = 1.0
    body.inputs["From Max"].default_value = 0.6
    body.inputs["To Min"].default_value = 0.0
    body.inputs["To Max"].default_value = 1.0
    links.new(lumpy.outputs[0], body.inputs["Value"])
    eaten = nodes.new("ShaderNodeMath")
    eaten.operation = "MULTIPLY_ADD"  # age * 0.3 + 0.3: how much noise it takes to leave a hole
    eaten.inputs[1].default_value = 0.42
    eaten.inputs[2].default_value = 0.2
    links.new(age.outputs[0], eaten.inputs[0])
    holes = nodes.new("ShaderNodeMath")
    holes.operation = "SUBTRACT"
    links.new(noise.outputs["Fac"], holes.inputs[0])
    links.new(eaten.outputs[0], holes.inputs[1])
    sharp = nodes.new("ShaderNodeMath")
    sharp.operation = "MULTIPLY"
    sharp.inputs[1].default_value = 5.0
    sharp.use_clamp = True
    links.new(holes.outputs[0], sharp.inputs[0])
    dense = nodes.new("ShaderNodeMath")
    dense.operation = "MULTIPLY"
    links.new(body.outputs[0], dense.inputs[0])
    links.new(sharp.outputs[0], dense.inputs[1])
    # Thick when it bursts, thin when it goes: 16 * (1 - age)^1.5 + 0.5.
    thin = nodes.new("ShaderNodeMath")
    thin.operation = "POWER"
    thin.inputs[1].default_value = 1.5
    links.new(left.outputs[0], thin.inputs[0])
    thick = nodes.new("ShaderNodeMath")
    thick.operation = "MULTIPLY_ADD"
    thick.inputs[1].default_value = 22.0
    thick.inputs[2].default_value = 0.6
    links.new(thin.outputs[0], thick.inputs[0])
    density = nodes.new("ShaderNodeMath")
    density.operation = "MULTIPLY"
    links.new(dense.outputs[0], density.inputs[0])
    links.new(thick.outputs[0], density.inputs[1])
    links.new(density.outputs[0], volume.inputs["Density"])
    ball.data.materials.append(mat)
    return age


def brighten(sheet):
    """As light as dust in the sun is: its lit side white, so that the game's tint is its colour."""
    pixels = np.asarray(sheet, dtype=np.float32) / 255.0
    thick = pixels[..., 3] > 0.3
    most = np.percentile(pixels[..., :3][thick], 97)
    pixels[..., :3] = np.clip(pixels[..., :3] / most, 0.0, 1.0) ** 0.8
    return Image.fromarray(np.round(pixels * 255.0).astype(np.uint8), "RGBA")


def main(out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = False
    scene.cycles.volume_bounces = 3
    scene.cycles.max_bounces = 6
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = FRAME
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.world = bpy.data.worlds.new("sky")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.36, 0.39, 0.44, 1.0)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 6.5
    sun.rotation_euler = (math.radians(35), math.radians(25), 0)
    scene.collection.objects.link(sun)
    camera = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.6
    camera.location = (0, -6, 0)
    camera.rotation_euler = (math.pi / 2, 0, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera
    age = cloud()
    only = int(os.environ.get("FRAMES", FRAMES))  # (fewer, to try it out)
    sheet = Image.new("RGBA", (FRAME * ACROSS, FRAME * ACROSS))
    with tempfile.TemporaryDirectory() as scratch:
        for k in range(FRAMES):
            if k % (FRAMES // only):
                continue
            age.outputs[0].default_value = k / (FRAMES - 1) * 0.94
            scene.render.filepath = os.path.join(scratch, "frame.png")
            bpy.ops.render.render(write_still=True)
            frame = np.asarray(Image.open(scene.render.filepath).convert("RGBA"), dtype=np.float32) / 255.0
            # Soft at the edge of its square, so that no frame is cut off.
            y, x = np.mgrid[0:FRAME, 0:FRAME] / (FRAME - 1.0) * 2.0 - 1.0
            edge = np.clip((1.0 - np.sqrt(x * x + y * y)) * 6.0, 0.0, 1.0)
            frame[..., 3] *= edge
            tile = Image.fromarray(np.round(frame * 255.0).astype(np.uint8), "RGBA")
            sheet.paste(tile, ((k % ACROSS) * FRAME, (k // ACROSS) * FRAME))
            print("frame", k, flush=True)
    brighten(sheet).save(os.path.join(out, "dust.png"), optimize=True)


if __name__ == "__main__":
    main(sys.argv[1])
