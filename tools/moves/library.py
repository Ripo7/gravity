"""Reads clips out of Quaternius's Universal Animation Libraries (.glb,
.gltf), and makes a blow of one fist a blow of both (`joined`).

Its skeleton is the mannequin's own, bone for bone and at rest, under other
names (and with a leaf at the end of each finger and toe that the mannequin
does not have): a clip is taken over as it is, each track given to the bone
of the same place. Nothing is retargeted."""
import json
import struct

import numpy as np

from retarget import between
from skeleton import matrix_to_quat, quat_to_matrix

PLAIN = {
    "root": "root",
    "pelvis": "DEF-hips",
    "spine_01": "DEF-spine.001",
    "spine_02": "DEF-spine.002",
    "spine_03": "DEF-spine.003",
    "neck_01": "DEF-neck",
    "Head": "DEF-head",
}
LIMBS = {
    "clavicle": "shoulder",
    "upperarm": "upper_arm",
    "lowerarm": "forearm",
    "hand": "hand",
    "thigh": "thigh",
    "calf": "shin",
    "foot": "foot",
    "ball": "toe",
}
FINGERS = ("index", "middle", "ring", "pinky", "thumb")


def bone_of(joint):
    """The mannequin's bone for a joint of the library (None: it has none)."""
    if joint in PLAIN:
        return PLAIN[joint]
    if joint.startswith("DEF-"):
        return joint  # the first library: the mannequin's own names
    side = {"_l": ".L", "_r": ".R"}.get(joint[-2:])
    if side is None:
        return None
    stem = joint[:-2]
    if stem in LIMBS:
        return "DEF-%s%s" % (LIMBS[stem], side)
    finger, _, knuckle = stem.partition("_")
    if finger in FINGERS and knuckle in ("01", "02", "03"):
        return "DEF-%s%s.%s%s" % ("" if finger == "thumb" else "f_", finger, knuckle, side)
    return None


class Library:
    def __init__(self, path):
        if path.endswith(".gltf"):
            # The first library: the document, and its data beside it.
            import os
            with open(path) as f:
                self.doc = json.load(f)
            with open(os.path.join(os.path.dirname(path), self.doc["buffers"][0]["uri"]), "rb") as f:
                self.bin = f.read()
            return
        with open(path, "rb") as f:
            magic, _, _ = struct.unpack("<4sII", f.read(12))
            assert magic == b"glTF", path
            size, _ = struct.unpack("<I4s", f.read(8))
            self.doc = json.loads(f.read(size))
            rest = f.read()
        size, _ = struct.unpack("<I4s", rest[:8])
        self.bin = rest[8:8 + size]

    def _accessor(self, i):
        acc = self.doc["accessors"][i]
        view = self.doc["bufferViews"][acc["bufferView"]]
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[acc["type"]]
        assert acc["componentType"] == 5126 and not view.get("byteStride")
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        data = np.frombuffer(self.bin, "<f4", acc["count"] * width, start)
        return data.reshape(acc["count"], width).astype(float)

    def clip(self, name, fps, t0=0.0, t1=None):
        """Clip `name` from t0 to t1 s, sampled `fps` times a second: for
        each bone it moves, its rotation in its parent (F, 4: x, y, z, w),
        and the place of "root" and of "DEF-hips" (F, 3)."""
        anim = next(a for a in self.doc["animations"] if a["name"] == name)
        length = max(self.doc["accessors"][s["input"]]["max"][0] for s in anim["samplers"])
        t1 = length if t1 is None else t1
        times = t0 + np.arange(0, int(round((t1 - t0) * fps)) + 1) / fps
        turns, places = {}, {}
        for ch in anim["channels"]:
            bone = bone_of(self.doc["nodes"][ch["target"]["node"]]["name"])
            path = ch["target"]["path"]
            if bone is None or path == "scale":
                continue
            if path == "translation" and bone not in ("root", "DEF-hips"):
                continue
            sampler = anim["samplers"][ch["sampler"]]
            t, v = self._accessor(sampler["input"])[:, 0], self._accessor(sampler["output"])
            lo = np.clip(np.searchsorted(t, times + 1e-6) - 1, 0, len(t) - 1)
            hi = np.minimum(lo + 1, len(t) - 1)
            w = np.where(t[hi] > t[lo], (times - t[lo]) / np.maximum(t[hi] - t[lo], 1e-9), 0.0)[:, None]
            a, b = v[lo], v[hi].copy()
            if path == "rotation":
                b[(a * b).sum(-1) < 0] *= -1
            out = a * (1 - w) + b * w
            if path == "rotation":
                out /= np.linalg.norm(out, axis=-1, keepdims=True)
                turns[bone] = out
            else:
                places[bone] = out
        return turns, places


def join(parts):
    """Several (turns, places) one after the other: the first frame of each
    is the last of the one before, and it goes on from where that one is."""
    turns, places = {k: v.copy() for k, v in parts[0][0].items()}, {k: v.copy() for k, v in parts[0][1].items()}
    for more_turns, more_places in parts[1:]:
        for bone in turns:
            more = more_turns[bone][1:].copy()
            more[(more * turns[bone][-1]).sum(-1) < 0] *= -1
            turns[bone] = np.concatenate([turns[bone], more])
        for bone in places:
            more = more_places[bone][1:]
            if bone == "root":
                more = more - more_places[bone][0] + places[bone][-1]
            places[bone] = np.concatenate([places[bone], more])
    return turns, places


