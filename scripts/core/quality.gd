class_name Quality
extends RefCounted
## Quality tier, picked once from the platform: full effects on desktop,
## a bit less in a desktop browser, a light version on phones and tablets.
## Effects read their budgets from here instead of guessing the platform.

enum Tier { LOW, MEDIUM, HIGH }

static var _tier := -1


static func tier() -> int:
	if _tier < 0:
		if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
			_tier = Tier.LOW
		elif OS.has_feature("web"):
			_tier = Tier.MEDIUM
		else:
			_tier = Tier.HIGH
	return _tier


## For tests and the --quality launch option.
static func force(t: int) -> void:
	_tier = t


## Picks the value for the current tier: pick(low, medium, high).
static func pick(low: Variant, medium: Variant, high: Variant) -> Variant:
	match tier():
		Tier.LOW:
			return low
		Tier.MEDIUM:
			return medium
	return high
