extends Node3D
class_name Rift
## The portal: a tear in space on the walkway. Dormant during a wave, opens when the wave is
## cleared. Faces the player, lights the stones around it.

signal entered(player: Node)
signal exited(player: Node)

var open := 0.0  # 0 = collapsed to a point, 1 = fully open
var target_open := 0.0
var mesh: MeshInstance3D
var mat: ShaderMaterial
var light: OmniLight3D
var area: Area3D
var player_inside := false


func _ready() -> void:
	mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 3.2)
	mesh.mesh = quad
	mesh.position.y = 1.9
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/rift.gdshader")
	mesh.material_override = mat
	add_child(mesh)
	light = OmniLight3D.new()
	light.light_color = Color(0.55, 0.35, 1.0)
	light.omni_range = 9.0
	light.position.y = 1.8
	add_child(light)
	area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = Game.LAYER_PLAYER
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 2.6
	shape.shape = sph
	shape.position.y = 1.0
	area.add_child(shape)
	area.body_entered.connect(func(b): if b.has_method("stun"): player_inside = true; entered.emit(b))
	area.body_exited.connect(func(b): if b.has_method("stun"): player_inside = false; exited.emit(b))
	add_child(area)
	Game.rift = self


func set_active(active: bool) -> void:
	target_open = 1.0 if active else 0.0


func is_active() -> bool:
	return target_open > 0.5


func _process(delta: float) -> void:
	open = move_toward(open, target_open, delta * (1.2 if target_open > open else 1.6))
	mat.set_shader_parameter("open", open)
	light.light_energy = 0.15 + 5.0 * open + sin(Time.get_ticks_msec() * 0.004) * 0.6 * open
	var cam := get_viewport().get_camera_3d()
	if cam:
		var to := cam.global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			rotation.y = atan2(to.x, to.z)  # quad faces +Z
