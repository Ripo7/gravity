# Mannequin and animations

`AnimationLibrary_Godot_Standard.gltf` and `.bin`: the free "Standard"
version of the **Universal Animation Library** by **Quaternius**
(https://quaternius.com/packs/universalanimationlibrary.html): one rigged
mannequin (53 bones, 8547 vertices, no textures) and 46 clips, without
root motion.

Licence: **CC0 1.0** (public domain), see `LICENSE.txt`. No attribution is
required; Quaternius can be supported at https://www.patreon.com/quaternius.

Where these two files come from: the mirror
https://github.com/J-Ponzo/gltf-universal-animation-library (commit
`e24c23c`, 2025-06-10), which holds the pack as distributed on itch.io that
day, unchanged. They are unchanged here too:

    6e65377d81558333c4093dbb144a48fd19019343d82b1a3a7992a98ec0e0543c  AnimationLibrary_Godot_Standard.bin
    0ff075c7ad6855c5c2c37a171592ee8f0d6ab2f58259e2be77a9b63dd8027765  AnimationLibrary_Godot_Standard.gltf

Godot drops the `_Loop` at the end of a clip's name when it imports it and
makes the clip loop: `Jog_Fwd_Loop` in the file is `Jog_Fwd` in the game.

The clips: A_TPose, Crouch_Fwd, Crouch_Idle, Dance, Death01, Driving,
Fixing_Kneeling, Hit_Chest, Hit_Head, Idle, Idle_Talking, Idle_Torch,
Interact, Jog_Fwd, Jump, Jump_Land, Jump_Start, PickUp_Table,
Pistol_Aim_Down, Pistol_Aim_Neutral, Pistol_Aim_Up, Pistol_Idle,
Pistol_Reload, Pistol_Shoot, Punch_Cross, Punch_Enter, Punch_Jab, Push,
Roll, Roll_RM, Sitting_Enter, Sitting_Exit, Sitting_Idle, Sitting_Talking,
Spell_Simple_Enter, Spell_Simple_Exit, Spell_Simple_Idle,
Spell_Simple_Shoot, Sprint, Swim_Fwd, Swim_Idle, Sword_Attack,
Sword_Attack_RM, Sword_Idle, Walk, Walk_Formal. The game uses nine of them
(see `scripts/player/character.gd`).
