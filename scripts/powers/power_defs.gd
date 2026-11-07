class_name PowerDefs
extends RefCounted
## Every tunable number of the powers.

enum Power { VORTEX, SHIELD, SHOCKWAVE }

const NAMES := ["Trou noir", "Bouclier", "Onde de choc"]
const KEYS := ["clic", "E", "F"]

## How far you can target, metres.
const RANGE := 80.0

const COOLDOWN := {
	Power.VORTEX: 8.0,
	Power.SHIELD: 6.0,
	Power.SHOCKWAVE: 3.0,
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
## A shell of black ice standing in front of the player: a slice of a wide
## curve, gently bent across and leaning back a little at the top, open to
## the sides and behind. Distance of its front from the player, radius of
## its curve, how much of that curve it covers, height, lean of the top.
const SHIELD_AHEAD := 2.3
const SHIELD_RADIUS := 3.2
const SHIELD_ARC := 52.0  ## degrees: about 2.8 m across
const SHIELD_HEIGHT := 3.0
const SHIELD_LEAN := 0.4
const SHIELD_THICKNESS := 0.35
const SHIELD_HP := 700.0
const SHIELD_LIFETIME := 14.0

# --- Shock wave ---------------------------------------------------------------------
## A blast of air out of your hands, along where you look: its front runs
## out to SHOCK_RANGE (m) at SHOCK_SPEED (m/s), in a cone SHOCK_ANGLE
## degrees either side of your aim.
const SHOCK_RANGE := 16.0
const SHOCK_SPEED := 45.0
const SHOCK_ANGLE := 30.0
## What it passes is thrown away from you at up to SHOCK_PUSH m/s and
## lifted SHOCK_LIFT m/s (less far off, and less for heavy pieces).
const SHOCK_PUSH := 18.0
const SHOCK_LIFT := 4.0
## Damage to a standing block right in front of you (blocks hold about 3),
## fading out with distance: close, it punches through a wall; far, it only
## knocks loose what was barely holding.
const SHOCK_DAMAGE := 8.0


static func cooldown(power: int) -> float:
	return COOLDOWN[power]


## Powers that go off at once when you pick them (the others are aimed and
## cast with the cast button).
static func is_instant(power: int) -> bool:
	return power != Power.VORTEX
