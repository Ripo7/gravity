"""The mannequin's skeleton, read from its glTF: bones, rest pose, and the
pose of any of its clips at a given time."""
import json
import os
import struct

import numpy as np


def quat_to_matrix(q):
    """(..., 4) quaternions x, y, z, w to (..., 3, 3)."""
    q = np.asarray(q, dtype=float)
    x, y, z, w = q[..., 0], q[..., 1], q[..., 2], q[..., 3]
    m = np.empty(q.shape[:-1] + (3, 3))
    m[..., 0, 0] = 1 - 2 * (y * y + z * z)
    m[..., 0, 1] = 2 * (x * y - z * w)
    m[..., 0, 2] = 2 * (x * z + y * w)
    m[..., 1, 0] = 2 * (x * y + z * w)
    m[..., 1, 1] = 1 - 2 * (x * x + z * z)
    m[..., 1, 2] = 2 * (y * z - x * w)
    m[..., 2, 0] = 2 * (x * z - y * w)
    m[..., 2, 1] = 2 * (y * z + x * w)
    m[..., 2, 2] = 1 - 2 * (x * x + y * y)
    return m


def matrix_to_quat(m):
    """(..., 3, 3) rotations to (..., 4) quaternions x, y, z, w."""
    m = np.asarray(m, dtype=float)
    q = np.empty(m.shape[:-2] + (4,))
    t = m[..., 0, 0] + m[..., 1, 1] + m[..., 2, 2]
    # The four branches of the usual conversion, picked per matrix.
    c0 = t > 0
    c1 = ~c0 & (m[..., 0, 0] > m[..., 1, 1]) & (m[..., 0, 0] > m[..., 2, 2])
    c2 = ~c0 & ~c1 & (m[..., 1, 1] > m[..., 2, 2])
    c3 = ~c0 & ~c1 & ~c2
    for cond, kind in ((c0, 0), (c1, 1), (c2, 2), (c3, 3)):
        if not cond.any():
            continue
        a = m[cond]
        if kind == 0:
            s = np.sqrt(a[:, 0, 0] + a[:, 1, 1] + a[:, 2, 2] + 1.0) * 2
            r = np.stack([(a[:, 2, 1] - a[:, 1, 2]) / s, (a[:, 0, 2] - a[:, 2, 0]) / s, (a[:, 1, 0] - a[:, 0, 1]) / s, 0.25 * s], -1)
        elif kind == 1:
            s = np.sqrt(1.0 + a[:, 0, 0] - a[:, 1, 1] - a[:, 2, 2]) * 2
            r = np.stack([0.25 * s, (a[:, 0, 1] + a[:, 1, 0]) / s, (a[:, 0, 2] + a[:, 2, 0]) / s, (a[:, 2, 1] - a[:, 1, 2]) / s], -1)
        elif kind == 2:
            s = np.sqrt(1.0 + a[:, 1, 1] - a[:, 0, 0] - a[:, 2, 2]) * 2
            r = np.stack([(a[:, 0, 1] + a[:, 1, 0]) / s, 0.25 * s, (a[:, 1, 2] + a[:, 2, 1]) / s, (a[:, 0, 2] - a[:, 2, 0]) / s], -1)
        else:
            s = np.sqrt(1.0 + a[:, 2, 2] - a[:, 0, 0] - a[:, 1, 1]) * 2
            r = np.stack([(a[:, 0, 2] + a[:, 2, 0]) / s, (a[:, 1, 2] + a[:, 2, 1]) / s, 0.25 * s, (a[:, 1, 0] - a[:, 0, 1]) / s], -1)
        q[cond] = r
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


class Skeleton:
    def __init__(self, path):
        self.gltf = json.load(open(path))
        self.dir = os.path.dirname(path)
        nodes = self.gltf["nodes"]
        joints = self.gltf["skins"][0]["joints"]
        parent_of = {}
        for i, n in enumerate(nodes):
            for c in n.get("children", []):
                parent_of[c] = i
        self.node = joints  # bone index -> node index
        self.names = [nodes[j]["name"] for j in joints]
        self.parents = [joints.index(parent_of[j]) if parent_of.get(j) in joints else -1 for j in joints]
        self.rest_rot = np.array([quat_to_matrix(nodes[j].get("rotation", [0, 0, 0, 1])) for j in joints])
        self.rest_pos = np.array([nodes[j].get("translation", [0, 0, 0]) for j in joints], dtype=float)
        count = len(joints)
        self.world_rot = np.empty((count, 3, 3))
        self.world_pos = np.empty((count, 3))
        for b in range(count):  # parents come before their children in this file
            p = self.parents[b]
            assert p < b
            if p < 0:
                self.world_rot[b] = self.rest_rot[b]
                self.world_pos[b] = self.rest_pos[b]
            else:
                self.world_rot[b] = self.world_rot[p] @ self.rest_rot[b]
                self.world_pos[b] = self.world_pos[p] + self.world_rot[p] @ self.rest_pos[b]
        self._bin = None

    def index(self, name):
        return self.names.index(name)

    def _accessor(self, i):
        g = self.gltf
        if self._bin is None:
            self._bin = open(os.path.join(self.dir, g["buffers"][0]["uri"]), "rb").read()
        acc = g["accessors"][i]
        view = g["bufferViews"][acc["bufferView"]]
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[acc["type"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        data = struct.unpack_from("<%df" % (acc["count"] * width), self._bin, start)
        return np.array(data).reshape(acc["count"], width)

    def clip_rotations(self, clip, time):
        """Local rotation (x, y, z, w) of every bone a clip turns, at `time`."""
        anim = next(a for a in self.gltf["animations"] if a["name"] == clip)
        out = {}
        for ch in anim["channels"]:
            if ch["target"]["path"] != "rotation" or ch["target"]["node"] not in self.node:
                continue
            s = anim["samplers"][ch["sampler"]]
            times = self._accessor(s["input"])[:, 0]
            values = self._accessor(s["output"])
            k = int(np.clip(np.searchsorted(times, time), 0, len(times) - 1))
            out[self.names[self.node.index(ch["target"]["node"])]] = values[k]
        return out