def poses(skel, turns, places):
    """How every bone is turned (F, B, 3, 3) and where it is (F, B, 3),
    seen from the body: from "root" at rest, in the mannequin's space (+Z
    ahead, +X to its left)."""
    frames = len(next(iter(turns.values())))
    rot = np.empty((frames, len(skel.names), 3, 3))
    pos = np.empty((frames, len(skel.names), 3))
    for b, name in enumerate(skel.names):
        local = np.array([quat_to_matrix(q) for q in turns[name]]) if name in turns else np.broadcast_to(skel.rest_rot[b], (frames, 3, 3))
        at = places[name] if name == "DEF-hips" and name in places else np.broadcast_to(skel.rest_pos[b], (frames, 3))
        p = skel.parents[b]
        if p < 0:
            rot[:, b], pos[:, b] = local, at
        else:
            rot[:, b] = rot[:, p] @ local
            pos[:, b] = pos[:, p] + np.einsum("fij,fj->fi", rot[:, p], at)
    return rot, pos


def positions(skel, turns, places):
    """Where every bone is (F, B, 3), seen from the body."""
    return poses(skel, turns, places)[1]


TRUNK = ("DEF-spine.001", "DEF-spine.002", "DEF-spine.003", "DEF-neck", "DEF-head")
MIRROR = np.diag([-1.0, 1.0, 1.0])


def joined(skel, turns, places, fist, apart):
    """A blow of the right hand, made a blow of both fists side by side:

    - the trunk no longer twists or tilts: it only leans, as much as it did;
    - the right arm does to the trunk what it did, then swings about its
      shoulder until its wrist is `apart` m to the right of the middle of
      the chest;
    - the left arm is the mirror image of the right;
    - both hands are fists (`fist`: the turn of every finger bone), the
      wrists straight.

    The pelvis and the legs are left as they are. Returns the turns."""
    rot, _ = poses(skel, turns, places)
    frames, index = len(rot), skel.index
    new = rot.copy()
    for name in TRUNK:
        b = index(name)
        lean = matrix_to_quat(rot[:, b] @ skel.world_rot[b].T)
        lean[:, 1:3] = 0.0  # (what is left is the turn about the axis from side to side)
        lean /= np.linalg.norm(lean, axis=-1, keepdims=True)
        new[:, b] = quat_to_matrix(lean) @ skel.world_rot[b]
    arm = [b for b, name in enumerate(skel.names) if name.endswith(".R") and _under(skel, b, index("DEF-shoulder.R"))]
    for b in arm:
        name, p = skel.names[b], skel.parents[b]
        if name in fist:
            local = quat_to_matrix(np.asarray(fist[name], dtype=float))
        elif name == "DEF-hand.R":
            local = skel.rest_rot[b]
        else:
            local = np.einsum("fji,fjk->fik", rot[:, p], rot[:, b])
        new[:, b] = new[:, p] @ local
    at = _places(skel, new, places)
    shoulder, wrist, chest = index("DEF-upper_arm.R"), index("DEF-hand.R"), index("DEF-spine.003")
    for f in range(frames):
        reach = at[f, wrist] - at[f, shoulder]
        length = np.linalg.norm(reach)
        aside = float(np.clip(at[f, chest, 0] - apart - at[f, shoulder, 0], -0.95 * length, 0.95 * length))
        there = reach.copy()
        there[0] = aside
        there[1:] *= np.sqrt(length * length - aside * aside) / max(np.linalg.norm(reach[1:]), 1e-9)
        swing = between(reach, there)
        for b in arm:
            if b != index("DEF-shoulder.R"):
                new[f, b] = swing @ new[f, b]
    for b in arm:
        other = index(skel.names[b][:-1] + "L")
        new[:, other] = MIRROR @ new[:, b] @ skel.world_rot[b].T @ MIRROR @ skel.world_rot[other]
    out = {}
    for b, name in enumerate(skel.names):
        p = skel.parents[b]
        if p < 0:
            continue
        quats = matrix_to_quat(np.einsum("fji,fjk->fik", new[:, p], new[:, b]))
        for f in range(1, frames):
            if quats[f] @ quats[f - 1] < 0:
                quats[f] *= -1
        out[name] = quats
    for name in turns:
        out.setdefault(name, turns[name])
    return out


def _under(skel, b, top):
    while b >= 0:
        if b == top:
            return True
        b = skel.parents[b]
    return False


def _places(skel, rot, places):
    """Where every bone is, from how each is turned."""
    pos = np.empty(rot.shape[:2] + (3,))
    for b, name in enumerate(skel.names):
        at = places[name] if name == "DEF-hips" and name in places else np.broadcast_to(skel.rest_pos[b], (len(rot), 3))
        p = skel.parents[b]
        pos[:, b] = at if p < 0 else pos[:, p] + np.einsum("fij,fj->fi", rot[:, p], at)
    return pos
