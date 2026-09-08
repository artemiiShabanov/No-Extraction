extends CharacterBody3D
## Blocky enemy knight: runs to a target on the wall, attacks, ragdolls when shot.
## Skeleton and animations come from Mixamo (assets/mixamo), props are attached to bones.

@export var speed := 6.0
@export var tunic_color := Color(0.75, 0.12, 0.10)
@export var corpse_time := 9.0
@export var model_yaw := PI  # Mixamo rigs face +Z, Godot forward is -Z

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

# bone name candidates: Mixamo rig first, our old Blender rig second
const RIGHT_HAND_BONES := ["mixamorig_RightHand", "LowerArm.R"]
const LEFT_ARM_BONES := ["mixamorig_LeftForeArm", "LowerArm.L"]

# ragdoll: only these bones get physics bodies, the rest follow their parents
const RAGDOLL_BONES := {
	"mixamorig_Hips": [0.40, 4.0], "mixamorig_Spine": [0.42, 2.0], "mixamorig_Spine1": [0.46, 2.0], "mixamorig_Spine2": [0.50, 2.0],
	"mixamorig_Neck": [0.16, 0.5], "mixamorig_Head": [0.40, 1.5],
	"mixamorig_LeftArm": [0.18, 1.0], "mixamorig_LeftForeArm": [0.16, 0.8], "mixamorig_LeftHand": [0.14, 0.3],
	"mixamorig_RightArm": [0.18, 1.0], "mixamorig_RightForeArm": [0.16, 0.8], "mixamorig_RightHand": [0.14, 0.3],
	"mixamorig_LeftUpLeg": [0.21, 1.5], "mixamorig_LeftLeg": [0.19, 1.0], "mixamorig_LeftFoot": [0.18, 0.4],
	"mixamorig_RightUpLeg": [0.21, 1.5], "mixamorig_RightLeg": [0.19, 1.0], "mixamorig_RightFoot": [0.18, 0.4],
	# old Blender rig
	"Hips": [0.44, 4.0], "Spine": [0.5, 4.0], "Head": [0.4, 1.5],
	"UpperArm.L": [0.2, 1.0], "UpperArm.R": [0.2, 1.0], "LowerArm.L": [0.18, 1.0], "LowerArm.R": [0.18, 1.0],
	"UpperLeg.L": [0.2, 1.0], "UpperLeg.R": [0.2, 1.0], "LowerLeg.L": [0.18, 1.0], "LowerLeg.R": [0.18, 1.0],
}
const BONE_LEN_FALLBACK := {"mixamorig_Head": 0.40, "Head": 0.46, "LowerArm.L": 0.40, "LowerArm.R": 0.40, "LowerLeg.L": 0.45, "LowerLeg.R": 0.45}

var target := Vector3.ZERO
var dead := false
var attacking := false
var anim: AnimationPlayer
var skel: Skeleton3D
var body_mesh: MeshInstance3D
var wobble_phase := randf() * TAU


func _ready() -> void:
	add_to_group("knight")
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
	_apply_tunic_color()
	_attach_prop(RIGHT_HAND_BONES, SwordScene, Vector3(0.0, 0.06, 0.0))
	_attach_prop(LEFT_ARM_BONES, ShieldScene, Vector3(0.12, 0.13, 0.0))
	if anim:
		_install_animations()
		anim.speed_scale = randf_range(0.9, 1.15)
		_play_loop("Run")
	speed *= randf_range(0.9, 1.1)


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


func _apply_tunic_color() -> void:
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


func _attach_prop(bone_candidates: Array, scene: PackedScene, offset: Vector3) -> void:
	## Parent a prop to the first bone from the list that exists on this skeleton.
	if skel == null:
		return
	for bone_name in bone_candidates:
		if skel.find_bone(bone_name) < 0:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone_name
		skel.add_child(attachment)
		var prop := scene.instantiate()
		prop.position = offset
		attachment.add_child(prop)
		return


func _play_loop(anim_name: String) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	if anim.current_animation != anim_name:
		anim.play(anim_name, 0.15)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var to := target - global_position
	to.y = 0.0
	if to.length() < 1.6:
		if not attacking:
			attacking = true
			_play_loop("Attack")
		velocity.x = 0
		velocity.z = 0
	else:
		wobble_phase += delta
		var dir := to.normalized()
		var side := dir.cross(Vector3.UP) * sin(wobble_phase * 0.7) * 0.25
		velocity.x = (dir + side).normalized().x * speed
		velocity.z = (dir + side).normalized().z * speed
		var yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, delta * 6.0)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func hit(pos: Vector3, impulse: Vector3, _bullet: Node) -> void:
	if dead:
		return
	dead = true
	Game.kills += 1
	Game.last_kill = self
	var BulletScript := load("res://scripts/bullet.gd")
	BulletScript.spawn_puff(get_tree().current_scene, pos, -impulse.normalized(), Color(0.55, 0.08, 0.05, 0.95), 18, 0.25)
	_ragdoll(pos, impulse)


func _ragdoll(hit_pos: Vector3, impulse: Vector3) -> void:
	if anim:
		anim.stop()
	collision_layer = 0
	collision_mask = 0
	$CollisionShape3D.disabled = true
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
	var hips: PhysicalBone3D = bodies.get("mixamorig_Hips", bodies.get("Hips"))
	if nearest:
		nearest.apply_central_impulse(impulse)
		nearest.apply_impulse(impulse * 0.3, Vector3(randf_range(-0.2, 0.2), randf_range(0.1, 0.3), randf_range(-0.2, 0.2)))
	if hips and hips != nearest:
		hips.apply_central_impulse(impulse * 0.6)
	# kick the feet out so the body never stays standing like a statue
	for leg in ["mixamorig_LeftLeg", "mixamorig_RightLeg", "LowerLeg.L", "LowerLeg.R"]:
		var l: PhysicalBone3D = bodies.get(leg)
		if l:
			l.apply_central_impulse(-impulse.normalized() * 2.0 + Vector3(randf_range(-1.5, 1.5), 0, 0))
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)


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
