extends CharacterBody3D
## First person sniper on the wall.

const BulletScene := preload("res://scenes/bullet.tscn")

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0022
@export var hip_fov := 72.0
@export var ads_fov := 14.0
@export var bolt_time := 1.1
@export var magazine_size := 5
@export var reload_time := 2.2

@onready var camera: Camera3D = $Camera
@onready var rifle_holder: Node3D = $Camera/RifleHolder
@onready var muzzle: Node3D = $Camera/RifleHolder.find_child("Muzzle", true, false)

const HIP_POS := Vector3(0.26, -0.24, -0.42)
const HIP_ROT := Vector3(0.0, 0.06, 0.0)
const ADS_POS := Vector3(0.0, -0.165, -0.30)

var ammo := 5  # rounds in the magazine
var reserve := 5  # rounds left for this wave
var reloading := 0.0
var aiming := false
var aim_blend := 0.0
var fire_cooldown := 0.0
var recoil_pitch := 0.0
var rifle_kick := 0.0
var bob_time := 0.0
var mouse_captured := true
var stunned_until := 0.0
var recover_until := 0.0
var immune_until := 0.0
var stun_kick := Vector2.ZERO
var stun_overlay: ColorRect
var stun_cfg := {"duration": 1.2, "recovery": 1.0, "immunity": 2.0}


func _ready() -> void:
	ammo = magazine_size
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = hip_fov
	rifle_holder.position = HIP_POS
	rifle_holder.rotation = HIP_ROT
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WORLD
	var cfg := WaveManager._load_json("res://data/castle.json")
	stun_cfg = cfg.get("stun", stun_cfg)
	_build_stun_overlay()


func _build_stun_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	stun_overlay = ColorRect.new()
	stun_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	stun_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = textureLod(screen_tex, uv, strength * 3.5).rgb;
	float d = distance(uv, vec2(0.5));
	float vig = smoothstep(0.25, 0.75, d) * strength;
	col = mix(col, vec3(0.35, 0.02, 0.0), vig);
	COLOR = vec4(col, strength > 0.001 ? 1.0 : 0.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	stun_overlay.material = mat
	stun_overlay.visible = false
	layer.add_child(stun_overlay)


func is_stunned() -> bool:
	return Time.get_ticks_msec() / 1000.0 < stunned_until


## Arrow hit: knocked out of the scope, camera kicked, can't fire for a moment.
func stun(dir: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < immune_until:
		return
	stunned_until = now + float(stun_cfg.duration)
	recover_until = stunned_until + float(stun_cfg.recovery)
	immune_until = recover_until + float(stun_cfg.immunity)
	stun_kick = Vector2(randf_range(-0.25, 0.25), randf_range(0.1, 0.22))
	camera.rotation.x = clamp(camera.rotation.x + stun_kick.y, -1.4, 1.4)
	rotate_y(stun_kick.x)
	fire_cooldown = max(fire_cooldown, float(stun_cfg.duration))
	Game.stuns += 1
	print("PLAYER stunned by an arrow")


func _unhandled_input(event: InputEvent) -> void:
	if Debug.input_blocked():
		return
	if event is InputEventMouseMotion and mouse_captured:
		var sens := mouse_sensitivity * (camera.fov / hip_fov)
		rotate_y(-event.relative.x * sens)
		camera.rotation.x = clamp(camera.rotation.x - event.relative.y * sens, -1.4, 1.4)
	if event.is_action_pressed("toggle_mouse"):
		mouse_captured = not mouse_captured
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("fire") and mouse_captured:
		try_fire()
	if event.is_action_pressed("reload"):
		reload()


func _physics_process(delta: float) -> void:
	# movement
	var input_dir := Vector2.ZERO if Debug.input_blocked() else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") and not aiming else walk_speed
	if aiming:
		speed *= 0.45
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	velocity.x = move_toward(velocity.x, dir.x * speed, 40.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 40.0 * delta)
	move_and_slide()

	# aiming (a stun throws us out of the scope)
	aiming = Input.is_action_pressed("aim") and mouse_captured and not Debug.input_blocked() and not is_stunned()
	_update_stun(delta)
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta * 6.0)
	var eased := smoothstep(0.0, 1.0, aim_blend)
	camera.fov = lerp(hip_fov, ads_fov, eased)

	# rifle sway, bob, kick
	fire_cooldown = max(fire_cooldown - delta, 0.0)
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			var take := mini(magazine_size - ammo, reserve)
			ammo += take
			reserve -= take
	recoil_pitch = lerp(recoil_pitch, 0.0, delta * 8.0)
	rifle_kick = lerp(rifle_kick, 0.0, delta * 10.0)
	var planar := Vector2(velocity.x, velocity.z).length()
	bob_time += delta * planar * 1.6
	var bob := Vector3(sin(bob_time) * 0.012, abs(cos(bob_time)) * 0.008, 0.0) * planar / walk_speed * (1.0 - eased)
	rifle_holder.position = HIP_POS.lerp(ADS_POS, eased) + bob + Vector3(0, 0, rifle_kick)
	rifle_holder.rotation = HIP_ROT * (1.0 - eased) + Vector3(recoil_pitch * 0.5, 0, 0)
	rifle_holder.visible = aim_blend < 0.75  # the scope overlay replaces the model when fully aimed
	camera.rotation.x += recoil_pitch * delta * 4.0


func _update_stun(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var strength := 0.0
	if now < stunned_until:
		strength = 1.0
		aim_blend = move_toward(aim_blend, 0.0, delta * 12.0)
		# the world reels
		camera.rotation.x += sin(now * 23.0) * 0.004
		rotate_y(cos(now * 17.0) * 0.003)
	elif now < recover_until:
		strength = (recover_until - now) / max(float(stun_cfg.recovery), 0.01)
		camera.rotation.x += sin(now * 9.0) * 0.0015 * strength
	stun_overlay.visible = strength > 0.001
	if stun_overlay.visible:
		(stun_overlay.material as ShaderMaterial).set_shader_parameter("strength", strength)


## Add this wave's ammunition: leftovers carry over, the magazine is topped up from the pool.
func resupply(total: int) -> void:
	var pool := ammo + reserve + total
	ammo = mini(pool, magazine_size)
	reserve = max(pool - ammo, 0)
	reloading = 0.0


func reload() -> void:
	if reloading > 0.0 or ammo >= magazine_size or reserve <= 0 or is_stunned():
		return
	reloading = reload_time
	rifle_kick += 0.05


func total_ammo() -> int:
	return ammo + reserve


func try_fire() -> void:
	if fire_cooldown > 0.0 or is_stunned() or reloading > 0.0:
		return
	if ammo <= 0:
		if not Debug.infinite_ammo:
			reload()
			return
	if not Debug.infinite_ammo:
		ammo -= 1
	fire_cooldown = bolt_time
	recoil_pitch += 0.09
	rifle_kick += 0.07
	var bullet := BulletScene.instantiate()
	get_tree().current_scene.add_child(bullet)
	# the bullet flies from the eye (what you see is what you hit); the tracer starts at the muzzle
	var origin: Vector3 = camera.global_position - camera.global_transform.basis.z * 0.3
	var visual: Vector3 = muzzle.global_position if muzzle else origin
	bullet.launch(origin, -camera.global_transform.basis.z, visual)


func aim_at(target: Vector3) -> void:
	## Debug helper: point the camera at a world position.
	var to := target - camera.global_position
	rotation.y = atan2(-to.x, -to.z)
	var flat := Vector2(to.x, to.z).length()
	camera.rotation.x = atan2(to.y, flat)
