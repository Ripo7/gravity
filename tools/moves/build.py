#!/usr/bin/env python3
"""Builds assets/fight/moves.tres: the fighting moves of the brutes.

    python3 tools/moves/build.py <dir of the CMU BVH files> <dir of the UAL2 .glb files> [out.tres]

Two kinds of clips, in one library:

- MADE: animations made for games, from Quaternius's Universal Animation
  Library 2 (CC0). Its skeleton is the mannequin's, so they are taken over
  as they are (library.py): cut, joined end to end, measured.
- CLIPS: motion capture, from the CMU Graphics Lab Motion Capture Database
  in Bruce Hahne's BVH conversion, put on the mannequin (retarget.py) and
  retimed.

Where the files come from, which clips and which seconds of them:
assets/fight/SOURCE.md.

Every clip starts with the pelvis over the origin, the opponent along +Z
(where the mannequin looks). The steps of a move are given to the bone
"root" (the game moves the body by it, so the feet stay where they are
put); what is left is the pose. Each strike carries, as metadata, the
moment its fist or foot gets there ("hit"), the moment the next move may
start ("next"), how far from the body that fist or foot is then
("reach"), how high ("height"), which way it is going ("way_x", "way_y",
"way_z") and how hard it is ("power").
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bvh  # noqa: E402
import library  # noqa: E402
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

# A blow reads as heavy when it is slow to come and sudden when it does:
# the last SNAP s before it lands take QUICK of the time they took, and the
# SETTLE s after it LINGERS times as long (the pose is all but held).
SNAP = 0.12
QUICK = 0.65
SETTLE = 0.06
LINGERS = 2.5

# name, take, from, to (s in the take), then:
#   hit: when the fist or foot is there; limb: which one; next: when the
#   next move may start; power: 2 a blow, 3 one that throws
#   slow: how much longer the wind-up and the recovery take than performed
#   (the blow itself is retimed the same way for all, see SNAP)
#   steps: the root takes the steps (else the clip stays where it is)
CLIPS = [
    # A karateka's front kick, stepping in.
    dict(name="kick", take="135_04", t0=2.62, t1=3.30, hit=3.11, limb="RightFoot", next=3.26, power=3,
         slow=(1.2, 1.3), steps=True),
]


# The clips made for games. name, the file (without .glb: "_RM" has the
# steps on the root, the other stays in place), then:
#   parts: the clips of the file it is made of, end to end; each one a
#   name, and from when to when (s) if not the whole of it
#   hit, next: s into the result (hit on one of its 30 frames a second:
#   the fist goes a long way between two); limb, power, steps: as above
#   still: only its last pose, held
# The blows are sword strokes, thrown without the sword: A, B and the
# last of the heavy ones, each with the recovery that follows it when no
# other blow does.
MADE_FPS = 30
MADE = [
    # A lunging hook: the one blow of the set that was made as a punch.
    dict(name="hook", glb="UAL2_Standard_RM", parts=[("Melee_Hook",), ("Melee_Hook_Rec",)],
         hit=8 / 30, limb="RightHand", next=0.47, power=2, steps=True),
    # Dashing in, a swing from low on the right to high on the left.
    dict(name="upswing", glb="UAL2_Standard_RM", parts=[("Sword_Regular_A",), ("Sword_Regular_A_Rec",)],
         hit=7 / 30, limb="RightHand", next=0.43, power=2, steps=True),
    # Back across, from the left to the right.
    dict(name="backhand", glb="UAL2_Standard_RM", parts=[("Sword_Regular_B",), ("Sword_Regular_B_Rec",)],
         hit=7 / 30, limb="RightHand", next=0.53, power=2, steps=True),
    # A leap, the fist straight up, and down to the ground.
    dict(name="slam", glb="UAL2_Standard_RM", parts=[("Sword_Heavy_Combo", 2.1, 3.8)],
         hit=15 / 30, limb="RightHand", next=1.1, power=3, steps=True),
    # The guard: both fists up in front of the face, where the hook's
    # recovery ends.
    dict(name="guard", glb="UAL2_Standard", parts=[("Melee_Hook_Rec",)], still=True),
    # Knocked off its feet: over backwards, onto its back.
    dict(name="thrown", glb="UAL2_Standard", parts=[("Hit_Knockback",)]),
    # From lying on its back to standing.
    dict(name="getup", glb="UAL2_Standard", parts=[("LayToIdle",)]),
]
LIMBS = {"LeftHand": "DEF-hand.L", "RightHand": "DEF-hand.R", "RightFoot": "DEF-foot.R", "LeftFoot": "DEF-foot.L"}


def made(lib, skel, spec):
    """One clip made of clips of the library: tracks and metadata."""
    turns, places = library.join([lib.clip(part[0], MADE_FPS, *part[1:]) for part in spec["parts"]])
    if spec.get("still"):
        turns = {bone: np.repeat(v[-1:], 2, axis=0) for bone, v in turns.items()}
        places = {bone: np.repeat(v[-1:], 2, axis=0) for bone, v in places.items()}
    walk = places["root"] - places["root"][0]
    tracks = []
    if spec.get("steps"):
        tracks.append(("Rig/Skeleton3D:root", "position_3d", walk))
    tracks.append(("Rig/Skeleton3D:DEF-hips", "position_3d", places["DEF-hips"]))
    for bone in skel.names:
        if bone != "root" and bone in turns:
            tracks.append(("Rig/Skeleton3D:%s" % bone, "rotation_3d", turns[bone]))
    meta = {}
    if "hit" in spec:
        limb = library.positions(skel, turns, places)[:, skel.index(LIMBS[spec["limb"]])]
        frames = np.arange(len(limb), dtype=float)

        def where(t):
            return np.array([np.interp(t * MADE_FPS, frames, limb[:, k]) for k in range(3)])

        at = where(spec["hit"])
        going = where(spec["hit"] + 0.5 / MADE_FPS) - where(spec["hit"] - 0.5 / MADE_FPS)
        going /= max(np.linalg.norm(going), 1e-6)
        meta.update(hit=spec["hit"], next=spec["next"], power=spec["power"],
                    reach=float(np.hypot(at[0], at[2])), height=float(at[1]), aside=float(at[0]),
                    way_x=float(going[0]), way_y=float(going[1]), way_z=float(going[2]))
    still = bool(spec.get("still"))
    clip = {"name": spec["name"], "dt": 1.0 / MADE_FPS, "tracks": tracks, "meta": meta, "loop": still}
    return clip, walk


def warp(count, hit, before, after):
    """Retimes a strike of `count` frames whose blow lands at frame `hit`:
    the wind-up takes `before` times as long, the last stretch is quick, the
    contact lingers, the recovery takes `after` times as long. Returns, for
    every frame of the new clip, where it is in the original (a fraction of
    a frame), and what tells where a frame of the original ends up."""
    marks = np.array([0.0, max(hit - SNAP * FPS, 0.0), hit, min(hit + SETTLE * FPS, count - 1.0), count - 1.0])
    ends = np.concatenate([[0.0], np.cumsum(np.diff(marks) * [before, QUICK, LINGERS, after])])
    t = np.arange(0, int(round(ends[-1])) + 1, dtype=float)
    return np.interp(t, ends, marks), lambda frame: float(np.interp(frame, marks, ends))


def resample(values, src):
    """`values` (F, ...) at the fractional frames `src`."""
    lo = np.floor(src).astype(int)
    hi = np.minimum(lo + 1, len(values) - 1)
    w = (src - lo).reshape((-1,) + (1,) * (values.ndim - 1))
    return values[lo] * (1 - w) + values[hi] * w


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

    def frame(self, t):
        return int(np.clip(round((t - self.time[0]) * FPS), 0, len(self.time) - 1))

    def towards(self, limb, t):
        """Heading from the body to a hand or foot at time t."""
        bone = LIMBS[limb]
        f = self.frame(t)
        return angle(self.pos[f, self.skel.index(bone)] - self.walk[f])


def build(cap, spec):
    """One clip: tracks and metadata."""
    s = cap.skel
    f0, f1 = cap.frame(spec["t0"]), cap.frame(spec["t1"])
    frames = np.arange(f0, f1 + 1)
    # The opponent is where the fist or foot goes.
    heading = cap.towards(spec["limb"], spec["hit"])
    turn = rt.turn_y(-heading)
    root = s.index("root")
    world = turn @ cap.motion.world[frames]
    world[:, root] = s.world_rot[root]  # the root does not turn: the body on it does
    hips = (cap.motion.hips[frames] - cap.walk[f0]) @ turn.T
    walk = (cap.walk[frames] - cap.walk[f0]) @ turn.T
    if not spec.get("steps"):
        walk = np.zeros_like(walk)
    hips = hips - walk
    quats = matrix_to_quat(rt.Motion(s, world, hips).local())
    for f in range(1, len(quats)):
        flip = (quats[f] * quats[f - 1]).sum(-1) < 0
        quats[f][flip] *= -1
    src, slowed = warp(len(frames), cap.frame(spec["hit"]) - f0, *spec["slow"])
    quats = resample(quats, src)
    quats /= np.linalg.norm(quats, axis=-1, keepdims=True)
    hips = resample(hips, src)
    walk = resample(walk, src)
    root0 = s.world_rot[s.index("root")]
    tracks = []
    if spec.get("steps"):
        tracks.append(("Rig/Skeleton3D:root", "position_3d", walk))
    tracks.append(("Rig/Skeleton3D:DEF-hips", "position_3d", hips @ root0))
    for b, bone in enumerate(s.names):
        if bone != "root":
            tracks.append(("Rig/Skeleton3D:%s" % bone, "rotation_3d", quats[:, b]))
    fh = cap.frame(spec["hit"])
    bone = LIMBS[spec["limb"]]
    at = (cap.pos[fh, s.index(bone)] - cap.walk[fh]) @ turn.T
    # (to the wrist; for a kick, to the ball of the foot: FOOT past the ankle)
    reach = float(np.hypot(at[0], at[2])) + (FOOT if spec["limb"].endswith("Foot") else 0.0)
    # Which way the fist or foot is going when it gets there (x aside, y up, z ahead).
    going = (cap.pos[fh, s.index(bone)] - cap.pos[max(fh - 3, 0), s.index(bone)]) @ turn.T
    going /= max(np.linalg.norm(going), 1e-6)
    meta = dict(hit=slowed(fh - f0) / FPS, next=slowed(cap.frame(spec["next"]) - f0) / FPS,
                power=spec["power"], reach=reach, height=float(at[1]), aside=float(at[0]),
                way_x=float(going[0]), way_y=float(going[1]), way_z=float(going[2]))
    return {"name": spec["name"], "dt": 1.0 / FPS, "tracks": tracks, "meta": meta, "loop": False}, heading, (f0, f1), walk


def main():
    data, games = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(__file__), "../../assets/fight/moves.tres")
    skel = Skeleton(MANNEQUIN)
    fist = {k: v for k, v in skel.clip_rotations("Punch_Jab", 0.0).items() if "f_" in k or "thumb" in k}
    captures = {}
    for spec in CLIPS:
        if spec["take"] not in captures:
            subject = spec["take"].split("_")[0]
            captures[spec["take"]] = Capture(os.path.join(data, "%03d" % int(subject), spec["take"] + ".bvh"), skel, fist)
    clips = []
    libraries = {}
    for spec in MADE:
        if spec["glb"] not in libraries:
            libraries[spec["glb"]] = library.Library(os.path.join(games, spec["glb"] + ".glb"))
        clip, walk = made(libraries[spec["glb"]], skel, spec)
        clips.append(clip)
        length = (max(len(v) for _, _, v in clip["tracks"]) - 1) / MADE_FPS
        print("%-8s %s (plays %.2f s)  walks %+.2f m ahead, %+.2f aside  %s" % (
            spec["name"], " + ".join(part[0] for part in spec["parts"]), length, walk[-1, 2], walk[-1, 0],
            "  ".join("%s %.2f" % kv for kv in clip["meta"].items())))
    for spec in CLIPS:
        cap = captures[spec["take"]]
        clip, heading, (f0, f1), walk = build(cap, spec)
        clips.append(clip)
        meta = clip["meta"]
        length = (max(len(v) for _, _, v in clip["tracks"]) - 1) / FPS
        print("%-8s %s %.2f-%.2f s (plays %.2f s)  opponent at %4.0f deg  walks %+.2f m ahead, %+.2f aside  %s" % (
            spec["name"], spec["take"], cap.time[f0], cap.time[f1], length, np.degrees(heading),
            walk[-1, 2], walk[-1, 0], "  ".join("%s %.2f" % kv for kv in meta.items())))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    rt.write_library(out, clips)
    print("wrote %s (%.0f kB)" % (out, os.path.getsize(out) / 1000))


if __name__ == "__main__":
    main()
