extends Node3D
## Prototype scene root: environment, castle, player, spawner, HUD, debug automation.

const PlayerScene := preload("res://scenes/player.tscn")

var player: CharacterBody3D
var spawner: Node3D
var waves: WaveManager
var hud: Label
var scope: Control
var gate_bar: Control
var frame := 0
var _perf_accum := 0.0
var _perf_cpu := 0.0
var _perf_gpu := 0.0
var _perf_render_cpu := 0.0
var _kill_frame := -1
var _cleared_frames := 0


func _ready() -> void:
	if Game.auto_test:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_build_environment()
	var terrain := StaticBody3D.new()
	terrain.name = "Terrain"
	terrain.set_script(load("res://scripts/terrain.gd"))
	add_child(terrain)
	var castle := Node3D.new()
	castle.name = "Castle"
	castle.set_script(load("res://scripts/castle.gd"))
	add_child(castle)

	spawner = Node3D.new()
	spawner.name = "Spawner"
	spawner.set_script(load("res://scripts/spawner.gd"))
	add_child(spawner)
	waves = WaveManager.new()
	waves.name = "Waves"
	waves.spawner = spawner
	if Game.auto_test:
		# smaller waves, spawned close to the wall so the aim bot can finish them
		waves.budget_scale = 0.35
		for lane in ["left", "center", "right"]:
			waves.lane_override[lane] = {"spawn_z": [-110, -60]}
		waves.lane_override["flank"] = {"spawn_z": [-70, -40]}
	add_child(waves)
	Game.gate.fell.connect(_on_gate_fell)

	player = PlayerScene.instantiate()
	player.position = Vector3(15.0, 10.1, 0.0)
	add_child(player)

	_build_hud()


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var hdri := EnvMaterials.sky_hdri()
	if hdri:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = hdri
		sky.sky_material = pano
	else:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.25, 0.42, 0.7)
		sky_mat.sky_horizon_color = Color(0.72, 0.72, 0.68)
		sky_mat.ground_bottom_color = Color(0.2, 0.18, 0.15)
		sky_mat.ground_horizon_color = Color(0.6, 0.58, 0.52)
		sky_mat.sun_angle_max = 20.0
		sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.72, 0.7)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 320.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	add_child(sun)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	scope = ScopeOverlay.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE  # otherwise the overlay eats mouse events before the player sees them
	scope.player = player
	layer.add_child(scope)
	hud = Label.new()
	hud.position = Vector2(16, 58)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud)
	gate_bar = GateBar.new()
	gate_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	gate_bar.position = Vector2(-GateBar.WIDTH / 2, 14)
	gate_bar.size = Vector2(GateBar.WIDTH, GateBar.HEIGHT + 22)
	gate_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(gate_bar)


func _process(_delta: float) -> void:
	frame += 1
	hud.text = "%s\nочки %d\nAMMO %d / %d    [R] reload\nKILLS %d  (headshots %d, blocked by shields %d, allies hit %d)\nENEMIES %d   ALLIES %d   melee deaths %d\nFPS %d" % [
		waves.status_text(), Game.run_points, player.ammo, player.magazine_size, Game.kills, Game.headshots, Game.blocked, Game.ally_kills,
		spawner.alive_count(Game.Faction.ENEMY), spawner.alive_count(Game.Faction.ALLY), Game.melee_deaths, Engine.get_frames_per_second()]
	if Input.is_action_just_pressed("next_wave") and not Debug.input_blocked():
		waves.start_next_wave()
	if Game.auto_test:
		_auto_test()


