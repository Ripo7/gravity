class_name PowerDefs
extends RefCounted
## Every tunable number of the three powers. One size each.

enum Power { VORTEX, PORTAL, SHIELD }

const NAMES := ["Trou noir", "Portail", "Bouclier"]
const KEYS := ["1", "2", "3"]

## How far you can target, metres.
const RANGE := 80.0

const COOLDOWN := {
	Power.VORTEX: 8.0,
	Power.PORTAL: 10.0,
	Power.SHIELD: 6.0,
}

# --- Black hole (vortex) -------------------------------------------------------
## Everything inside this radius is caught and spins around the core.
const VORTEX_RADIUS := 5.0
## Just outside the radius, a band that shreds instead of pulling.
const VORTEX_BAND := 2.0
const VORTEX_CORE := 0.9
const VORTEX_SPINUP := 0.5  ## seconds before it starts pulling
const VORTEX_DURATION := 7.0
## Orbit angular speed (rad/s) at the core and at the radius.
const VORTEX_SPIN := Vector2(9.0, 4.5)
const VORTEX_MAX_SPEED := 22.0
## Structural damage per second inside the radius and in the band.
const VORTEX_DPS_INSIDE := 9.0
const VORTEX_DPS_BAND := 3.0
## Player damage per second inside the radius and in the band.
const VORTEX_HURT_INSIDE := 70.0
const VORTEX_HURT_BAND := 30.0

# --- Meteor portal -----------------------------------------------------------------
const PORTAL_RADIUS := 5.0
## One big rock; it breaks apart after a few hard hits.
const PORTAL_STONE_SIZE := 5.0  ## metres, longest edge
const PORTAL_STONE_HP := 120.0
const PORTAL_HEIGHT := 26.0  ## above the target

# --- Ice shield --------------------------------------------------------------------
const SHIELD_WIDTH := 3.75
const SHIELD_HEIGHT := 2.1
const SHIELD_HP := 700.0
const SHIELD_LIFETIME := 14.0
const SHIELD_DISTANCE := 3.2  ## in front of the player


static func cooldown(power: int) -> float:
	return COOLDOWN[power]
