extends CanvasLayer
## Autoload "Debug": playtest tools. Only active in debug builds and the editor.
##
##   F1  menu            F2  free camera      F3  hitboxes
##   F5  spawn 10 enemies near the wall       F6  kill all enemies
##   F11 bookmark (screenshot + state json + note from the menu)
##   F12 screenshot

const KEYS := {
	"debug_menu": KEY_F1, "debug_freecam": KEY_F2, "debug_hitboxes": KEY_F3,
	"debug_spawn": KEY_F5, "debug_kill_all": KEY_F6, "debug_bookmark": KEY_F11, "debug_screenshot": KEY_F12,
}
const ZONE_COLORS := {"head": Color(1, 0.2, 0.2, 0.35), "torso": Color(1, 0.6, 0.1, 0.3), "limb": Color(0.3, 0.6, 1, 0.3), "shield": Color(1, 1, 0.2, 0.35)}

var enabled := OS.is_debug_build()
var menu_open := false
var freecam := false
var show_hitboxes := false
var infinite_ammo := false
var show_stats := true
var playtest_dir := ""
var bookmark_count := 0

var panel: PanelContainer
var stats: Label
var note: LineEdit
var cam: Camera3D
var prev_cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := 0.0


func _ready() -> void:
	layer = 100
	if not enabled:
		return
	for action_name in KEYS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEYS[action_name]
			InputMap.action_add_event(action_name, ev)
	if OS.has_feature("editor"):
		playtest_dir = ProjectSettings.globalize_path("res://debug/playtest/")
	else:
		playtest_dir = OS.get_user_data_dir().path_join("playtest/")
	DirAccess.make_dir_recursive_absolute(playtest_dir)
	_build_ui()
	print("DEBUG tools ready, playtest captures go to ", playtest_dir)


## True while a debug tool owns the mouse/keyboard: the player must ignore input.
func input_blocked() -> bool:
	return enabled and (menu_open or freecam)


# ------------------------------------------------------------------ ui

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(16, 140)
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = "DEBUG  (F1 закрыть)"
	box.add_child(title)
	_button(box, "F2  Свободная камера", toggle_freecam)
	_button(box, "F3  Показать хитбоксы", toggle_hitboxes)
	_button(box, "F5  +10 врагов у стены", spawn_enemies.bind(10))
	_button(box, "      +5 союзников", spawn_allies.bind(5))
	_button(box, "F6  Убить всех врагов", kill_all_enemies)
	_button(box, "Бесконечные патроны", toggle_infinite_ammo)
	_button(box, "Статистика вкл/выкл", func(): show_stats = not show_stats)
	var row := HBoxContainer.new()
	box.add_child(row)
	for ts in [0.1, 0.25, 0.5, 1.0, 2.0]:
		var b := Button.new()
		b.text = "x%s" % ts
		b.pressed.connect(func(): Engine.time_scale = ts)
		row.add_child(b)
	note = LineEdit.new()
	note.placeholder_text = "Заметка к закладке (F11)"
	note.custom_minimum_size.x = 320
	box.add_child(note)
	_button(box, "F11 Закладка: скриншот + состояние + заметка", bookmark)
	_button(box, "F12 Скриншот", screenshot)
	_button(box, "Перезапустить сцену", restart_scene)
	_button(box, "Открыть debug/knight_test", func(): _load_scene("res://debug/knight_test.tscn"))
	_button(box, "Открыть main", func(): _load_scene("res://scenes/main.tscn"))

	stats = Label.new()
	stats.position = Vector2(16, 900 - 110)
	stats.add_theme_font_size_override("font_size", 14)
	stats.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	stats.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_child(stats)


