extends Node3D
## Spawns a crowd of knights in the field that charge the wall.

const KnightScene := preload("res://scenes/knight.tscn")

@export var count := 90
@export var spawn_z_min := -230.0
@export var spawn_z_max := -140.0
@export var spawn_x_half := 60.0
@export var wall_target_z := -5.0
@export var wall_x_half := 36.0
@export var batch := 6
@export var interval := 0.35

var spawned := 0
var timer := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 42


func _process(delta: float) -> void:
	if spawned >= count:
		return
	timer -= delta
	if timer > 0.0:
		return
	timer = interval
	for i in batch:
		if spawned >= count:
			break
		_spawn_one()


func _spawn_one() -> void:
	var k := KnightScene.instantiate()
	var x := rng.randf_range(-spawn_x_half, spawn_x_half)
	var z := rng.randf_range(spawn_z_min, spawn_z_max)
	k.position = Vector3(x, 0.0, z)
	# a third of them go for the gate, the rest spread along the wall
	var tx: float = clampf(x * 0.6, -wall_x_half, wall_x_half)
	if rng.randf() < 0.33:
		tx = rng.randf_range(-3.0, 3.0)
	k.target = Vector3(tx, 0.0, wall_target_z - rng.randf_range(0.0, 2.5))
	k.speed = rng.randf_range(5.0, 7.5)
	k.tunic_color = Color(0.75, 0.12, 0.10) if rng.randf() > 0.15 else Color(0.2, 0.2, 0.22)
	add_child(k)
	spawned += 1


func alive_count() -> int:
	var n := 0
	for k in get_children():
		if not k.dead:
			n += 1
	return n
