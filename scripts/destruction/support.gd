class_name Support
extends RefCounted
## Decides what still stands in a Structure.
## 1. Reach: starting from the shards on the ground and going from bond to
##    bond, every shard reached is held; the others have nothing under them
##    any more and come off (unheld()).
## 2. Load: each shard hangs its weight on the neighbours one step nearer
##    the ground, and so on down. A bond that carries too much for its size
##    breaks (overloaded()). Pressed straight down a bond is strong; pulled
##    or sheared sideways it is weak; and what sticks out sideways levers
##    the bonds at its root, the more the farther it sticks out (a slab
##    that lost its pillars, a wall over a wide gap).
## It is a rough model, far from real engineering, but it gives what the eye
## expects: a hole in a wall holds, a wide gap brings down what is above it,
## a slab that lost its pillars snaps off.

const GRAVITY := 9.8
## Stress (Pa) a whole bond takes before it breaks. Tuned on the house: as
## built, its most loaded bond is at about half of this (--mode=check).
const STRENGTH := 1.2e6
## Share of a load pressing straight down through a bond that strains it.
const SQUEEZE := 0.08
## How much a load out to the side levers a bond.
const LEVER := 2.0
## Bonds over their limit broken in one look, worst first. Those far over
## it (a ratio above SNAP) all go at once.
const BREAKS := 24
const SNAP := 2.0

## A bond much smaller than the biggest one its shard has is a sliver: the
## shard is not counted as hanging on it while it has better.
const SLIVER := 0.25
## Share of all of a shard's bonds it is judged on at least.
const WEDGE := 0.35

## Steps from the ground, per shard (-1: not reached).
var level := PackedInt32Array()
## The worst load / strength seen in the last look (1 = at the limit).
var worst := 0.0

var _order := PackedInt32Array()
var _hold := PackedFloat32Array()  # area of the bonds each shard hangs on
var _wedge := PackedFloat32Array()  # the area it is judged on (see WEDGE)
var _out := PackedFloat32Array()  # how far each shard sticks out sideways from what is under it (m)
var _carry := PackedFloat32Array()  # kg hanging on each shard, its own included
var _lever := PackedFloat32Array()  # kg.m: how far out that weight is, beyond the shard
var _seen := PackedInt32Array()
# Per entry of adj_bond (shard i, its neighbour j):
var _good := PackedByteArray()  # big enough to hang j on i
var _down := PackedFloat32Array()  # 1 if j is right under i, 0 if beside or above
var _lean := PackedFloat32Array()  # how much farther out i is than j (m)


func setup(s: Structure) -> void:
	level.resize(s.count)
	_hold.resize(s.count)
	_wedge.resize(s.count)
	_out.resize(s.count)
	_carry.resize(s.count)
	_lever.resize(s.count)
	_seen.resize(s.count)
	var biggest := PackedFloat32Array()
	biggest.resize(s.count)
	for b in s.bond_a.size():
		biggest[s.bond_a[b]] = maxf(biggest[s.bond_a[b]], s.bond_area[b])
		biggest[s.bond_b[b]] = maxf(biggest[s.bond_b[b]], s.bond_area[b])
	_good.resize(s.adj_bond.size())
	_down.resize(s.adj_bond.size())
	_lean.resize(s.adj_bond.size())
	for i in s.count:
		for k in range(s.adj_first[i], s.adj_first[i + 1]):
			var j := s.adj_other[k]
			_good[k] = 1 if s.bond_area[s.adj_bond[k]] >= SLIVER * biggest[j] else 0
			var to := s.centroid[j] - s.centroid[i]
			var length := to.length()
			var down := maxf(-to.y / length, 0.0)
			_down[k] = down
			# Resting on j: only as far out as it is to the side of it.
			# Hanging from j: the whole way.
			_lean[k] = Vector2(to.x, to.z).length() * (1.0 - down) * (1.0 - down) if to.y <= 0.0 else length


