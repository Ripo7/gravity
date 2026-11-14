"""Puts motion capture on the mannequin.

A take (bvh.Take, CMU skeleton, T pose at frame 0, facing +Z) is turned
into the mannequin's bone rotations: every mapped bone takes the turn its
joint made since the T pose, in the world (the mannequin's rest is a T pose
facing +Z too). The two T poses are not quite the same (the take's arms
hang 8 degrees, the mannequin's are level): the long bones are first laid
along the take's. The hips are placed so that the hip joints are where the
take's are, scaled by the length of the legs."""
import numpy as np

from skeleton import matrix_to_quat, quat_to_matrix

MAP = {
    "DEF-hips": "Hips",
    "DEF-spine.001": "LowerBack",
    "DEF-spine.002": "Spine",
    "DEF-spine.003": "Spine1",
    "DEF-neck": "Neck1",
    "DEF-head": "Head",
}
for side, name in (("L", "Left"), ("R", "Right")):
    MAP["DEF-shoulder." + side] = name + "Shoulder"
    MAP["DEF-upper_arm." + side] = name + "Arm"
    MAP["DEF-forearm." + side] = name + "ForeArm"
    MAP["DEF-hand." + side] = name + "Hand"
    MAP["DEF-thigh." + side] = name + "UpLeg"
    MAP["DEF-shin." + side] = name + "Leg"
    MAP["DEF-foot." + side] = name + "Foot"
    MAP["DEF-toe." + side] = name + "ToeBase"


# The long bones, and the joint each one points to: mannequin, then take.
LONG = {}
for side, name in (("L", "Left"), ("R", "Right")):
    LONG["DEF-upper_arm." + side] = ("DEF-forearm." + side, name + "ForeArm")
    LONG["DEF-forearm." + side] = ("DEF-hand." + side, name + "Hand")
    LONG["DEF-thigh." + side] = ("DEF-shin." + side, name + "Leg")
    LONG["DEF-shin." + side] = ("DEF-foot." + side, name + "Foot")


def between(u, v):
    """The smallest rotation that takes direction u onto direction v."""
    u, v = u / np.linalg.norm(u), v / np.linalg.norm(v)
    axis = np.cross(u, v)
    s, c = np.linalg.norm(axis), u @ v
    if s < 1e-9:
        return np.eye(3)
    k = axis / s
    cross = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + s * cross + (1 - c) * cross @ cross


def turn_y(angle):
    c, s = np.cos(angle), np.sin(angle)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def leg_scale(take, skel):
    """Metres of the mannequin for one unit of the take: by the legs."""
    mine = np.linalg.norm(skel.world_pos[skel.index("DEF-shin.L")] - skel.world_pos[skel.index("DEF-thigh.L")])
    mine += np.linalg.norm(skel.world_pos[skel.index("DEF-foot.L")] - skel.world_pos[skel.index("DEF-shin.L")])
    theirs = np.linalg.norm(take.offsets[take.index("LeftLeg")]) + np.linalg.norm(take.offsets[take.index("LeftFoot")])
    return mine / theirs


class Motion:
    """The mannequin moving: for F frames, the world rotation (F, B, 3, 3)
    of every bone, and the world position (F, 3) of the hips bone."""

    def __init__(self, skel, world, hips):
        self.skel, self.world, self.hips = skel, world, hips

    def positions(self):
        """World position (F, B, 3) of every bone."""
        s = self.skel
        pos = np.empty(self.world.shape[:2] + (3,))
        for b, p in enumerate(s.parents):
            if p < 0:
                pos[:, b] = s.rest_pos[b]
            elif s.names[b] == "DEF-hips":
                pos[:, b] = self.hips
            else:
                pos[:, b] = pos[:, p] + self.world[:, p] @ s.rest_pos[b]
        return pos

    def local(self):
        """Rotation of every bone in its parent (F, B, 3, 3)."""
        out = np.empty_like(self.world)
        for b, p in enumerate(self.skel.parents):
            out[:, b] = self.world[:, b] if p < 0 else np.swapaxes(self.world[:, p], 1, 2) @ self.world[:, b]
        return out


