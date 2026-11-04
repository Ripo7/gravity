class_name PowerDefs
extends RefCounted
## Every tunable number of the three powers. One size each (the big one):
## press to cast.

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
const VORTEX_RADIUS := 10.0
## Just outside the radius, a band that shreds instead of pulling.
const VORTEX_BAND := 4.0
const VORTEX_CORE := 1.8
const VORTEX_SPINUP := 0.5  ## seconds before it starts pulling
const VORTEX_DURATION := 7.0
## Orbit speed (m/s) at the core and at the radius.
## Orbit angular speed (rad/s) at the core and at the radius.
const VORTEX_SPIN := Vector2(7.0, 3.2)
const VORTEX_MAX_SPEED := 34.0
## Structural damage per second inside the radius and in the band.
const VORTEX_DPS_INSIDE := 9.0
const VORTEX_DPS_BAND := 3.0
## Player damage per second inside the radius and in the band.
const VORTEX_HURT_INSIDE := 70.0
const VORTEX_HURT_BAND := 30.0

# --- Meteor portal -----------------------------------------------------------------
const PORTAL_RADIUS := 10.0
const PORTAL_STONES := 14
const PORTAL_STONE_SIZE := 4.2  ## metres, longest edge
const PORTAL_HEIGHT := 26.0  ## above the target
const PORTAL_SPREAD := 2.2  ## seconds over which stones drop

# --- Ice shield --------------------------------------------------------------------
const SHIELD_WIDTH := 7.5
const SHIELD_HEIGHT := 4.2
const SHIELD_HP := 700.0
const SHIELD_LIFETIME := 14.0
const SHIELD_DISTANCE := 3.2  ## in front of the player


static func cooldown(power: int) -> float:
	return COOLDOWN[power]
