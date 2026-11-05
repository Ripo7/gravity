class_name Megacity
extends Node3D
## The colossal city around the district: temple towers of stacked
## colonnades crowned with domes and spires, a double aqueduct ringing the
## district, colossal guardians, temple fronts and smoking chimneys.
## Nothing here breaks or collides: it is scenery, drawn as one MultiMesh
## per piece (a handful of draw calls), meshes from tools/make_megacity.py.

const KIT := "res://assets/megacity/kit.glb"
const TIERS := ["tier_xl", "tier_l", "tier_m", "tier_s"]
## Height of each tier piece (stylobate + core + entablature), metres.
const TIER_H := {"tier_xl": 24.2, "tier_l": 22.2, "tier_m": 20.2, "tier_s": 18.2}
const TIER_R := {"tier_xl": 16.0, "tier_l": 12.0, "tier_m": 8.5, "tier_s": 5.5}

static var _kit := {}  # piece name -> Mesh, shared
static var _materials := {}

@export var inner := 52.0
@export var seed_value := 5

var _meshes := {}  # piece name -> Mesh
var _placed := {}  # piece name -> Array[Transform3D]
var _smoke: Array[Vector3] = []


func _ready() -> void:
	if not _load_kit():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_lower_city(rng)
	_towers(rng)
	_aqueduct()
	_guardians()
	_temples(rng)
	_chimneys(rng)
	_build()


func _load_kit() -> bool:
	_meshes = kit()
	return not _meshes.is_empty()


## Every piece of the kit by name, with the game's materials (loaded once,
## shared with the street decor).
static func kit() -> Dictionary:
	if not _kit.is_empty():
		return _kit
	var scene := load(KIT) as PackedScene
	if scene == null:
		push_warning("Megacity kit missing: %s" % KIT)
		return _kit
	var root := scene.instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		_kit[String(mi.name)] = _restyle(mi.mesh)
	root.free()
	return _kit


## The kit's placeholder materials, swapped for the game's (by name).
static func _restyle(mesh: Mesh) -> Mesh:
	var out := mesh.duplicate() as Mesh
	for s in out.get_surface_count():
		var m := out.surface_get_material(s)
		var key := String(m.resource_name) if m else "marble"
		out.surface_set_material(s, _material(key))
	return out


