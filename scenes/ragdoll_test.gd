extends Node3D
## Debug scene: one knight, killed at frame 30, screenshots + bone positions afterwards.
## Run: Godot --path . res://scenes/ragdoll_test.tscn -- --screenshot=/tmp/rag.png

const KnightScene := preload("res://scenes/knight.tscn")

var knight: CharacterBody3D
var frame := 0


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
	knight.target = Vector3(0, 0, -100)
	knight.speed = 0.0
	add_child(knight)

	var cam := Camera3D.new()
	cam.position = Vector3(3.2, 1.6, 3.2)
	add_child(cam)
	cam.look_at(Vector3(0, 0.8, 0))
	cam.current = true


func _process(_delta: float) -> void:
	frame += 1
	if frame == 30:
		knight.hit(knight.global_position + Vector3(0.1, 1.2, -0.2), Vector3(0, 0, 16.0), null)
	if frame in [31, 45, 75, 150]:
		var hips: Node3D = knight.find_child("PB_mixamorig_Hips", true, false)
		var sk: Skeleton3D = knight.skel
		var sim: PhysicalBoneSimulator3D = null
		for c in sk.get_children():
			if c is PhysicalBoneSimulator3D:
				sim = c
		print("F%d pb_hips=%s bone_hips_pose=%s sim_simulating=%s pb_simulating=%s" % [
			frame, hips.global_position if hips else "none",
			sk.get_bone_global_pose(maxi(sk.find_bone("mixamorig_Hips"), 0)).origin,
			sim.is_simulating_physics() if sim else "nosim",
			hips.is_simulating_physics() if hips else "n/a"])
		if Game.screenshot_path != "":
			get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%03d.png" % frame))
	if frame == 160:
		get_tree().quit()
