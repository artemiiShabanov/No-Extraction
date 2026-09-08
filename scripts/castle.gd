extends Node3D
## Greybox castle: a wall along X with a gatehouse and two corner towers.
## The enemy approaches from -Z. The walkway top is at WALK_Y.

const WALL_HALF := 40.0
const WALL_H := 10.0
const WALL_T := 6.0
const WALK_Y := WALL_H

var stone: StandardMaterial3D
var wood: StandardMaterial3D
var ground_mat: StandardMaterial3D


func _ready() -> void:
	stone = _stone_material(Color(0.55, 0.52, 0.48))
	wood = _stone_material(Color(0.36, 0.24, 0.12), 2.0)
	ground_mat = _stone_material(Color(0.36, 0.40, 0.22), 0.06)

	# ground
	var ground := _block(Vector3(0, -0.5, 0), Vector3(1200, 1, 1200), ground_mat)
	ground.name = "Ground"

	# main wall, split around the gate
	var gate_half := 3.5
	var seg := (WALL_HALF - gate_half - 5.0)
	_block(Vector3(-(gate_half + 5.0 + seg / 2), WALL_H / 2, 0), Vector3(seg, WALL_H, WALL_T), stone)
	_block(Vector3((gate_half + 5.0 + seg / 2), WALL_H / 2, 0), Vector3(seg, WALL_H, WALL_T), stone)
	# arch above the gate
	_block(Vector3(0, WALL_H - 2.0, 0), Vector3(gate_half * 2, 4.0, WALL_T), stone)
	# gate doors
	_block(Vector3(0, 3.0, 0.5), Vector3(gate_half * 2, 6.0, 0.6), wood)
	# gatehouse towers
	for sx in [-1.0, 1.0]:
		_tower(Vector3(sx * (gate_half + 2.5), 0, 0), 5.0, WALL_H + 4.0)
	# corner towers
	for sx in [-1.0, 1.0]:
		_tower(Vector3(sx * WALL_HALF, 0, 0), 10.0, WALL_H + 5.0)
	# merlons along the outer edge of the walkway
	var x := -WALL_HALF + 6.0
	while x < WALL_HALF - 6.0:
		if abs(x) > gate_half + 5.0:
			_block(Vector3(x, WALL_H + 0.6, -WALL_T / 2 + 0.4), Vector3(1.0, 1.2, 0.8), stone)
		x += 2.0
	# low parapet on the inner side
	_block(Vector3(-(gate_half + 5.0 + seg / 2), WALL_H + 0.4, WALL_T / 2 - 0.3), Vector3(seg, 0.8, 0.6), stone)
	_block(Vector3((gate_half + 5.0 + seg / 2), WALL_H + 0.4, WALL_T / 2 - 0.3), Vector3(seg, 0.8, 0.6), stone)

	# a few boulders in the field for scale
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 30:
		var p := Vector3(rng.randf_range(-120, 120), 0, rng.randf_range(-260, -20))
		var s := rng.randf_range(0.8, 3.0)
		var rock := _block(p + Vector3(0, s * 0.3, 0), Vector3(s, s * 0.7, s * 0.8), stone)
		rock.rotation.y = rng.randf_range(0, TAU)


func _tower(base: Vector3, size: float, height: float) -> void:
	_block(base + Vector3(0, height / 2, 0), Vector3(size, height, size), stone)
	var n := int(size / 2.0)
	for i in n:
		var t := -size / 2 + 1.0 + i * 2.0
		_block(base + Vector3(t, height + 0.75, -size / 2 + 0.4), Vector3(1.0, 1.5, 0.8), stone)
		_block(base + Vector3(t, height + 0.75, size / 2 - 0.4), Vector3(1.0, 1.5, 0.8), stone)
		_block(base + Vector3(-size / 2 + 0.4, height + 0.75, t), Vector3(0.8, 1.5, 1.0), stone)
		_block(base + Vector3(size / 2 - 0.4, height + 0.75, t), Vector3(0.8, 1.5, 1.0), stone)


func _block(center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	return body


func _stone_material(base: Color, scale: float = 0.5) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.72, 0.72))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	tex.color_ramp = ramp
	mat.albedo_color = base
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * scale
	mat.roughness = 0.95
	return mat
