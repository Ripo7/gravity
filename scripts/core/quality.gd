class_name Quality
extends RefCounted
## Quality tier, picked once from the platform: full effects on desktop,
## a bit less in a desktop browser, a light version on phones and tablets.
## Effects read their budgets from here instead of guessing the platform.

enum Tier { LOW, MEDIUM, HIGH }

static var _tier := -1


static func tier() -> int:
	if _tier < 0:
		if is_handheld():
			_tier = Tier.LOW
		elif OS.has_feature("web"):
			_tier = Tier.MEDIUM
		else:
			_tier = Tier.HIGH
	return _tier


## Phones and tablets. Godot reads web_ios from the user agent, and Safari
## on iPadOS sends a Mac one: a "Mac" with a touchscreen is an iPad.
static func is_handheld() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	return OS.has_feature("web_macos") and DisplayServer.is_touchscreen_available()


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
