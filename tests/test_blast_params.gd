extends TestCase


func test_everything_scales_with_charge() -> void:
	var small := BlastParams.from_charge(0.1)
	var big := BlastParams.from_charge(1.0)
	check(big.radius > small.radius, "radius")
	check(big.burst_speed > small.burst_speed, "burst")
	check(big.damage > small.damage * 4.0, "damage grows faster than linear")
	check(big.break_radius < big.radius * 0.5, "damage reaches less far than the pull")
	check(big.pull_time > small.pull_time, "pull time")
	check(big.ball_radius > small.ball_radius, "ball size")
	check(big.slow_motion and not small.slow_motion, "slow motion only on big blasts")


func test_charge_is_clamped() -> void:
	check_eq(BlastParams.from_charge(-1.0).charge, BlastParams.MIN_CHARGE, "min clamp")
	check_eq(BlastParams.from_charge(5.0).charge, 1.0, "max clamp")


func test_falloff_shape() -> void:
	var p := BlastParams.from_charge(0.5)
	check_near(p.falloff(0.0), 1.0, 1e-5, "full at centre")
	check_eq(p.falloff(p.radius), 0.0, "zero at edge")
	var prev := 2.0
	for i in 11:
		var f := p.falloff(p.radius * i / 10.0)
		check(f <= prev, "monotonic")
		prev = f
