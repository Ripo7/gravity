"""Reads a BVH motion capture file: the skeleton, and where every joint is
and how it is turned at every frame."""
import numpy as np


class Take:
    """names, parents (index, -1 for the root), offsets (J, 3), ends (J, 3:
    where a bone with no child stops), order (J: e.g. "ZYX"), root (F, 3),
    local (F, J, 3, 3), dt (seconds a frame)."""

    def __init__(self):
        self.names, self.parents, self.offsets, self.ends, self.order = [], [], [], [], []
        self.root = self.local = None
        self.dt = 1.0 / 120.0

    @property
    def frames(self):
        return self.local.shape[0]

    def index(self, name):
        return self.names.index(name)

    def world(self, frames=None):
        """World rotation (F, J, 3, 3) and position (F, J, 3) of every joint."""
        local = self.local if frames is None else self.local[frames]
        root = self.root if frames is None else self.root[frames]
        f, j = local.shape[:2]
        rot = np.empty((f, j, 3, 3))
        pos = np.empty((f, j, 3))
        for k, parent in enumerate(self.parents):
            if parent < 0:
                rot[:, k] = local[:, k]
                pos[:, k] = root
            else:
                rot[:, k] = rot[:, parent] @ local[:, k]
                pos[:, k] = pos[:, parent] + rot[:, parent] @ self.offsets[k]
        return rot, pos


def axis_rotation(axis, degrees):
    """Rotation matrices (N, 3, 3) about X, Y or Z."""
    a = np.radians(degrees)
    c, s = np.cos(a), np.sin(a)
    m = np.zeros(a.shape + (3, 3))
    i = "XYZ".index(axis)
    j, k = (i + 1) % 3, (i + 2) % 3
    m[..., i, i] = 1.0
    m[..., j, j] = c
    m[..., j, k] = -s
    m[..., k, j] = s
    m[..., k, k] = c
    return m


def load(path):
    take = Take()
    channels = []  # per joint: list of channel names
    stack = []
    with open(path) as f:
        lines = iter(f.read().split("\n"))
    for line in lines:
        words = line.split()
        if not words:
            continue
        if words[0] in ("ROOT", "JOINT"):
            take.names.append(words[1])
            take.parents.append(stack[-1] if stack else -1)
            take.ends.append(np.zeros(3))
            stack.append(len(take.names) - 1)
        elif words[0] == "End":
            stack.append(-1 - stack[-1])  # an end site: remembers whose
        elif words[0] == "OFFSET":
            offset = np.array([float(w) for w in words[1:4]])
            if stack[-1] < 0:
                take.ends[-1 - stack[-1]] = offset
            else:
                take.offsets.append(offset)
        elif words[0] == "CHANNELS":
            channels.append(words[2:])
        elif words[0] == "}":
            stack.pop()
        elif words[0] == "MOTION":
            break
    frames = int(next(lines).split()[1])
    take.dt = float(next(lines).split()[2])
    data = np.array([[float(w) for w in next(lines).split()] for _ in range(frames)])
    take.offsets = np.array(take.offsets)
    take.ends = np.array(take.ends)
    joints = len(take.names)
    take.local = np.empty((frames, joints, 3, 3))
    column = 0
    for k in range(joints):
        m = np.broadcast_to(np.eye(3), (frames, 3, 3)).copy()
        order = ""
        for name in channels[k]:
            if name.endswith("position"):
                if take.root is None:
                    take.root = np.zeros((frames, 3))
                take.root[:, "XYZ".index(name[0])] = data[:, column]
            else:
                m = m @ axis_rotation(name[0], data[:, column])
                order += name[0]
            column += 1
        take.local[:, k] = m
        take.order.append(order)
    return take
