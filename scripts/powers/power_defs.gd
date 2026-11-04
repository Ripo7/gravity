class_name PowerDefs
extends RefCounted
## Every tunable number of the three powers, per size tier (0 small, 1 medium,
## 2 large). Hold the cast button longer to step up a tier.

enum Power { GRAVITY, PORTAL, SHIELD }

const NAMES := ["Singularité", "Portail", "Bouclier"]
const KEYS := ["1", "2", "3"]
const TIER_NAMES := ["petit", "moyen", "grand"]

## Seconds the cast button must be held to reach tier 1 and tier 2.
const TIER_TIMES := Vector2(0.35, 0.85)
## How far you can target, metres.
const RANGE := 70.0

const COOLDOWN := {
	Power.GRAVITY: [2.0, 4.5, 9.0],
	Power.PORTAL: [5.0, 9.0, 16.0],
	Power.SHIELD: [3.0, 5.0, 8.0],
}

# --- Gravity orb -----------------------------------------------------------------
## Charge fed to BlastParams for each tier.
const GRAVITY_CHARGE := [0.4, 0.72, 1.0]
## Seconds the orb hangs and grows before it goes off.
const GRAVITY_FUSE := [0.9, 1.3, 1.8]

# --- Meteor portal -----------------------------------------------------------------
const PORTAL_RADIUS := [3.0, 6.0, 10.0]
const PORTAL_STONES := [3, 7, 14]
const PORTAL_STONE_SIZE := [2.0, 3.0, 4.2]  ## metres, longest edge
const PORTAL_HEIGHT := [16.0, 20.0, 26.0]  ## above the target
const PORTAL_SPREAD := [0.6, 1.3, 2.2]  ## seconds over which stones drop

# --- Ice shield --------------------------------------------------------------------
const SHIELD_WIDTH := [2.4, 4.5, 7.5]
const SHIELD_HEIGHT := [2.6, 3.2, 4.2]
const SHIELD_HP := [260.0, 420.0, 700.0]
const SHIELD_LIFETIME := 14.0
const SHIELD_DISTANCE := 3.2  ## in front of the player


static func tier_for(held: float) -> int:
	if held >= TIER_TIMES.y:
		return 2
	if held >= TIER_TIMES.x:
		return 1
	return 0


static func cooldown(power: int, tier: int) -> float:
	return COOLDOWN[power][tier]


static func gravity_params(tier: int) -> BlastParams:
	return BlastParams.from_charge(GRAVITY_CHARGE[tier])