func _auto_test() -> void:
	# scripted run for screenshots: wait for the crowd, aim at the nearest knight, fire, capture.
	# input regression check: synthetic mouse motion and left click must reach the player
	if frame == 100:
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(200, 0)
		Input.parse_input_event(motion)
	if frame == 102:
		print("INPUT mouse look %s (yaw %.3f)" % ["OK" if abs(player.rotation.y) > 0.01 else "FAIL", player.rotation.y])
		player.rotation.y = 0.0
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		Input.parse_input_event(click)
	if frame == 104:
		print("INPUT left click fire %s (ammo %d)" % ["OK" if player.ammo == player.magazine_size - 1 else "FAIL", player.ammo])
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		Input.parse_input_event(release)
		player.ammo = player.magazine_size
	# waves: start immediately, and start the next one 3 s after a wave is cleared
	if frame == 5:
		waves.start_next_wave()
	if waves.state == WaveManager.State.CLEARED:
		_cleared_frames += 1
		if _cleared_frames > 180:
			_cleared_frames = 0
			waves.start_next_wave()
	# debug tools smoke test: hitbox overlay + menu visible on one screenshot
	if frame == 150:
		Debug.toggle_hitboxes()
		Debug.set_menu_open(true)
	if frame == 160 and Game.screenshot_path != "":
		_screenshot(Game.screenshot_path.replace(".png", "_debug.png"))
	if frame == 170:
		Debug.set_menu_open(false)
		Debug.toggle_hitboxes()
	if frame == 230:
		var n := 0
		for k in get_tree().get_nodes_in_group("knight"):
			if k.faction == Game.Faction.ALLY and not k.dead and n < 6:
				k.hit_zone("head", k.global_position + Vector3(0, 1.5, 0), Vector3(0, 1, -4))
				n += 1
		Game.ally_kills = 0
	if frame == 240:
		var k := _nearest_knight()
		if k:
			player.aim_at(k.global_position + Vector3(0, 1.1, 0))
			player.aiming = true
	if frame == 250:
		Input.action_press("aim")
	if frame >= 260 and frame % 40 == 0 and frame <= Game.test_frames - 60:
		var k := _nearest_knight()
		if k:
			player.aim_at(_ballistic_aim_point(k))
			player.fire_cooldown = 0.0
			player.try_fire()
	if frame == 200 and Game.screenshot_path != "":
		var k := _nearest_knight()
		if k:
			player.aim_at(k.global_position + Vector3(0, 1.0, 0))
		_screenshot(Game.screenshot_path.replace(".png", "_wide.png"))
	if frame == 330 and Game.screenshot_path != "":
		_screenshot(Game.screenshot_path.replace(".png", "_ads.png"))
	# ragdoll close-up: 25 frames after the first kill, look at the corpse's hips
	if Game.last_kill and _kill_frame < 0:
		_kill_frame = frame
	if _kill_frame > 0 and frame == _kill_frame + 25 and is_instance_valid(Game.last_kill):
		var hips: Node3D = Game.last_kill.find_child("PB_mixamorig_Hips", true, false)
		player.aim_at((hips.global_position if hips else Game.last_kill.global_position) + Vector3(0, 0.3, 0))
	if _kill_frame > 0 and frame == _kill_frame + 26 and Game.screenshot_path != "":
		_screenshot(Game.screenshot_path.replace(".png", "_ragdoll.png"))
	if frame >= 400 and frame < 480:
		_perf_accum += get_process_delta_time()
		_perf_cpu += Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_perf_gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		_perf_render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
	if frame == 480:
		print("PERF frame %.2f ms | script+physics %.2f ms | render cpu %.2f ms | gpu %.2f ms | enemies %d allies %d | kills %d headshots %d blocked %d melee deaths %d" % [
			_perf_accum / 80.0 * 1000.0, _perf_cpu / 80.0 * 1000.0, _perf_render_cpu / 80.0, _perf_gpu / 80.0,
			spawner.alive_count(Game.Faction.ENEMY), spawner.alive_count(Game.Faction.ALLY), Game.kills, Game.headshots, Game.blocked, Game.melee_deaths])
	# gate: at 60% of the run force heavy damage so the stages, the fall and the breach show
	if Game.gate_test and frame == int(Game.test_frames * 0.55):
		Game.gate.damage(int(Game.gate.max_hp * 0.7), Game.gate.attack_point(1))
		print("GATE forced to hp=%d stage=%d" % [Game.gate.hp, Game.gate.stage])
	if Game.gate_test and frame == int(Game.test_frames * 0.6):
		Game.gate.damage(Game.gate.hp, Game.gate.attack_point(2))
	if Game.gate_test and frame == int(Game.test_frames * 0.6) + 10:
		# look down at the gate from above with the free camera (scope overlay fades first)
		Input.action_release("aim")
		if not Debug.freecam:
			Debug.toggle_freecam()
		Debug.cam.global_position = Vector3(0.0, 14.0, -13.0)
		Debug.cam_yaw = PI  # face +Z, towards the gate
		Debug.cam_pitch = -0.7
		Debug.cam.global_rotation = Vector3(Debug.cam_pitch, Debug.cam_yaw, 0.0)
	if Game.gate_test and frame == int(Game.test_frames * 0.6) + 40 and Game.screenshot_path != "":
		_screenshot(Game.screenshot_path.replace(".png", "_gate.png"))
	if Game.gate_test and frame == int(Game.test_frames * 0.6) + 70 and Debug.freecam:
		Debug.toggle_freecam()
		Input.action_press("aim")
	if frame == Game.test_frames - 30:
		# wide look at the allied line for the battlefield screenshot
		Input.action_release("aim")
		player.global_position.z = -1.9  # step up to the parapet to see the field below
		player.aim_at(Vector3(0.0, 1.0, -22.0))
	if frame == Game.test_frames - 10 and Game.screenshot_path != "":
		_screenshot(Game.screenshot_path.replace(".png", "_field.png"))
		print("END enemies %d allies %d | kills %d headshots %d blocked %d melee deaths %d" % [
			spawner.alive_count(Game.Faction.ENEMY), spawner.alive_count(Game.Faction.ALLY), Game.kills, Game.headshots, Game.blocked, Game.melee_deaths])
	if frame == Game.test_frames:
		Input.action_release("aim")
		get_tree().quit()


func _on_gate_fell() -> void:
	# short breach sequence: enemies pour in for a few seconds, then the run is lost
	print("GATE breach sequence")
	get_tree().create_timer(4.0).timeout.connect(waves.lose)


