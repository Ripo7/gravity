#!/usr/bin/env python3
"""Builds assets/boxing/boxing.tres: the boxing moves, cut out of CMU motion
capture takes and put on the mannequin.

    python3 tools/mocap/build.py <dir of the CMU BVH files> [out.tres]

The takes come from the CMU Graphics Lab Motion Capture Database, in Bruce
Hahne's BVH conversion (one mirror: github.com/una-dinosauria/cmu-mocap,
files data/013/13_17.bvh and data/135/135_07.bvh). See
assets/boxing/SOURCE.md.

Every clip starts with the pelvis over the origin, the opponent along +Z
(where the mannequin looks). The steps of a move are given to the bone
"root" (the game moves the body by it, so the feet stay where they are
put); what is left is the pose. Each clip carries, as metadata, the
moment its fist or foot gets there ("hit"), the moment the next move may
start ("next"), how far from the body that fist or foot is then
("reach"), and how hard it is ("power").
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bvh  # noqa: E402
import retarget as rt  # noqa: E402
from skeleton import Skeleton, matrix_to_quat  # noqa: E402

MANNEQUIN = os.path.join(os.path.dirname(__file__), "../../assets/mannequin/AnimationLibrary_Godot_Standard.gltf")
FPS = 60
# Blur (s) that takes the trembling out of the capture, and the one that
# separates the steps (given to the root) from the sway (left in the pose).
CALM = 0.012
STEPS = 0.12
ANKLE = 0.10  # m: how high the ankle of a foot flat on the ground is
FOOT = 0.15  # m: from the ankle to the ball of the foot

# name, take, from, to (s in the take), then:
#   hit: when the fist or foot is there; limb: which one; next: when the
#   next move may start; power: 1 a jab, 2 a hard punch, 3 a kick
#   with: another strike of the same passage, to tell where the opponent is
#   steps: the root takes the steps (else the clip stays where it is)
#   loop: the end is made to run into the start
CLIPS = [
    dict(name="guard", take="13_17", t0=23.0, t1=27.5, loop=(0.9, 1.9)),
    dict(name="jab", take="13_17", t0=2.87, t1=3.14, hit=3.03, limb="LeftHand", next=3.10, power=1,
         with_=("RightHand", 3.25), steps=True),
    dict(name="cross", take="13_17", t0=3.10, t1=3.62, hit=3.25, limb="RightHand", next=3.42, power=2,
         with_=("LeftHand", 3.03), steps=True),
    dict(name="hook_l", take="13_17", t0=20.24, t1=20.58, hit=20.45, limb="LeftHand", next=20.52, power=2,
         with_=("RightHand", 20.72), steps=True),
    dict(name="hook_r", take="13_17", t0=20.52, t1=21.00, hit=20.72, limb="RightHand", next=20.86, power=2,
         with_=("LeftHand", 20.45), steps=True),
    dict(name="duck", take="13_17", t0=11.62, t1=12.40, low=11.96),
    dict(name="kick", take="135_07", t0=0.45, t1=1.30, hit=1.00, limb="RightFoot", next=1.25, power=3),
]


def angle(v):
    """Heading of a ground direction: 0 along +Z, growing towards +X."""
    return np.arctan2(v[0], v[2])


class Capture:
    """A take on the mannequin, at FPS frames a second, calmed."""

    def __init__(self, path, skel, fist):
        take = bvh.load(path)
        self.skel = skel
        self.step = int(round(1.0 / (FPS * take.dt)))
        # (not frame 0: the T pose everything is measured from)
        take.local[1:] = rt.smooth_rotations(take.local[1:], CALM / take.dt)
        take.root[1:] = rt.smooth(take.root[1:], CALM / take.dt)
        frames = np.arange(1, take.frames, self.step)  # frame 0 is the T pose
        self.time = frames * take.dt
        self.motion = rt.retarget(take, skel, frames, fist)
        self.pos = self.motion.positions()
        feet = np.minimum(self.pos[:, skel.index("DEF-foot.L"), 1], self.pos[:, skel.index("DEF-foot.R"), 1])
        lift = ANKLE - np.percentile(feet, 10)
        self.motion.hips[:, 1] += lift
        self.pos[:, :, 1] += lift
        ground = self.motion.hips * [1, 0, 1]
        self.walk = rt.smooth(ground, STEPS * FPS)  # where the body is, without its sway
        hips = skel.index("DEF-hips")
        ahead = self.motion.world[:, hips] @ skel.world_rot[hips].T @ np.array([0, 0, 1.0])
        self.hips_yaw = np.unwrap(np.arctan2(ahead[:, 0], ahead[:, 2]))
        self.hips_yaw = rt.smooth(self.hips_yaw[:, None], 0.25 * FPS)[:, 0]

    def frame(self, t):
        return int(np.clip(round((t - self.time[0]) * FPS), 0, len(self.time) - 1))

    def towards(self, limb, t):
        """Heading from the body to a hand or foot at time t."""
        bone = {"LeftHand": "DEF-hand.L", "RightHand": "DEF-hand.R", "RightFoot": "DEF-foot.R", "LeftFoot": "DEF-foot.L"}[limb]
        f = self.frame(t)
        return angle(self.pos[f, self.skel.index(bone)] - self.walk[f])


def mean_angle(angles):
    return np.arctan2(np.mean(np.sin(angles)), np.mean(np.cos(angles)))


def best_loop(cap, a, b, shortest, longest):
    """The two frames between times a and b, shortest to longest seconds
    apart, where the body is most alike (pose and speed): a loop."""
    s = cap.skel
    fa, fb = cap.frame(a), cap.frame(b)
    idx = np.arange(fa, fb)
    # joints seen from the body: turned by its heading, placed on its walk
    local = np.empty((len(idx), len(s.names), 3))
    for k, f in enumerate(idx):
        local[k] = (cap.pos[f] - cap.walk[f]) @ rt.turn_y(-cap.hips_yaw[f]).T
    speed = np.gradient(local, axis=0) * FPS
    best = (np.inf, 0, 0)
    for i in range(0, len(idx) - int(shortest * FPS)):
        for j in range(i + int(shortest * FPS), min(i + int(longest * FPS), len(idx))):
            d = np.linalg.norm(local[i] - local[j], axis=1).mean() + 0.08 * np.linalg.norm(speed[i] - speed[j], axis=1).mean()
            # a loop that goes nowhere: the walk comes back to where it was
            d += 0.3 * np.linalg.norm(cap.walk[idx[i]] - cap.walk[idx[j]])
            if d < best[0]:
                best = (d, idx[i], idx[j])
    return best


def build(cap, spec, offset):
    """One clip: tracks and metadata. `offset`: what to add to the heading
    of the hips to get where the opponent is, for clips with no strike."""
    s = cap.skel
    f0, f1 = cap.frame(spec["t0"]), cap.frame(spec["t1"])
    if "loop" in spec:
        _, f0, f1 = best_loop(cap, spec["t0"], spec["t1"], *spec["loop"])
    frames = np.arange(f0, f1 + 1)
    if "hit" in spec:
        headings = [cap.towards(spec["limb"], spec["hit"])]
        if "with_" in spec:
            headings.append(cap.towards(*spec["with_"]))
        heading = mean_angle(headings)
    else:
        heading = cap.hips_yaw[f0] + offset
    turn = rt.turn_y(-heading)
    root = s.index("root")
    world = turn @ cap.motion.world[frames]
    world[:, root] = s.world_rot[root]  # the root does not turn: the body on it does
    hips = (cap.motion.hips[frames] - cap.walk[f0]) @ turn.T
    walk = (cap.walk[frames] - cap.walk[f0]) @ turn.T
    if not spec.get("steps"):
        if "loop" in spec:
            hips = hips - walk  # only the sway is kept
        walk = np.zeros_like(walk)
    hips = hips - walk
    quats = matrix_to_quat(rt.Motion(s, world, hips).local())
    for f in range(1, len(quats)):
        flip = (quats[f] * quats[f - 1]).sum(-1) < 0
        quats[f][flip] *= -1
    if "loop" in spec:
        # The last frames slide into what came before the first.
        n = min(int(0.3 * FPS), f0)
        before = np.arange(f0 - n, f0)
        w_b = turn @ cap.motion.world[before]
        w_b[:, root] = s.world_rot[root]
        h_b = (cap.motion.hips[before] - cap.walk[before]) @ turn.T
        q_b = matrix_to_quat(rt.Motion(s, w_b, h_b).local())
        for k in range(n):
            t = (k + 1) / (n + 1)
            t = t * t * (3 - 2 * t)
            f = len(frames) - n + k
            qb = q_b[k].copy()
            qb[(qb * quats[f]).sum(-1) < 0] *= -1
            mixed = quats[f] * (1 - t) + qb * t
            quats[f] = mixed / np.linalg.norm(mixed, axis=-1, keepdims=True)
            hips[f] = hips[f] * (1 - t) + h_b[k] * t
        # and the heading at the end is the one at the start: the loop does not turn
    root0 = s.world_rot[s.index("root")]
    tracks = []
    if spec.get("steps"):
        tracks.append(("Rig/Skeleton3D:root", "position_3d", walk))
    tracks.append(("Rig/Skeleton3D:DEF-hips", "position_3d", hips @ root0))
    for b, bone in enumerate(s.names):
        if bone != "root":
            tracks.append(("Rig/Skeleton3D:%s" % bone, "rotation_3d", quats[:, b]))
    meta = {}
    if "hit" in spec:
        fh = cap.frame(spec["hit"])
        bone = {"LeftHand": "DEF-hand.L", "RightHand": "DEF-hand.R", "RightFoot": "DEF-foot.R"}[spec["limb"]]
        at = (cap.pos[fh, s.index(bone)] - cap.walk[fh]) @ turn.T
        # (to the wrist; for a kick, to the ball of the foot: FOOT past the ankle)
        reach = float(np.hypot(at[0], at[2])) + (FOOT if spec["limb"].endswith("Foot") else 0.0)
        meta.update(hit=(fh - f0) / FPS, next=(cap.frame(spec["next"]) - f0) / FPS, power=spec["power"],
                    reach=reach, height=float(at[1]), aside=float(at[0]))
        meta["travel"] = float(walk[fh - f0, 2]) if spec.get("steps") else 0.0
    if "low" in spec:
        meta["low"] = (cap.frame(spec["low"]) - f0) / FPS
    return {"name": spec["name"], "dt": 1.0 / FPS, "tracks": tracks, "meta": meta, "loop": "loop" in spec}, heading, (f0, f1), walk


def main():
    data = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "../../assets/boxing/boxing.tres")
    skel = Skeleton(MANNEQUIN)
    fist = {k: v for k, v in skel.clip_rotations("Punch_Jab", 0.0).items() if "f_" in k or "thumb" in k}
    captures = {}
    for spec in CLIPS:
        if spec["take"] not in captures:
            subject = spec["take"].split("_")[0]
            captures[spec["take"]] = Capture(os.path.join(data, "%03d" % int(subject), spec["take"] + ".bvh"), skel, fist)
    # How the hips are turned away from the opponent at the start of the punches.
    offsets = []
    for spec in CLIPS:
        if "hit" in spec and spec["limb"].endswith("Hand"):
            cap = captures[spec["take"]]
            heading = mean_angle([cap.towards(spec["limb"], spec["hit"]), cap.towards(*spec["with_"])])
            offsets.append(heading - cap.hips_yaw[cap.frame(spec["t0"])])
    offset = mean_angle(np.array(offsets))
    clips = []
    for spec in CLIPS:
        cap = captures[spec["take"]]
        clip, heading, (f0, f1), walk = build(cap, spec, offset)
        clips.append(clip)
        meta = clip["meta"]
        print("%-7s %s %.2f-%.2f s (%.2f s)  opponent at %4.0f deg  walks %+.2f m ahead, %+.2f aside  %s" % (
            spec["name"], spec["take"], cap.time[f0], cap.time[f1], (f1 - f0) / FPS, np.degrees(heading),
            walk[-1, 2], walk[-1, 0], "  ".join("%s %.2f" % kv for kv in meta.items())))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    rt.write_library(out, clips)
    print("wrote %s (%.0f kB)" % (out, os.path.getsize(out) / 1000))


if __name__ == "__main__":
    main()
