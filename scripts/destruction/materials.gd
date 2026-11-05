class_name Materials
extends RefCounted
## Building materials. Each one looks, weighs and breaks differently.
## The id is written into each instance's colour so one shader (one draw
## call) renders every material.

enum Kind { CONCRETE, WOOD, METAL, ICE, GLASS }

## Per material: strength multiplier, density (kg/m^3), fracture piece
## multiplier, fraction of strength that knocks a block loose, how strongly
## blasts move it (lighter = flies further), friction, bounce.
## Material slots in the custom-data integer (Kind fits under it).
const KIND_SLOTS := 5
## Facade colours, index 1..PAINT_COUNT (0 = raw). Keep in step with
## `PAINTS` in shaders/block.gdshader.
const PAINT_COUNT := 7
const PAINTS: Array[Color] = [
	Color(1, 1, 1),
	Color(0.95, 0.68, 0.3),  # ochre
	Color(0.85, 0.42, 0.3),  # terracotta
	Color(0.95, 0.62, 0.6),  # rose
	Color(0.55, 0.7, 0.5),  # sage
	Color(0.98, 0.9, 0.7),  # cream
	Color(0.4, 0.62, 0.72),  # teal
	Color(0.92, 0.78, 0.38),  # mustard
]

const PROPS := {
	Kind.CONCRETE:
	{
		"strength": 1.0,
		"density": 260.0,
		"pieces": 1.0,
		"dislodge": 0.3,
		"blast_response": 1.0,
		"friction": 0.85,
		"bounce": 0.03,
	},
	Kind.WOOD:
	{
		"strength": 0.7,
		"density": 120.0,
		"pieces": 0.7,
		"dislodge": 0.25,
		"blast_response": 1.25,
		"friction": 0.9,
		"bounce": 0.08,
	},
	Kind.METAL:
	{
		"strength": 2.2,
		"density": 560.0,
		"pieces": 0.3,
		"dislodge": 0.12,
		"blast_response": 0.7,
		"friction": 0.5,
		"bounce": 0.2,
	},
	# Black ice from the shield power: hard, slippery, shatters into shards.
	Kind.ICE:
	{
		"strength": 1.6,
		"density": 300.0,
		"pieces": 1.2,
		"dislodge": 0.2,
		"blast_response": 1.1,
		"friction": 0.15,
		"bounce": 0.1,
	},
	# Window glass: breaks at a touch into a spray of shards (no bodies).
	Kind.GLASS:
	{
		"strength": 0.12,
		"density": 250.0,
		"pieces": 0.0,
		"dislodge": 1.0,
		"blast_response": 1.3,
		"friction": 0.4,
		"bounce": 0.05,
	},
}


static func prop(kind: int, key: String) -> float:
	return PROPS[kind][key]


## Value stored in the instance colour's green channel (legacy, unused by
## the block shader now: colour conversion differs between renderers).
static func encode(kind: int) -> float:
	return float(kind) / 4.0


## First custom-data float of an instance: the material and paint in the
## integer part (paint * KIND_SLOTS + kind), the damage (0..1, drawn as
## cracks) in the fraction. Custom data is never colour-converted, so the
## shader reads them back exactly.
static func custom(kind: int, damage: float, seed_value := 0.0) -> float:
	return float(paint_of(seed_value) * KIND_SLOTS + kind) + clampf(damage, 0.0, 1.0) * 0.9


## A block's seed carries its building's paint (0 = raw) in its integer
## part, so the colour follows every piece broken off it without another
## field: the fraction is the per-block random seed.
static func paint_seed(paint: int, random: float) -> float:
	return float(paint) + clampf(random, 0.0, 0.999)


static func paint_of(seed_value: float) -> int:
	return clampi(int(floor(seed_value)), 0, PAINT_COUNT)
