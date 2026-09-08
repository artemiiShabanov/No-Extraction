extends CharacterBody3D
## Blocky enemy knight: runs to a target on the wall, attacks, ragdolls when shot.

@export var speed := 6.0
@export var tunic_color := Color(0.75, 0.12, 0.10)
@export var corpse_time := 9.0

var target := Vector3.ZERO
var dead := false
var attacking := false
var anim: AnimationPlayer
var skel: Skeleton3D
var body_mesh: MeshInstance3D
var wobble_phase := randf() * TAU

const BONE_LEN_FALLBACK := {"Head": 0.46, "LowerArm.L": 0.40, "LowerArm.R": 0.40, "LowerLeg.L": 0.45, "LowerLeg.R": 0.45}
const BONE_WIDTH := {"Hips": 0.44, "Spine": 0.5, "Head": 0.4, "UpperArm.L": 0.2, "UpperArm.R": 0.2, "LowerArm.L": 0.18, "LowerArm.R": 0.18, "UpperLeg.L": 0.2, "UpperLeg.R": 0.2, "LowerLeg.L": 0.18, "LowerLeg.R": 0.18}


func _ready() -> void:
	add_to_group("knight")
	collision_layer = Game.LAYER_KNIGHT
	collision_mask = Game.LAYER_WORLD | Game.LAYER_KNIGHT
	anim = find_child("AnimationPlayer", true, false)
	skel = find_child("Skeleton3D", true, false)
	body_mesh = find_child("KnightMesh", true, false)
	if body_mesh == null:
		for c in skel.get_children():
			if c is MeshInstance3D:
				body_mesh = c
				break
	_apply_tunic_color()
	if anim:
		anim.speed_scale = randf_range(0.9, 1.15)
		_play_loop("Run")
	speed *= randf_range(0.9, 1.1)


func _apply_tunic_color() -> void:
	if body_mesh == null or body_mesh.mesh == null:
		return
	for i in body_mesh.mesh.get_surface_count():
		var m := body_mesh.mesh.surface_get_material(i)
		if m and m.resource_name == "Tunic":
			var dup: StandardMaterial3D = m.duplicate()
			dup.albedo_color = tunic_color
			body_mesh.set_surface_override_material(i, dup)


func _play_loop(anim_name: String) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
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
	# hit flash particles
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
	skel.add_child(sim)
	var nearest: PhysicalBone3D = null
	var nearest_d := INF
	for i in skel.get_bone_count():
		var bname := skel.get_bone_name(i)
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bname
		pb.bone_name = bname
		pb.mass = 4.0 if bname in ["Hips", "Spine"] else (1.5 if bname == "Head" else 1.0)
		pb.collision_layer = Game.LAYER_RAGDOLL
		pb.collision_mask = Game.LAYER_WORLD | Game.LAYER_RAGDOLL
		pb.friction = 1.0
		pb.angular_damp = 0.5
		pb.linear_damp = 0.1
		var blen := _bone_length(i)
		var w: float = BONE_WIDTH.get(bname, 0.2)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(w, blen, w * 0.9)
		shape.shape = box
		shape.position = Vector3(0, blen * 0.5, 0)
		pb.add_child(shape)
		if skel.get_bone_parent(i) >= 0:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", deg_to_rad(70.0))
			pb.set("joint_constraints/twist_span", deg_to_rad(40.0))
		sim.add_child(pb)
		var bone_pos := skel.global_transform * skel.get_bone_global_pose(i).origin
		var d := bone_pos.distance_to(hit_pos)
		if d < nearest_d:
			nearest_d = d
			nearest = pb
	sim.physical_bones_start_simulation()
	var hips: PhysicalBone3D = sim.find_child("PB_Hips", false, false)
	if nearest:
		nearest.apply_central_impulse(impulse)
		nearest.apply_impulse(impulse * 0.3, Vector3(randf_range(-0.2, 0.2), randf_range(0.1, 0.3), randf_range(-0.2, 0.2)))
	if hips and hips != nearest:
		hips.apply_central_impulse(impulse * 0.6)
	# kick the feet out so the body never stays standing like a statue
	for leg in ["PB_LowerLeg.L", "PB_LowerLeg.R"]:
		var l: PhysicalBone3D = sim.find_child(leg, false, false)
		if l:
			l.apply_central_impulse(-impulse.normalized() * 2.0 + Vector3(randf_range(-1.5, 1.5), 0, 0))
	get_tree().create_timer(corpse_time).timeout.connect(queue_free)


func _bone_length(i: int) -> float:
	var bname := skel.get_bone_name(i)
	for j in skel.get_bone_count():
		if skel.get_bone_parent(j) == i:
			return max(skel.get_bone_rest(j).origin.length(), 0.08)
	return BONE_LEN_FALLBACK.get(bname, 0.3)
