class_name TestCase
extends Node
## Minimal test base: methods named test_* run in order, may `await`.

var failures: Array[String] = []
var current := ""


func check(cond: bool, message: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, message])


func check_eq(a: Variant, b: Variant, message := "") -> void:
	check(a == b, "%s (expected %s, got %s)" % [message, b, a])


func check_near(a: float, b: float, eps: float, message := "") -> void:
	check(absf(a - b) <= eps, "%s (expected %f ± %f, got %f)" % [message, b, eps, a])


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
