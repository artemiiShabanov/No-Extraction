extends CharacterBody3D
## Blocky knight (enemy or ally). Enemies charge the wall; allies hold the field.
## Opposing knights pair up and duel 1 on 1. Bullets hit per-bone zones.
## Skeleton and animations come from Mixamo (assets/mixamo), props are attached to bones.

@export var speed := 6.0
@export var faction: Game.Faction = Game.Faction.ENEMY
@export var tunic_color := Color(0.75, 0.12, 0.10)
@export var corpse_time := 12.0
@export var model_yaw := PI  # Mixamo rigs face +Z, Godot forward is -Z
@export var max_hp := 2  # bullet damage: head = kill, torso = 2, limb = 1, shield = 0
@export var melee_hp := 3
@export var melee_hit_chance := 0.5
@export var has_shield := true
@export var priority := false  # priority target: its death lets the wave rout
var type_id := "swordsman"
var fleeing := false
var flee_to := Vector3.ZERO
var gate_slot := -1
var gate_retry := 0.0
var idle_at_wall := 0.0
var gate_damage := 2

const SwordScene := preload("res://assets/models/sword.glb")
const ShieldScene := preload("res://assets/models/shield.glb")

# animation name -> Mixamo file (each holds one clip named "mixamo_com")
const ANIM_FILES := {
	"Run": "res://assets/mixamo/knight_run.fbx",
	"Idle": "res://assets/mixamo/knight_idle.fbx",
	"Attack": "res://assets/mixamo/knight_attack.fbx",
	"Death": "res://assets/mixamo/knight_death.fbx",
}
const LOOPING := ["Run", "Idle", "Attack"]
static var _anim_cache := {}

const RIGHT_HAND_BONE := "mixamorig_RightHand"
const LEFT_ARM_BONE := "mixamorig_LeftForeArm"
const SHIELD_OFFSET := Vector3(0.12, 0.13, 0.0)

# hit zones: bone -> [box size, offset along the bone, zone name]
const HITBOXES := {
	"mixamorig_Head": [Vector3(0.42, 0.44, 0.42), Vector3(0, 0.22, 0), "head"],
	"mixamorig_Spine": [Vector3(0.56, 0.50, 0.36), Vector3(0, 0.20, 0), "torso"],
	"mixamorig_Hips": [Vector3(0.50, 0.26, 0.32), Vector3(0, -0.02, 0), "torso"],
	"mixamorig_LeftArm": [Vector3(0.18, 0.30, 0.18), Vector3(0, 0.15, 0), "limb"],
	"mixamorig_RightArm": [Vector3(0.18, 0.30, 0.18), Vector3(0, 0.15, 0), "limb"],
	"mixamorig_LeftForeArm": [Vector3(0.16, 0.36, 0.16), Vector3(0, 0.18, 0), "limb"],
	"mixamorig_RightForeArm": [Vector3(0.16, 0.36, 0.16), Vector3(0, 0.18, 0), "limb"],
	"mixamorig_LeftUpLeg": [Vector3(0.21, 0.40, 0.22), Vector3(0, 0.20, 0), "limb"],
	"mixamorig_RightUpLeg": [Vector3(0.21, 0.40, 0.22), Vector3(0, 0.20, 0), "limb"],
	"mixamorig_LeftLeg": [Vector3(0.19, 0.44, 0.20), Vector3(0, 0.22, 0), "limb"],
	"mixamorig_RightLeg": [Vector3(0.19, 0.44, 0.20), Vector3(0, 0.22, 0), "limb"],
}
const ZONE_DAMAGE := {"head": 99, "torso": 2, "limb": 1, "shield": 0}

