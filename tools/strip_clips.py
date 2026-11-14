#!/usr/bin/env python3
"""Keeps only the animation clips the game uses in the mannequin's glTF.

    python3 tools/strip_clips.py assets/mannequin/AnimationLibrary_Godot_Standard.gltf

The library comes with 46 clips; the game plays 10 of them and the mocap
tool reads one more. The others were two thirds of the file. This rewrites
the .gltf and its .bin in place without them: clips, then the accessors
and the stretches of the buffer nothing refers to any more. To get a clip
back, start again from the original (assets/mannequin/SOURCE.md says where
it is) and add its name to KEEP.
"""
import json
import os
import sys

# As named in the file (Godot drops the "_Loop").
KEEP = [
    "Idle_Loop",
    "Walk_Loop",
    "Jog_Fwd_Loop",
    "Sprint_Loop",
    "Jump_Start",
    "Jump_Loop",
    "Jump_Land",
    "Hit_Chest",
    "Hit_Head",
    "Death01",
    "Punch_Jab",  # not played: tools/mocap takes the closed fist from it
]


def main():
    path = sys.argv[1]
    g = json.load(open(path))
    bin_path = os.path.join(os.path.dirname(path), g["buffers"][0]["uri"])
    data = open(bin_path, "rb").read()
    before = (os.path.getsize(path), len(data), len(g["animations"]))
    missing = set(KEEP) - {a["name"] for a in g["animations"]}
    if missing:
        sys.exit("not in the file: %s" % ", ".join(sorted(missing)))
    g["animations"] = [a for a in g["animations"] if a["name"] in KEEP]

    # The accessors still referred to, in their old order.
    used = set()
    for mesh in g.get("meshes", []):
        for prim in mesh["primitives"]:
            used.update(prim["attributes"].values())
            if "indices" in prim:
                used.add(prim["indices"])
            for target in prim.get("targets", []):
                used.update(target.values())
    for skin in g.get("skins", []):
        if "inverseBindMatrices" in skin:
            used.add(skin["inverseBindMatrices"])
    for anim in g["animations"]:
        for sampler in anim["samplers"]:
            used.update((sampler["input"], sampler["output"]))
    new_acc = {old: new for new, old in enumerate(sorted(used))}
    g["accessors"] = [g["accessors"][old] for old in sorted(used)]
    for mesh in g.get("meshes", []):
        for prim in mesh["primitives"]:
            prim["attributes"] = {k: new_acc[v] for k, v in prim["attributes"].items()}
            if "indices" in prim:
                prim["indices"] = new_acc[prim["indices"]]
            for target in prim.get("targets", []):
                for k in target:
                    target[k] = new_acc[target[k]]
    for skin in g.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = new_acc[skin["inverseBindMatrices"]]
    for anim in g["animations"]:
        for sampler in anim["samplers"]:
            sampler["input"] = new_acc[sampler["input"]]
            sampler["output"] = new_acc[sampler["output"]]

    # The stretches of the buffer still referred to, packed again.
    views = {acc["bufferView"] for acc in g["accessors"] if "bufferView" in acc}
    views.update(img["bufferView"] for img in g.get("images", []) if "bufferView" in img)
    new_view = {old: new for new, old in enumerate(sorted(views))}
    packed = bytearray()
    kept = []
    for old in sorted(views):
        view = dict(g["bufferViews"][old])
        start = view.get("byteOffset", 0)
        while len(packed) % 4:
            packed.append(0)
        view["byteOffset"] = len(packed)
        packed += data[start:start + view["byteLength"]]
        kept.append(view)
    g["bufferViews"] = kept
    for acc in g["accessors"]:
        if "bufferView" in acc:
            acc["bufferView"] = new_view[acc["bufferView"]]
    for img in g.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = new_view[img["bufferView"]]
    g["buffers"][0]["byteLength"] = len(packed)

    open(bin_path, "wb").write(packed)
    json.dump(g, open(path, "w"), separators=(",", ":"))
    after = (os.path.getsize(path), len(packed), len(g["animations"]))
    print("clips %d -> %d, .gltf %d -> %d kB, .bin %d -> %d kB" % (
        before[2], after[2], before[0] // 1000, after[0] // 1000, before[1] // 1000, after[1] // 1000))


if __name__ == "__main__":
    main()
