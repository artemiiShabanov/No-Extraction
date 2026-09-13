extends Node3D
class_name Gate
## The castle gate: two plank doors with hit points, three damage stages readable from the
## wall (splinters, smoke, fire), attack slots for enemies and a crowd queue behind them.
## When it falls the planks burst into physics debris and the passage opens.

signal damaged(hp: int, stage: int)
signal fell()

const DOOR_W := 3.9
const DOOR_H := 5.3
const PLANKS_PER_DOOR := 4
const SLOT_ROWS := [-0.6, -2.2]  # z of the two attack rows in front of the doors
const SLOT_COLS := [-1.3, 0.0, 1.3]

var max_hp := 300
var hp := 300
var stage := 0
var stages: Array = [0.66, 0.33, 0.0]
var fallen := false
var slots: Array = []
var planks: Array[MeshInstance3D] = []
var body: StaticBody3D
var smoke: GPUParticles3D
var fire: GPUParticles3D
var fire_light: OmniLight3D
var wood: Material
var effects_enabled := true  # smoke/fire, off by playtest feedback for now


func _ready() -> void:
	Game.gate = self
	var cfg := WaveManager._load_json("res://data/castle.json")
	max_hp = int(cfg.get("gate_hp", 300))
	hp = max_hp
	stages = cfg.get("stages", stages)
	slots.resize(int(cfg.get("gate_slots", 6)))
	effects_enabled = bool(cfg.get("gate_effects", true))
	wood = EnvMaterials.stone("Wood")
	_build_doors()
	_build_effects()


func _build_doors() -> void:
	body = StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var plank_w := DOOR_W / 2.0 / PLANKS_PER_DOOR
	for door in [-1, 1]:
		for i in PLANKS_PER_DOOR:
			var x: float = door * (0.15 + plank_w * (i + 0.5))
			var mi := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(plank_w - 0.04, DOOR_H, 0.28)
			mi.mesh = mesh
			mi.position = Vector3(x, DOOR_H / 2, 0.0)
			mi.material_override = wood
			mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			add_child(mi)
			planks.append(mi)
		for z in [0.8, 2.6, 4.4]:
			for side in [0.18, -0.18]:
				var band := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(DOOR_W / 2 - 0.1, 0.18, 0.06)
				band.mesh = bm
				band.position = Vector3(door * DOOR_W / 4, z, side)
				band.material_override = EnvMaterials.stone("Dark")
				add_child(band)
				planks.append(band)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(DOOR_W + 0.4, DOOR_H, 0.4)
	shape.shape = box
	shape.position = Vector3(0, DOOR_H / 2, 0)
	body.add_child(shape)


func _build_effects() -> void:
	smoke = _particles(Color(0.25, 0.24, 0.23, 0.55), 2.6, 14.0, 60, Vector3(0, 6.0, -1.0))
	fire = _particles(Color(1.0, 0.55, 0.15, 0.9), 0.9, 4.0, 40, Vector3(0, 3.0, -0.8), true)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.55, 0.2)
	fire_light.light_energy = 0.0
	fire_light.omni_range = 14.0
	fire_light.position = Vector3(0, 3.5, -1.5)
	add_child(fire_light)