# ragdoll: only these bones get physics bodies, the rest follow their parents. [width, mass]
const RAGDOLL_BONES := {
	"mixamorig_Hips": [0.40, 4.0], "mixamorig_Spine": [0.42, 2.0], "mixamorig_Spine1": [0.46, 2.0], "mixamorig_Spine2": [0.50, 2.0],
	"mixamorig_Neck": [0.16, 0.5], "mixamorig_Head": [0.40, 1.5],
	"mixamorig_LeftArm": [0.18, 1.0], "mixamorig_LeftForeArm": [0.16, 0.8], "mixamorig_LeftHand": [0.14, 0.3],
	"mixamorig_RightArm": [0.18, 1.0], "mixamorig_RightForeArm": [0.16, 0.8], "mixamorig_RightHand": [0.14, 0.3],
	"mixamorig_LeftUpLeg": [0.21, 1.5], "mixamorig_LeftLeg": [0.19, 1.0], "mixamorig_LeftFoot": [0.18, 0.4],
	"mixamorig_RightUpLeg": [0.21, 1.5], "mixamorig_RightLeg": [0.19, 1.0], "mixamorig_RightFoot": [0.18, 0.4],
}
const BONE_LEN_FALLBACK := {"mixamorig_Head": 0.40}

# Mixamo strips PBR settings from the materials, so the palette is re-applied by name.
# [albedo, roughness, metallic]
const PALETTE := {
	"Armor": [Color(0.55, 0.57, 0.60), 0.45, 0.6],
	"Skin": [Color(0.87, 0.62, 0.45), 0.85, 0.0],
	"Leather": [Color(0.30, 0.18, 0.09), 0.85, 0.0],
	"Dark": [Color(0.08, 0.08, 0.09), 0.85, 0.0],
	"Tunic": [Color(0.75, 0.12, 0.10), 0.85, 0.0],
}
static var _material_cache := {}

var target := Vector3.ZERO  # enemies: point on the wall; allies: post to hold
var hold := false  # stand still in Idle (allies without an opponent, tests)
var dead := false
var attacking := false
var hp := 2
var melee_target: CharacterBody3D = null
var attack_timer := 0.0
var attack_period := 1.4
var stagger := 0.0
var slow := 1.0
var anim: AnimationPlayer
var skel: Skeleton3D
var body_mesh: MeshInstance3D
var hitboxes: Array[Area3D] = []
var wobble_phase := randf() * TAU
var _spec_speed := -1.0


## Configure from an enemy type spec (data/enemy_types.json). Call before adding to the tree.
func apply_spec(spec: Dictionary, r: RandomNumberGenerator) -> void:
	type_id = spec.get("id", "swordsman")
	max_hp = int(spec.get("hp", 2))
	melee_hp = int(spec.get("melee_hp", 3))
	var sp: Array = spec.get("speed", [5.0, 7.0])
	_spec_speed = r.randf_range(float(sp[0]), float(sp[1]))
	tunic_color = Color.html(spec.get("tunic", "#bf1f1a"))
	has_shield = bool(spec.get("shield", true))
	priority = bool(spec.get("priority", false))
	scale = Vector3.ONE * float(spec.get("scale", 1.0))
	var cfg := WaveManager._load_json("res://data/castle.json")
	gate_damage = int(cfg.get("gate_damage", {}).get(type_id, 2))
	flee_to = spec.get("flee_to", Vector3(0, 0, -200))


func flee() -> void:
	## Rout: drop the fight and run back to where we came from, then despawn.
	if dead:
		return
	fleeing = true
	melee_target = null
	attacking = false
	hold = false
	_leave_gate()
	collision_layer = 0  # no longer a target for duel pairing; bullets still hit hitboxes


func _leave_gate() -> void:
	if gate_slot >= 0 and Game.gate:
		Game.gate.release_slot(self)
	gate_slot = -1


func _gate_bound() -> bool:
	return faction == Game.Faction.ENEMY and Game.gate != null and abs(target.x) <= 3.5


func _ready() -> void:
	add_to_group("knight")
	hp = max_hp
	collision_layer = Game.LAYER_KNIGHT
	collision_mask = Game.LAYER_WORLD | Game.LAYER_KNIGHT
	var model: Node3D = $Model
	model.rotation.y = model_yaw
	anim = find_child("AnimationPlayer", true, false)
	skel = find_child("Skeleton3D", true, false)
	body_mesh = find_child("KnightMesh", true, false)
	if body_mesh == null and skel:
		for c in skel.get_children():
			if c is MeshInstance3D:
				body_mesh = c
				break
	_apply_palette()
	_attach_prop(RIGHT_HAND_BONE, SwordScene, Vector3(0.0, 0.06, 0.0))
	var shield_attachment: BoneAttachment3D = _attach_prop(LEFT_ARM_BONE, ShieldScene, SHIELD_OFFSET) if has_shield else null
	_build_hitboxes(shield_attachment)
	if anim:
		_install_animations()
		anim.speed_scale = randf_range(0.9, 1.15)
		attack_period = anim.get_animation("Attack").length / anim.speed_scale if anim.has_animation("Attack") else 1.4
		_play_loop("Idle" if hold else "Run")
	speed = _spec_speed if _spec_speed > 0.0 else speed * randf_range(0.9, 1.1)