def retarget(take, skel, frames, fingers=None):
    """The mannequin at `frames` of the take, in the take's own place (in
    metres). `fingers`: local rotation (x, y, z, w) by bone name for bones
    the take says nothing about (the rest pose otherwise)."""
    frames = np.asarray(frames)
    rot, pos = take.world(frames)
    rot0, pos0 = take.world(np.array([0]))
    count = len(skel.names)
    world = np.empty((len(frames), count, 3, 3))
    for b, name in enumerate(skel.names):
        p = skel.parents[b]
        if name in MAP:
            j = take.index(MAP[name])
            rest = skel.world_rot[b]
            if name in LONG:
                mine, theirs = LONG[name]
                rest = between(
                    skel.world_pos[skel.index(mine)] - skel.world_pos[b], pos0[0, take.index(theirs)] - pos0[0, j]
                ) @ rest
            world[:, b] = rot[:, j] @ rot0[0, j].T @ rest
        elif p < 0:
            world[:, b] = skel.world_rot[b]
        elif fingers and name in fingers:
            world[:, b] = world[:, p] @ quat_to_matrix(fingers[name])
        else:
            world[:, b] = world[:, p] @ skel.rest_rot[b]
    scale = leg_scale(take, skel)
    hips = skel.index("DEF-hips")
    joints = (pos[:, take.index("LeftUpLeg")] + pos[:, take.index("RightUpLeg")]) * 0.5 * scale
    mine = (skel.world_pos[skel.index("DEF-thigh.L")] + skel.world_pos[skel.index("DEF-thigh.R")]) * 0.5
    offset = skel.world_rot[hips].T @ (mine - skel.world_pos[hips])
    return Motion(skel, world, joints - world[:, hips] @ offset)


def smooth(values, sigma):
    """Gaussian blur along the first axis (sigma in frames), ends held."""
    if sigma <= 0:
        return values.copy()
    half = int(np.ceil(sigma * 3))
    kernel = np.exp(-0.5 * (np.arange(-half, half + 1) / sigma) ** 2)
    kernel /= kernel.sum()
    padded = np.concatenate([np.repeat(values[:1], half, 0), values, np.repeat(values[-1:], half, 0)])
    out = np.zeros_like(values, dtype=float)
    for k, w in enumerate(kernel):
        out += w * padded[k:k + len(values)]
    return out


def smooth_rotations(m, sigma):
    """Blurs rotation matrices (F, ..., 3, 3) over time, then makes them
    rotations again."""
    if sigma <= 0:
        return m
    blurred = smooth(m, sigma)
    u, _, vt = np.linalg.svd(blurred)
    return u @ vt


def write_library(path, clips):
    """A Godot AnimationLibrary. clips: list of dicts with name, dt, loop,
    tracks [(path, kind, values (F, 3 or 4))], meta {name: number}."""
    out = ['[gd_resource type="AnimationLibrary" load_steps=%d format=3]\n' % (len(clips) + 1)]
    for c in clips:
        frames = max(len(values) for _, _, values in c["tracks"])
        out.append('[sub_resource type="Animation" id="%s"]' % c["name"])
        out.append('resource_name = "%s"' % c["name"])
        out.append("length = %s" % _num((frames - 1) * c["dt"]))
        if c.get("loop"):
            out.append("loop_mode = 1")
        for k, (track, kind, values) in enumerate(c["tracks"]):
            values = np.asarray(values)
            if len(values) > 1 and np.abs(values - values[0]).max() < 1e-5:
                values = values[:1]  # it never changes: one key
            keys = []
            for f, v in enumerate(values):
                keys.append(_num(f * c["dt"]))
                keys.append("1")
                keys.extend(_num(x) for x in v)
            out.append('tracks/%d/type = "%s"' % (k, kind))
            out.append("tracks/%d/imported = false" % k)
            out.append("tracks/%d/enabled = true" % k)
            out.append('tracks/%d/path = NodePath("%s")' % (k, track))
            out.append("tracks/%d/interp = 1" % k)
            out.append("tracks/%d/loop_wrap = true" % k)
            out.append("tracks/%d/keys = PackedFloat32Array(%s)" % (k, ", ".join(keys)))
        for name, value in c.get("meta", {}).items():
            out.append("metadata/%s = %s" % (name, _num(value)))
        out.append("")
    out.append("[resource]")
    out.append("_data = {")
    out.append(",\n".join('&"%s": SubResource("%s")' % (c["name"], c["name"]) for c in clips))
    out.append("}")
    open(path, "w").write("\n".join(out) + "\n")


def _num(x):
    text = "%.4f" % x
    text = text.rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text
