class_name Layers
extends RefCounted
## The collision layers, by name (the same as in project.godot).

## The ground, and whatever neither moves nor breaks.
const WORLD := 1
## What stands and can be broken (Structure): in the way of the brute and
## of the camera.
const STRUCTURE := 2
## What has come off (Rubble): in the way of the brute, not of the camera.
const RUBBLE := 4
## The brute.
const PLAYER := 8