## The standing shards that nothing holds any more, grouped by what is
## still bonded together.
func unheld(s: Structure) -> Array[PackedInt32Array]:
	level.fill(-1)
	_order.clear()
	for i in s.count:
		if s.held[i] == 1 and s.anchored[i] == 1:
			level[i] = 0
			_order.append(i)
	_spread(s, true)
	if _order.size() < s.held_count:
		# What only slivers hold is reached last, from everything else.
		_spread(s, false)
	var out: Array[PackedInt32Array] = []
	if _order.size() == s.held_count:
		return out
	_seen.fill(0)
	for start in s.count:
		if s.held[start] == 0 or level[start] >= 0 or _seen[start] == 1:
			continue
		var group := PackedInt32Array([start])
		_seen[start] = 1
		var head := 0
		while head < group.size():
			var i := group[head]
			head += 1
			for k in range(s.adj_first[i], s.adj_first[i + 1]):
				var j := s.adj_other[k]
				if _seen[j] == 0 and s.held[j] == 1 and s.bond_health[s.adj_bond[k]] > 0.0:
					_seen[j] = 1
					group.append(j)
		out.append(group)
	return out


## The bonds that carry more than they can, worst first (uses who hangs on
## whom as unheld() last worked it out).
func overloaded(s: Structure) -> PackedInt32Array:
	for i in _order:
		_carry[i] = s.mass[i]
		_lever[i] = 0.0
	var over: Array[Vector2] = []  # (-ratio, bond)
	worst = 0.0
	# From the farthest shards down to the ground.
	for n in range(_order.size() - 1, -1, -1):
		var i := _order[n]
		var hold := _hold[i]
		if hold <= 0.0 or s.held[i] == 0:
			continue
		var below := level[i] - 1
		var load := _carry[i]
		var lever := _lever[i]
		var out := _out[i]
		var depth := sqrt(_wedge[i])
		var push := load * GRAVITY / _wedge[i] / STRENGTH
		for k in range(s.adj_first[i], s.adj_first[i + 1]):
			var j := s.adj_other[k]
			if level[j] != below:
				continue
			var b := s.adj_bond[k]
			var health := s.bond_health[b]
			if health <= 0.0:
				continue
			var share := s.bond_area[b] / hold
			var down := _down[k]
			# What hangs out beyond the neighbour levers this bond, unless
			# the load goes straight down into it.
			var moment := (lever + load * maxf(out - _out[j], 0.0)) * (1.0 - down)
			_carry[j] += load * share
			_lever[j] += moment * share
			var ratio := push * (1.0 - down * (1.0 - SQUEEZE) + LEVER * moment / load / depth) / health
			if ratio > worst:
				worst = ratio
			if ratio > 1.0:
				over.append(Vector2(-ratio, b))
	over.sort()
	var broken := PackedInt32Array()
	for o in over:
		if broken.size() >= BREAKS and -o.x < SNAP:
			break
		broken.append(int(o.y))
	return broken


## Goes from the shards reached so far to the standing shards bonded to
## them, step by step, and notes for each what it hangs on. `good_only`: not
## through slivers.
func _spread(s: Structure, good_only: bool) -> void:
	var head := 0
	while head < _order.size():
		var i := _order[head]
		head += 1
		var here := level[i]
		var hold := 0.0
		var all := 0.0
		var out := INF
		for k in range(s.adj_first[i], s.adj_first[i + 1]):
			var b := s.adj_bond[k]
			if s.bond_health[b] <= 0.0:
				continue
			var j := s.adj_other[k]
			var theirs := level[j]
			if theirs < 0:
				if s.held[j] == 0:
					continue
				all += s.bond_area[b]
				if good_only and _good[k] == 0:
					continue
				level[j] = here + 1
				_order.append(j)
			else:
				all += s.bond_area[b]
				if theirs == here - 1:
					hold += s.bond_area[b]
					out = minf(out, _out[j] + _lean[k])
		_hold[i] = hold
		# A shard wedged between its neighbours leans on them too: it is
		# never judged on a sliver alone while it has other bonds.
		_wedge[i] = maxf(hold, all * WEDGE)
		_out[i] = 0.0 if here == 0 else out