# ------------------------------------------------------------------ setup

func _install_animations() -> void:
	## Copy the clips from the animation-only Mixamo files into this rig's player.
	var lib: AnimationLibrary = anim.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		anim.add_animation_library("", lib)
	for anim_name in ANIM_FILES:
		if lib.has_animation(anim_name):
			continue
		var clip: Animation = _load_clip(anim_name)
		if clip:
			lib.add_animation(anim_name, clip)


static func _load_clip(anim_name: String) -> Animation:
	if _anim_cache.has(anim_name):
		return _anim_cache[anim_name]
	var packed: PackedScene = load(ANIM_FILES[anim_name])
	if packed == null:
		return null
	var inst := packed.instantiate()
	var player: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var clip: Animation = null
	if player and player.has_animation("mixamo_com"):
		clip = player.get_animation("mixamo_com").duplicate()
		clip.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPING else Animation.LOOP_NONE
	inst.free()
	_anim_cache[anim_name] = clip
	return clip


func _apply_palette() -> void:
	if body_mesh == null or body_mesh.mesh == null:
		return
	for i in body_mesh.mesh.get_surface_count():
		var m: Material = body_mesh.mesh.surface_get_material(i)
		if m == null:
			continue
		for key in PALETTE:
			if not m.resource_name.begins_with(key):
				continue
			var color: Color = tunic_color if key == "Tunic" else PALETTE[key][0]
			var cache_key := "%s_%s" % [key, color.to_html()]
			if not _material_cache.has(cache_key):
				var mat := StandardMaterial3D.new()
				mat.albedo_color = color
				mat.roughness = PALETTE[key][1]
				mat.metallic = PALETTE[key][2]
				_material_cache[cache_key] = mat
			body_mesh.set_surface_override_material(i, _material_cache[cache_key])
			break


func _attach_prop(bone_name: String, scene: PackedScene, offset: Vector3) -> BoneAttachment3D:
	if skel == null or skel.find_bone(bone_name) < 0:
		return null
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skel.add_child(attachment)
	var prop := scene.instantiate()
	prop.position = offset
	attachment.add_child(prop)
	return attachment


func _build_hitboxes(shield_attachment: BoneAttachment3D) -> void:
	if skel == null:
		return
	for bone_name in HITBOXES:
		if skel.find_bone(bone_name) < 0:
			continue
		var spec: Array = HITBOXES[bone_name]
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone_name
		skel.add_child(attachment)
		attachment.add_child(_make_hitbox(spec[0], spec[1], spec[2]))
	if shield_attachment:
		shield_attachment.add_child(_make_hitbox(Vector3(0.09, 0.66, 0.54), SHIELD_OFFSET, "shield"))


func _make_hitbox(size: Vector3, offset: Vector3, zone: String) -> Area3D:
	var area := Area3D.new()
	area.name = "Hitbox_" + zone
	area.collision_layer = Game.LAYER_HITBOX
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("knight", self)
	area.set_meta("zone", zone)
	area.add_to_group("hitbox")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	area.add_child(shape)
	hitboxes.append(area)
	if Debug.show_hitboxes:
		Debug.decorate_hitbox.call_deferred(area)
	return area


func _play_loop(anim_name: String) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	if anim.current_animation != anim_name:
		anim.play(anim_name, 0.15)


# ------------------------------------------------------------------ behaviour

