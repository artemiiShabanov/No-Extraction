extends Node3D
## Debug scene: one knight standing in Idle. Rays are cast at its head, shield and chest to
## verify hit zones, then a head shot must ragdoll it.
## Run: Godot --path . res://scenes/knight_test.tscn -- --screenshot=/tmp/kt.png

const KnightScene := preload("res://scenes/knight.tscn")

var knight: CharacterBody3D
var frame := 0
var failures := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.6, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	ground.collision_layer = Game.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 1, 40)
	mi.mesh = bm
	mi.position.y = -0.5
	ground.add_child(mi)
	add_child(ground)

	knight = KnightScene.instantiate()
	knight.position = Vector3.ZERO
	knight.hold = true
	knight.rotation.y = PI  # face +Z, towards the camera
	add_child(knight)

	var cam := Camera3D.new()
	cam.position = Vector3(1.5, 1.4, 3.5)
	add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.current = true


func _process(_delta: float) -> void:
	frame += 1
	if frame == 40:
		_probe_zones()
	if frame == 60:
		var head := _bone_pos("mixamorig_Head") + Vector3(0, 0.15, 0)
		var zone: String = knight.hit_zone("head", head, Vector3(0, 0, -16.0))
		print("KILL via zone=%s dead=%s headshots=%d" % [zone, knight.dead, Game.headshots])
	if frame in [45, 90, 150]:
		var hips: Node3D = knight.find_child("PB_mixamorig_Hips", true, false)
		print("F%d ragdoll_hips=%s" % [frame, hips.global_position if hips else "none"])
		if Game.screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%03d.png" % frame))
	if frame == 160:
		print("KNIGHT_TEST %s" % ("PASS" if failures == 0 and knight.dead else "FAIL"))
		get_tree().quit()


func _bone_pos(bone_name: String) -> Vector3:
	var sk: Skeleton3D = knight.skel
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone_name)).origin


func _probe_zones() -> void:
	## Cast rays from in front of the knight (+Z side) at known points and check the zone.
	var shield_attachment: Node3D = null
	for c in knight.skel.get_children():
		if c is BoneAttachment3D and c.bone_name == "mixamorig_LeftForeArm":
			shield_attachment = c
	var probes := {
		"head": _bone_pos("mixamorig_Head") + Vector3(0, 0.2, 0),
		"torso": _bone_pos("mixamorig_Spine1"),
		"limb": _bone_pos("mixamorig_RightLeg") + Vector3(0, 0.2, 0),
		"shield": shield_attachment.to_global(knight.SHIELD_OFFSET) if shield_attachment else Vector3.ZERO,
	}
	var space := get_world_3d().direct_space_state
	for expected in probes:
		var p: Vector3 = probes[expected]
		var origin := p + Vector3(0, 0, 6.0)  # straight in from the front
		if expected == "shield":
			# the shield sits on the outer side of the left forearm: come at it from that side
			var side := (p - _bone_pos("mixamorig_LeftForeArm"))
			side.y = 0
			origin = p + side.normalized() * 4.0 + Vector3(0, 0, 2.0)
		var q := PhysicsRayQueryParameters3D.create(origin, p + (p - origin).normalized() * 0.5, Game.LAYER_WORLD | Game.LAYER_HITBOX)
		q.collide_with_areas = true
		var hit := space.intersect_ray(q)
		var got: String = "nothing"
		if hit and hit.collider is Area3D and hit.collider.has_meta("zone"):
			got = hit.collider.get_meta("zone")
		elif hit:
			got = str(hit.collider.name)
		var ok: bool = got == expected
		if not ok:
			failures += 1
		print("ZONE expected=%-6s got=%-8s %s  (at %s)" % [expected, got, "OK" if ok else "FAIL", p])