static func _material(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	var made := _make_material(key)
	_materials[key] = made
	return made


static func _make_material(key: String) -> Material:
	var m := StandardMaterial3D.new()
	match key:
		"bronze":
			m.albedo_color = Color(0.78, 0.56, 0.28)
			m.metallic = 0.85
			m.roughness = 0.35
		"steel":
			m.albedo_color = Color(0.16, 0.16, 0.18)
			m.metallic = 0.6
			m.roughness = 0.45
		"cloth":
			m.albedo_color = Color(0.5, 0.08, 0.07)
			m.roughness = 0.95
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"amber":
			m.albedo_color = Color(0.2, 0.12, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.62, 0.28)
			m.emission_energy_multiplier = 1.6
		_:
			m.albedo_color = Color(0.93, 0.88, 0.8)
			m.roughness = 0.7
	return m


func _put(piece: String, xf: Transform3D) -> void:
	if not _meshes.has(piece):
		return
	if not _placed.has(piece):
		_placed[piece] = []
	(_placed[piece] as Array).append(xf)


## The lower city right behind the district walls: two rows of blocks
## (arcades, pilasters, lit windows) facing in, the back row taller.
func _lower_city(rng: RandomNumberGenerator) -> void:
	var widths := {"insula_low": 18.0, "insula_mid": 18.0, "insula_high": 13.5}
	for row in 2:
		var d := inner + 8.0 + row * 13.0
		for side in 4:
			var turn := Basis(Vector3.UP, side * PI * 0.5)
			var x := -d - 4.0
			while x < d + 4.0:
				var pick: String = (
					["insula_low", "insula_mid"] if row == 0 else ["insula_mid", "insula_high"]
				)[rng.randi_range(0, 1)]
				var w: float = widths[pick]
				# Facades face +z: this side's blocks stand at -z, facing in.
				var at := turn * Vector3(x + w * 0.5, 0, -d)
				_put(pick, Transform3D(turn, at))
				x += w + rng.randf_range(0.0, 2.5)


## Temple towers in two rings: tiers stacked smaller and smaller, crowned
## by a dome or a spire; the far ring taller.
func _towers(rng: RandomNumberGenerator) -> void:
	# Phones draw the near ring only (the far one is mostly haze anyway).
	for ring in int(Quality.pick(1, 2, 2)):
		var dist := inner + 40.0 + ring * 55.0
		var count := 9 + ring * 4
		for k in count:
			var a := TAU * (k + 0.5 * ring + rng.randf_range(-0.15, 0.15)) / count
			var at := Vector3(cos(a), 0, sin(a)) * (dist + rng.randf_range(-8, 8))
			var y := 0.0
			var start := 0 if ring == 1 or rng.randf() < 0.5 else 1
			var extra := ring + (1 if rng.randf() < 0.4 else 0)
			var stack: Array[String] = []
			for t in range(start, TIERS.size()):
				stack.append(TIERS[t])
				if t == start and extra > 0:
					for e in extra:
						stack.append(TIERS[t])
			var turn := Basis(Vector3.UP, rng.randf() * TAU)
			for t in stack:
				_put(t, Transform3D(turn, at + Vector3(0, y, 0)))
				y += TIER_H[t]
			var top: String = stack[-1]
			var r: float = TIER_R[top] * 0.72
			if rng.randf() < 0.55:
				_put("dome", Transform3D(turn.scaled(Vector3.ONE * r * 1.05), at + Vector3(0, y - 1.0, 0)))
			else:
				_put("spire", Transform3D(turn.scaled(Vector3.ONE * r), at + Vector3(0, y - 1.0, 0)))


## A two-storey aqueduct-viaduct all round the district, just behind the
## near city: a ring of 30 m spans.
func _aqueduct() -> void:
	var r := inner + 22.0
	var spans := int(TAU * r / 30.0)
	for k in spans:
		var a := TAU * (k + 0.5) / spans
		var at := Vector3(cos(a), 0, sin(a)) * r
		# The span runs along the ring (tangent), its x axis.
		var basis := Basis(Vector3.UP, -a + PI * 0.5)
		_put("viaduct", Transform3D(basis, at))
		_put("viaduct", Transform3D(basis, at + Vector3(0, 25.0, 0)))


## Colossal guardians at the four gates, looking into the district.
func _guardians() -> void:
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var at := Vector3(cos(a), 0, sin(a)) * (inner + 30.0)
		var look := Basis.looking_at(-at.normalized(), Vector3.UP)
		_put("statue", Transform3D(look * Basis(Vector3.UP, PI), at))


## Temple fronts facing the district between the gates.
func _temples(rng: RandomNumberGenerator) -> void:
	for k in 8:
		var a := TAU * k / 8.0 + rng.randf_range(-0.1, 0.1)
		var at := Vector3(cos(a), 0, sin(a)) * (inner + 34.0)
		var look := Basis.looking_at(at.normalized(), Vector3.UP)
		_put("temple_front", Transform3D(look, at))


## Temple-factory chimneys among the towers; their smoke drifts off.
func _chimneys(rng: RandomNumberGenerator) -> void:
	for k in 6:
		var a := TAU * (k + 0.3) / 6.0 + rng.randf_range(-0.2, 0.2)
		var at := Vector3(cos(a), 0, sin(a)) * (inner + 68.0 + rng.randf_range(-6, 6))
		var s := rng.randf_range(0.9, 1.3)
		_put("chimney", Transform3D(Basis().scaled(Vector3.ONE * s), at))
		_smoke.append(at + Vector3(0, 64.0 * s, 0))


func _build() -> void:
	for piece: String in _placed:
		add_child(batch(_meshes[piece], _placed[piece], piece, false))
	for at in _smoke:
		add_child(_smoke_plume(at))


## One MultiMesh drawing `mesh` at every transform.
static func batch(mesh: Mesh, xfs: Array, label: String, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return mmi


## A slow plume of warm smoke: a few big soft billboards (cheap).
func _smoke_plume(at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = int(Quality.pick(6, 10, 14))
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.direction = Vector3(0.6, 1, 0.2)
	p.spread = 12.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0.6, 0.3, 0.1)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.48, 0.42, 0.55))
	grad.set_color(1, Color(0.8, 0.7, 0.6, 0.0))
	p.color_ramp = grad
	var quad := QuadMesh.new()
	quad.size = Vector2(16, 16)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	quad.material = m
	p.mesh = quad
	return p


static func soft_dot() -> Texture2D:
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	g.width = 64
	g.height = 64
	return g
