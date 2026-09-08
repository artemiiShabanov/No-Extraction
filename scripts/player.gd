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
@export var magazine_size := 10

@onready var camera: Camera3D = $Camera
@onready var rifle_holder: Node3D = $Camera/RifleHolder
@onready var muzzle: Node3D = $Camera/RifleHolder.find_child("Muzzle", true, false)

const HIP_POS := Vector3(0.26, -0.24, -0.42)
const HIP_ROT := Vector3(0.0, 0.06, 0.0)
const ADS_POS := Vector3(0.0, -0.165, -0.30)

var ammo := 10
var aiming := false
var aim_blend := 0.0
var fire_cooldown := 0.0
var recoil_pitch := 0.0
var rifle_kick := 0.0
var bob_time := 0.0
var mouse_captured := true


func _ready() -> void:
	ammo = magazine_size
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = hip_fov
	rifle_holder.position = HIP_POS
	rifle_holder.rotation = HIP_ROT
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WORLD


func _unhandled_input(event: InputEvent) -> void:
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
		ammo = magazine_size


func _physics_process(delta: float) -> void:
	# movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
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

	# aiming
	aiming = Input.is_action_pressed("aim") and mouse_captured
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta * 6.0)
	var eased := smoothstep(0.0, 1.0, aim_blend)
	camera.fov = lerp(hip_fov, ads_fov, eased)

	# rifle sway, bob, kick
	fire_cooldown = max(fire_cooldown - delta, 0.0)
	recoil_pitch = lerp(recoil_pitch, 0.0, delta * 8.0)
	rifle_kick = lerp(rifle_kick, 0.0, delta * 10.0)
	var planar := Vector2(velocity.x, velocity.z).length()
	bob_time += delta * planar * 1.6
	var bob := Vector3(sin(bob_time) * 0.012, abs(cos(bob_time)) * 0.008, 0.0) * planar / walk_speed * (1.0 - eased)
	rifle_holder.position = HIP_POS.lerp(ADS_POS, eased) + bob + Vector3(0, 0, rifle_kick)
	rifle_holder.rotation = HIP_ROT * (1.0 - eased) + Vector3(recoil_pitch * 0.5, 0, 0)
	rifle_holder.visible = aim_blend < 0.75  # the scope overlay replaces the model when fully aimed
	camera.rotation.x += recoil_pitch * delta * 4.0


func try_fire() -> void:
	if fire_cooldown > 0.0 or ammo <= 0:
		return
	ammo -= 1
	fire_cooldown = bolt_time
	recoil_pitch += 0.09
	rifle_kick += 0.07
	var bullet := BulletScene.instantiate()
	get_tree().current_scene.add_child(bullet)
	var origin: Vector3 = muzzle.global_position if muzzle else camera.global_position
	var far := camera.global_position - camera.global_transform.basis.z * 1000.0
	bullet.launch(origin, (far - origin).normalized())


func aim_at(target: Vector3) -> void:
	## Debug helper: point the camera at a world position.
	var to := target - camera.global_position
	rotation.y = atan2(-to.x, -to.z)
	var flat := Vector2(to.x, to.z).length()
	camera.rotation.x = atan2(to.y, flat)
