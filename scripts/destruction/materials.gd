class_name Materials
extends RefCounted
## Building materials. Each one looks, weighs and breaks differently.
## The id is written into each instance's colour so one shader (one draw
## call) renders every material.

enum Kind { CONCRETE, WOOD, METAL, ICE }

## Per material: strength multiplier, density (kg/m^3), fracture piece
## multiplier, fraction of strength that knocks a block loose, how strongly
## blasts move it (lighter = flies further), friction, bounce.
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
}


static func prop(kind: int, key: String) -> float:
	return PROPS[kind][key]


## Value stored in the instance colour's green channel: kind / 3. The
## Compatibility renderer converts instance colours from sRGB to linear, so
## the shader converts back before rounding.
static func encode(kind: int) -> float:
	return float(kind) / 3.0