func _physics_process(delta: float) -> void:
	if dead:
		return
	stagger = max(stagger - delta, 0.0)
	if melee_target and (not is_instance_valid(melee_target) or melee_target.dead):
		melee_target = null
		attacking = false
	var goal: Vector3
	var engage_range := 1.6
	var at_gate := false  # standing in an attack slot or the waiting crowd
	if melee_target and gate_slot >= 0:
		_leave_gate()  # a duel pulls us out of the queue; we re-queue afterwards
	if fleeing:
		var away := flee_to - global_position
		away.y = 0.0
		if away.length() < 6.0 or global_position.z < -220.0:
			queue_free()
			return
		var fdir := away.normalized()
		velocity.x = fdir.x * speed * 1.15
		velocity.z = fdir.z * speed * 1.15
		_face(fdir, delta)
		_play_loop("Run")
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		move_and_slide()
		return
	if melee_target:
		goal = melee_target.global_position
		engage_range = 1.9
	elif hold:
		goal = global_position
	elif Game.gate and Game.gate.fallen and faction == Game.Faction.ENEMY:
		goal = Vector3(randf_range(-2.0, 2.0) if global_position.z < 2.0 else global_position.x, 0.0, 14.0)  # pour into the courtyard
		engage_range = 3.0
		hold = global_position.z > 8.0
	elif _gate_bound():
		at_gate = true
		gate_retry -= delta
		if gate_slot < 0 and gate_retry <= 0.0:
			gate_retry = 1.0
			gate_slot = Game.gate.request_slot(self)
		goal = Game.gate.slot_position(gate_slot) if gate_slot >= 0 else Game.gate.wait_position(self)
		engage_range = 1.0
	else:
		goal = target
	var to := goal - global_position
	to.y = 0.0
	if stagger > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	elif to.length() < engage_range:
		velocity.x = 0
		velocity.z = 0
		if at_gate and gate_slot < 0:
			# waiting crowd: face the gate, jeer now and then
			_face(Game.gate.global_position - global_position, delta)
			attacking = false
			_play_loop("Attack" if int(wobble_phase * 10.0) % 7 == 0 else "Idle")
			wobble_phase += delta * 0.3
		elif melee_target or not hold:
			if at_gate:
				_face(Vector3(0, 0, 1), delta)  # face the doors
			else:
				_face(to, delta)
			if not attacking:
				attacking = true
				attack_timer = attack_period * randf_range(0.3, 1.0)
			_play_loop("Attack")
			attack_timer -= delta
			if attack_timer <= 0.0:
				attack_timer = attack_period
				if melee_target:
					melee_target.take_melee_hit(self)
				elif at_gate and gate_slot >= 0:
					Game.gate.damage(gate_damage, Game.gate.attack_point(gate_slot))
			if not at_gate and not melee_target and faction == Game.Faction.ENEMY:
				# reached the wall with nobody to fight: after a moment head for the gate
				idle_at_wall += delta
				if idle_at_wall > 2.5:
					target.x = randf_range(-2.5, 2.5)
					idle_at_wall = 0.0
					attacking = false
		else:
			_play_loop("Idle")
	else:
		attacking = false
		wobble_phase += delta
		var dir := to.normalized()
		var side := dir.cross(Vector3.UP) * sin(wobble_phase * 0.7) * 0.25
		var move := (dir + side).normalized() * speed * slow
		velocity.x = move.x
		velocity.z = move.z
		_face(dir, delta)
		_play_loop("Run")
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, delta * 8.0)


func take_melee_hit(attacker: CharacterBody3D) -> void:
	if dead:
		return
	if randf() > melee_hit_chance:
		return
	melee_hp -= 1
	var pos := global_position + Vector3(0, 1.1, 0)
	var dir := (global_position - attacker.global_position).normalized()
	var BulletScript := load("res://scripts/bullet.gd")
	BulletScript.spawn_puff(get_tree().current_scene, pos, dir, Color(0.55, 0.08, 0.05, 0.9), 8, 0.2)
	if melee_hp <= 0:
		Game.melee_deaths += 1
		_die_animated()


## Bullet impact on a hit zone. Returns the zone so the shooter can react.
func hit_zone(zone: String, pos: Vector3, impulse: Vector3) -> String:
	if dead:
		return zone
	var BulletScript := load("res://scripts/bullet.gd")
	if zone == "shield":
		Game.blocked += 1
		BulletScript.spawn_puff(get_tree().current_scene, pos, -impulse.normalized(), Color(1.0, 0.9, 0.6, 1.0), 16, 0.18)
		stagger = 0.7
		velocity += impulse.normalized() * 2.5
		return zone
	BulletScript.spawn_puff(get_tree().current_scene, pos, -impulse.normalized(), Color(0.55, 0.08, 0.05, 0.95), 18, 0.25)
	hp -= ZONE_DAMAGE.get(zone, 1)
	if hp <= 0:
		if zone == "head":
			Game.headshots += 1
			Game.award("headshot")
		if faction == Game.Faction.ALLY:
			Game.ally_kills += 1
		else:
			Game.kills += 1
			Game.award("kill")
			if priority:
				Game.award("priority")
		Game.last_kill = self
		_ragdoll(pos, impulse * (1.6 if zone == "head" else 1.0))
	else:
		slow = 0.6
		stagger = 0.4
	return zone


