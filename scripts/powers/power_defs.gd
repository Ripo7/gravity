class_name PowerDefs
extends RefCounted
## Every tunable number of the two powers.

enum Power { VORTEX, SHIELD }

const NAMES := ["Trou noir", "Bouclier"]
const KEYS := ["clic", "E"]

## How far you can target, metres.
const RANGE := 80.0

const COOLDOWN := {
	Power.VORTEX: 8.0,
	Power.SHIELD: 6.0,
}

# --- Black hole (vortex) -------------------------------------------------------
## Everything inside this radius is caught and spins around the core.
const VORTEX_RADIUS := 5.0
## Just outside the radius, a band that shreds instead of pulling.
const VORTEX_BAND := 2.0
const VORTEX_CORE := 0.9
const VORTEX_SPINUP := 0.5  ## seconds before it starts pulling
const VORTEX_DURATION := 3.5
## When it closes, what it held is flung outward at this speed (m/s),
## a little upward, faster near the core.
const VORTEX_BURST_SPEED := Vector2(16.0, 10.0)
const VORTEX_BURST_LIFT := 4.0
## Orbit angular speed (rad/s) at the core and at the radius.
const VORTEX_SPIN := Vector2(9.0, 4.5)
const VORTEX_MAX_SPEED := 22.0
## A falling piece of building within VORTEX_PULL_REACH (m) of the core is
## dragged toward it, VORTEX_PULL m/s^2 at the radius (twice that at the
## core, fading out at the reach), and round it at VORTEX_SWIRL m/s^2: what
## falls past a black hole does not get by.
const VORTEX_PULL_REACH := 9.0
const VORTEX_PULL := 20.0
const VORTEX_SWIRL := 10.0
## Structural damage per second inside the radius and in the band.
const VORTEX_DPS_INSIDE := 9.0
const VORTEX_DPS_BAND := 3.0
## Player damage per second inside the radius and in the band.
const VORTEX_HURT_INSIDE := 70.0
const VORTEX_HURT_BAND := 30.0

# --- Ice shield --------------------------------------------------------------------
## A curved shell of black ice, close to a half dome, rising around the front
## of the player. Horizontal radius, height and how far it wraps around.
const SHIELD_RADIUS := 2.7
const SHIELD_HEIGHT := 4.8
const SHIELD_ARC := 200.0  ## degrees
const SHIELD_THICKNESS := 0.35
const SHIELD_HP := 700.0
const SHIELD_LIFETIME := 14.0


static func cooldown(power: int) -> float:
	return COOLDOWN[power]