func _ballistic_aim_point(k: Node3D) -> Vector3:
	## Lead the target and hold over for bullet drop (debug aim bot).
	var origin: Vector3 = player.camera.global_position
	var target: Vector3 = k.global_position + Vector3(0, 1.55, 0)  # head height
	var t := origin.distance_to(target) / 170.0
	var vel: Vector3 = k.velocity
	target += vel * t
	target.y += 0.5 * 9.8 * t * t
	return target


func _nearest_knight(want_dead: bool = false) -> Node3D:
	## Nearest knight with a clear line of sight from the camera.
	var best: Node3D = null
	var bd := INF
	var space := get_world_3d().direct_space_state
	var eye: Vector3 = player.camera.global_position
	var muzzle: Vector3 = player.muzzle.global_position
	for k in get_tree().get_nodes_in_group("knight"):
		if k.dead != want_dead or k.faction != Game.Faction.ENEMY:
			continue
		var d: float = k.global_position.distance_to(player.global_position)
		if d >= bd or (d < 30.0 and not want_dead):
			continue
		var aim: Vector3 = k.global_position + Vector3(0, 1.1, 0)
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, aim, Game.LAYER_WORLD)):
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle, aim, Game.LAYER_WORLD)):
			continue
		bd = d
		best = k
	return best


func _screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SCREENSHOT ", path)


class GateBar:
	extends Control
	## Gate integrity bar: colour from green to red, flashes on every hit.
	const WIDTH := 340.0
	const HEIGHT := 16.0
	var last_hp := -1
	var flash := 0.0

	func _process(delta: float) -> void:
		flash = max(flash - delta * 3.0, 0.0)
		if Game.gate and Game.gate.hp != last_hp:
			if last_hp >= 0 and Game.gate.hp < last_hp:
				flash = 1.0
			last_hp = Game.gate.hp
		queue_redraw()

	func _draw() -> void:
		if Game.gate == null:
			return
		var ratio: float = float(Game.gate.hp) / max(Game.gate.max_hp, 1)
		var col := Color(0.35, 0.8, 0.3).lerp(Color(0.95, 0.75, 0.2), clamp((0.66 - ratio) / 0.33 + 1.0, 0.0, 1.0)) if ratio > 0.33 else Color(0.9, 0.25, 0.15)
		col = col.lerp(Color(1, 1, 1), flash * 0.6)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, 14), "ВОРОТА", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.9, 0.8))
		var y := 20.0
		draw_rect(Rect2(0, y, WIDTH, HEIGHT), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(2, y + 2, (WIDTH - 4) * ratio, HEIGHT - 4), col)
		# stage marks at 66% and 33%
		for m in [0.66, 0.33]:
			draw_line(Vector2(2 + (WIDTH - 4) * m, y), Vector2(2 + (WIDTH - 4) * m, y + HEIGHT), Color(0, 0, 0, 0.6), 1.0)
		var txt := "%d / %d" % [Game.gate.hp, Game.gate.max_hp] if not Game.gate.fallen else "ПАЛИ"
		draw_string(font, Vector2(WIDTH / 2 - 30, y + 13), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))


class ScopeOverlay:
	extends Control
	var player: Node

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var blend: float = player.aim_blend if player else 0.0
		if blend > 0.01:
			var r := minf(size.x, size.y) * 0.42
			var alpha := smoothstep(0.0, 1.0, blend)
			# black vignette outside the scope circle
			var col := Color(0, 0, 0, alpha)
			draw_rect(Rect2(0, 0, size.x, c.y - r), col)
			draw_rect(Rect2(0, c.y + r, size.x, size.y - c.y - r), col)
			draw_rect(Rect2(0, c.y - r, c.x - r, 2 * r), col)
			draw_rect(Rect2(c.x + r, c.y - r, size.x - c.x - r, 2 * r), col)
			_draw_ring(c, r, r * 1.5, col, 96)
			draw_arc(c, r, 0, TAU, 96, Color(0.1, 0.1, 0.1, alpha), 3.0, true)
			# reticle
			var rc := Color(0.05, 0.05, 0.05, alpha)
			draw_line(c - Vector2(r, 0), c - Vector2(24, 0), rc, 2.0, true)
			draw_line(c + Vector2(24, 0), c + Vector2(r, 0), rc, 2.0, true)
			draw_line(c - Vector2(0, r), c - Vector2(0, 24), rc, 2.0, true)
			draw_line(c + Vector2(0, 24), c + Vector2(0, r), rc, 2.0, true)
			draw_line(c - Vector2(0, 24), c + Vector2(0, 24), rc, 1.0, true)
			draw_line(c - Vector2(24, 0), c + Vector2(24, 0), rc, 1.0, true)
			for i in range(1, 5):
				draw_line(c + Vector2(-8, i * 22), c + Vector2(8, i * 22), rc, 1.0, true)
		if blend < 0.9:
			draw_circle(c, 2.5, Color(1, 1, 1, 0.8 * (1.0 - blend)))

	func _draw_ring(c: Vector2, r0: float, r1: float, col: Color, segs: int) -> void:
		# ring between r0 and r1 drawn as a fan of quads (draw_polygon has no holes)
		var cols := PackedColorArray([col, col, col, col])
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			draw_polygon(PackedVector2Array([c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d1 * r0]), cols)