## Legacy entry point (capsule hit without a zone) — treated as a torso hit.
func hit(pos: Vector3, impulse: Vector3, _bullet: Node) -> void:
	hit_zone("torso", pos, impulse)


func _mark_dead() -> void:
	dead = true
	melee_target = null
	_leave_gate()
	collision_layer = 0
	collision_mask = 0
	$CollisionShape3D.disabled = true
	for h in hitboxes:
		h.collision_layer = 0
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)


func _die_animated() -> void:
	_mark_dead()
	velocity = Vector3.ZERO
	if anim and anim.has_animation("Death"):
		anim.play("Death", 0.1)


# ------------------------------------------------------------------ ragdoll

func _ragdoll(hit_pos: Vector3, impulse: Vector3) -> void:
	_mark_dead()
	if anim:
		anim.stop()
	if skel == null:
		queue_free()
		return
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	skel.add_child(sim)
	var nearest: PhysicalBone3D = null
	var nearest_d := INF
	var bodies := {}
	for i in skel.get_bone_count():
		var bname := skel.get_bone_name(i)
		if not RAGDOLL_BONES.has(bname):
			continue
		var spec: Array = RAGDOLL_BONES[bname]
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bname
		pb.bone_name = bname
		pb.mass = spec[1]
		pb.collision_layer = Game.LAYER_RAGDOLL
		pb.collision_mask = Game.LAYER_WORLD | Game.LAYER_RAGDOLL
		pb.friction = 1.0
		pb.angular_damp = 0.5
		pb.linear_damp = 0.1
		var blen := _bone_length(i)
		var w: float = spec[0]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(w, blen, w * 0.9)
		shape.shape = box
		shape.position = Vector3(0, blen * 0.5, 0)
		pb.add_child(shape)
		if _has_ragdoll_ancestor(i):
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", deg_to_rad(70.0))
			pb.set("joint_constraints/twist_span", deg_to_rad(40.0))
		sim.add_child(pb)
		bodies[bname] = pb
		var bone_pos := skel.global_transform * skel.get_bone_global_pose(i).origin
		var d := bone_pos.distance_to(hit_pos)
		if d < nearest_d:
			nearest_d = d
			nearest = pb
	sim.physical_bones_start_simulation()
	var hips: PhysicalBone3D = bodies.get("mixamorig_Hips")
	if nearest:
		nearest.apply_central_impulse(impulse)
		nearest.apply_impulse(impulse * 0.3, Vector3(randf_range(-0.2, 0.2), randf_range(0.1, 0.3), randf_range(-0.2, 0.2)))
	if hips and hips != nearest:
		hips.apply_central_impulse(impulse * 0.6)
	# kick the feet out so the body never stays standing like a statue
	for leg in ["mixamorig_LeftLeg", "mixamorig_RightLeg"]:
		var l: PhysicalBone3D = bodies.get(leg)
		if l:
			l.apply_central_impulse(-impulse.normalized() * 2.0 + Vector3(randf_range(-1.5, 1.5), 0, 0))


func _has_ragdoll_ancestor(bone: int) -> bool:
	var p := skel.get_bone_parent(bone)
	while p >= 0:
		if RAGDOLL_BONES.has(skel.get_bone_name(p)):
			return true
		p = skel.get_bone_parent(p)
	return false


func _bone_length(i: int) -> float:
	var bname := skel.get_bone_name(i)
	var best := 0.0
	for j in skel.get_bone_count():
		if skel.get_bone_parent(j) == i:
			best = max(best, skel.get_bone_rest(j).origin.length())
	if best > 0.05:
		return best
	return BONE_LEN_FALLBACK.get(bname, 0.3)