func _button(parent: Node, text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(callback)
	parent.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("debug_menu"):
		set_menu_open(not menu_open)
	elif event.is_action_pressed("debug_freecam"):
		toggle_freecam()
	elif event.is_action_pressed("debug_hitboxes"):
		toggle_hitboxes()
	elif event.is_action_pressed("debug_spawn"):
		spawn_enemies(10)
	elif event.is_action_pressed("debug_kill_all"):
		kill_all_enemies()
	elif event.is_action_pressed("debug_bookmark"):
		bookmark()
	elif event.is_action_pressed("debug_screenshot"):
		screenshot()
	elif freecam and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * 0.0025
		cam_pitch = clamp(cam_pitch - event.relative.y * 0.0025, -1.5, 1.5)


func _process(delta: float) -> void:
	if not enabled:
		return
	stats.visible = show_stats
	if show_stats:
		var alive := 0
		var dead := 0
		for k in get_tree().get_nodes_in_group("knight"):
			if k.dead:
				dead += 1
			else:
				alive += 1
		stats.text = "fps %d  frame %.1f ms  physics %.1f ms  draw calls %d  objects %d\nknights alive %d dead %d  time x%s  %s%s" % [
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			alive, dead, Engine.time_scale,
			"FREECAM " if freecam else "", "INF AMMO " if infinite_ammo else ""]
	if freecam and cam:
		_fly(delta)


# ------------------------------------------------------------------ tools

func set_menu_open(open: bool) -> void:
	menu_open = open
	panel.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if not open:
		note.release_focus()


func toggle_freecam() -> void:
	freecam = not freecam
	var vp := get_viewport()
	if freecam:
		prev_cam = vp.get_camera_3d()
		cam = Camera3D.new()
		cam.far = 2000.0
		get_tree().current_scene.add_child(cam)
		if prev_cam:
			cam.global_transform = prev_cam.global_transform
			var e := cam.global_transform.basis.get_euler()
			cam_yaw = e.y
			cam_pitch = e.x
		cam.current = true
	else:
		if prev_cam:
			prev_cam.current = true
		if cam:
			cam.queue_free()
			cam = null


func _fly(delta: float) -> void:
	var speed := 12.0 * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	cam.global_position += dir.normalized() * speed * delta / max(Engine.time_scale, 0.01)
	cam.global_rotation = Vector3(cam_pitch, cam_yaw, 0.0)


func toggle_hitboxes() -> void:
	show_hitboxes = not show_hitboxes
	for area in get_tree().get_nodes_in_group("hitbox"):
		decorate_hitbox(area)


## Add or remove the visible box on one hitbox Area3D according to show_hitboxes.
func decorate_hitbox(area: Area3D) -> void:
	var existing := area.get_node_or_null("DebugBox")
	if not show_hitboxes:
		if existing:
			existing.queue_free()
		return
	if existing:
		return
	var shape: CollisionShape3D = null
	for c in area.get_children():
		if c is CollisionShape3D:
			shape = c
	if shape == null or not (shape.shape is BoxShape3D):
		return
	var mi := MeshInstance3D.new()
	mi.name = "DebugBox"
	var mesh := BoxMesh.new()
	mesh.size = shape.shape.size
	mi.mesh = mesh
	mi.position = shape.position
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = ZONE_COLORS.get(area.get_meta("zone", ""), Color(1, 1, 1, 0.3))
	mat.no_depth_test = true
	mi.material_override = mat
	area.add_child(mi)


func toggle_infinite_ammo() -> void:
	infinite_ammo = not infinite_ammo


func _spawner() -> Node:
	return get_tree().current_scene.get_node_or_null("Spawner")


func spawn_enemies(n: int) -> void:
	var sp := _spawner()
	if sp == null:
		return
	for i in n:
		sp.spawn_enemy(Vector3(randf_range(-30, 30), 0, randf_range(-70, -45)))


func spawn_allies(n: int) -> void:
	var sp := _spawner()
	if sp == null:
		return
	for i in n:
		sp.spawn_ally(Vector3(randf_range(-30, 30), 0, randf_range(-25, -12)))


func kill_all_enemies() -> void:
	for k in get_tree().get_nodes_in_group("knight"):
		if not k.dead and k.faction == Game.Faction.ENEMY:
			k.hit_zone("head", k.global_position + Vector3(0, 1.5, 0), Vector3(0, 2, -6))


func restart_scene() -> void:
	Engine.time_scale = 1.0
	Game.kills = 0
	Game.headshots = 0
	Game.blocked = 0
	Game.ally_kills = 0
	Game.melee_deaths = 0
	Game.last_kill = null
	if freecam:
		toggle_freecam()
	set_menu_open(false)
	get_tree().reload_current_scene()


func _load_scene(path: String) -> void:
	restart_scene()
	get_tree().change_scene_to_file(path)


func _stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


func screenshot() -> String:
	var path := playtest_dir.path_join("shot_%s.png" % _stamp())
	var was_open := menu_open
	if was_open:
		panel.visible = false
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	if was_open:
		panel.visible = true
	print("DEBUG screenshot ", path)
	return path


func bookmark() -> void:
	bookmark_count += 1
	var stamp := _stamp()
	var base := playtest_dir.path_join("bookmark_%s" % stamp)
	var was_open := menu_open
	if was_open:
		panel.visible = false
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(base + ".png")
	if was_open:
		panel.visible = true
	var player := get_tree().current_scene.get_node_or_null("Player")
	var state := {
		"note": note.text, "time": stamp, "scene": get_tree().current_scene.scene_file_path,
		"kills": Game.kills, "headshots": Game.headshots, "blocked": Game.blocked, "melee_deaths": Game.melee_deaths,
		"time_scale": Engine.time_scale, "fps": Engine.get_frames_per_second(),
	}
	if player:
		state["player_position"] = [player.global_position.x, player.global_position.y, player.global_position.z]
		state["player_yaw"] = player.rotation.y
		state["ammo"] = player.ammo
	var sp := _spawner()
	if sp:
		state["enemies"] = sp.alive_count(Game.Faction.ENEMY)
		state["allies"] = sp.alive_count(Game.Faction.ALLY)
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "  "))
	f.close()
	note.text = ""
	print("DEBUG bookmark ", base)