func _particles(color: Color, size: float, rise: float, amount: int, pos: Vector3, additive := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 4.0 if not additive else 1.2
	p.emitting = false
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 30, 20))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = rise * 0.6
	pm.initial_velocity_max = rise
	pm.gravity = Vector3(0, 0.6, 0) if not additive else Vector3(0, 2.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.8, 0.3, 0.5)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, 0.0))
	ramp.add_point(0.15, color)
	ramp.set_color(1, Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = load("res://scripts/bullet.gd")._soft_dot()
	if additive:
		qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = qm
	p.draw_pass_1 = quad
	add_child(p)
	return p


# ------------------------------------------------------------------ damage

func damage(amount: int, hit_pos: Vector3) -> void:
	if fallen:
		return
	hp = max(hp - amount, 0)
	var BulletScript := load("res://scripts/bullet.gd")
	BulletScript.spawn_puff(get_tree().current_scene, hit_pos, Vector3(0, 0.6, -1), Color(0.55, 0.42, 0.25, 0.9), 10, 0.22)
	var new_stage := 0
	for i in stages.size():
		if hp <= max_hp * float(stages[i]):
			new_stage = i + 1
	if new_stage != stage:
		stage = new_stage
		_apply_stage()
	damaged.emit(hp, stage)
	if hp <= 0:
		_fall()


func repair(amount: int) -> void:
	if fallen:
		return
	hp = mini(hp + amount, max_hp)
	var new_stage := 0
	for i in stages.size():
		if hp <= max_hp * float(stages[i]):
			new_stage = i + 1
	if new_stage != stage:
		stage = new_stage
		_apply_stage()
	damaged.emit(hp, stage)


func _apply_stage() -> void:
	# stage 1: a plank knocked out per door; stage 2: smoke, more planks gone; stage 3: fire
	var to_hide: Array = [[], [0, 5], [0, 1, 5, 6], [0, 1, 2, 5, 6, 7]][mini(stage, 3)]
	var idx := 0
	for mi in planks:
		if mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.y > 1.0:  # planks only, not bands
			mi.visible = not (idx in to_hide)
			idx += 1
	smoke.emitting = effects_enabled and stage >= 2
	fire.emitting = effects_enabled and stage >= 3
	fire_light.light_energy = 6.0 if effects_enabled and stage >= 3 else 0.0


func _fall() -> void:
	fallen = true
	body.collision_layer = 0
	body.get_child(0).disabled = true
	for mi in planks:
		if not mi.visible:
			continue
		var rb := RigidBody3D.new()
		rb.collision_layer = Game.LAYER_RAGDOLL
		rb.collision_mask = Game.LAYER_WORLD | Game.LAYER_RAGDOLL
		rb.mass = 8.0
		rb.global_transform = mi.global_transform
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (mi.mesh as BoxMesh).size
		shape.shape = box
		rb.add_child(shape)
		remove_child(mi)
		mi.position = Vector3.ZERO
		mi.rotation = Vector3.ZERO
		rb.add_child(mi)
		get_tree().current_scene.add_child(rb)
		rb.apply_central_impulse(Vector3(randf_range(-2, 2), randf_range(2, 6), randf_range(6, 12)))
		rb.apply_torque_impulse(Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)))
		get_tree().create_timer(20.0).timeout.connect(rb.queue_free)
	planks.clear()
	for s in slots.size():
		slots[s] = null
	print("GATE fell")
	fell.emit()


func _process(delta: float) -> void:
	if effects_enabled and stage >= 3 and not fallen:
		fire_light.light_energy = 5.0 + sin(Time.get_ticks_msec() * 0.02) * 1.2 + randf() * 0.6


# ------------------------------------------------------------------ slots and crowd

func request_slot(knight: Node) -> int:
	for i in slots.size():
		if slots[i] == knight:
			return i
	for i in slots.size():
		if slots[i] == null or not is_instance_valid(slots[i]) or slots[i].dead:
			slots[i] = knight
			return i
	return -1


## The ram takes the two centre slots; knights standing there re-queue.
func reserve_ram(ram: Node) -> void:
	for i in [1, 4]:
		if i < slots.size():
			var k = slots[i]
			if k != null and is_instance_valid(k) and k != ram and "gate_slot" in k:
				k.gate_slot = -1
			slots[i] = ram


func release_slot(knight: Node) -> void:
	for i in slots.size():
		if slots[i] == knight:
			slots[i] = null


func slot_position(i: int) -> Vector3:
	var row := i / SLOT_COLS.size()
	var col := i % SLOT_COLS.size()
	return global_position + Vector3(SLOT_COLS[col], 0.0, SLOT_ROWS[mini(row, SLOT_ROWS.size() - 1)] - 3.0)


## Waiting spot in a loose half ring in front of the gate, stable per knight.
func wait_position(knight: Node) -> Vector3:
	var h := hash(knight.get_instance_id())
	var angle := deg_to_rad(-65.0 + float(h % 1000) / 1000.0 * 130.0)
	var radius := 5.5 + float((h / 1000) % 1000) / 1000.0 * 3.5
	return global_position + Vector3(sin(angle) * radius, 0.0, -3.0 - cos(angle) * radius)


func attack_point(i: int) -> Vector3:
	return global_position + Vector3(SLOT_COLS[i % SLOT_COLS.size()], 1.5, 0.0)
