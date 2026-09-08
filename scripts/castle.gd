extends Node3D
## Castle assembled from the Blender modules in assets/models/castle.
## The wall runs along X, the enemy approaches from -Z, the walkway top is at WALK_Y.

const WALL_HALF := 45.0
const WALK_Y := 10.0
const SEGMENT_LEN := 10.0
const GATE_HALF := 4.5

const WallSegment := preload("res://assets/models/castle/wall_segment.glb")
const TowerRound := preload("res://assets/models/castle/tower_round.glb")
const Gatehouse := preload("res://assets/models/castle/gatehouse.glb")
const GateDoors := preload("res://assets/models/castle/gate_doors.glb")


func _ready() -> void:
	# wall segments either side of the gate
	var x := GATE_HALF + SEGMENT_LEN / 2
	while x < WALL_HALF:
		_place(WallSegment, Vector3(x, 0, 0))
		_place(WallSegment, Vector3(-x, 0, 0))
		x += SEGMENT_LEN
	_place(Gatehouse, Vector3(0, 0, 0))
	_place(GateDoors, Vector3(0, 0, 0.6))
	# gate flank towers (smaller) and corner towers
	for sx in [-1.0, 1.0]:
		_place(TowerRound, Vector3(sx * 6.8, 0, 0), 0.72)
		_place(TowerRound, Vector3(sx * WALL_HALF, 0, 0))
	# a few boulders in the field for scale
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 30:
		var p := Vector3(rng.randf_range(-140, 140), 0, rng.randf_range(-260, -25))
		p.y = Game.terrain.height_at(p.x, p.z) if Game.terrain else 0.0
		var s := rng.randf_range(0.8, 3.0)
		_rock(p, s, rng.randf_range(0, TAU))


func _place(scene: PackedScene, pos: Vector3, scale_xz: float = 1.0) -> Node3D:
	var inst: Node3D = scene.instantiate()
	inst.position = pos
	inst.scale = Vector3(scale_xz, 1.0, scale_xz)
	add_child(inst)
	EnvMaterials.apply_to(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_trimesh_shape()
		body.add_child(shape)
		mi.add_child(body)
	return inst


func _rock(center: Vector3, size: float, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.position = center + Vector3(0, size * 0.25, 0)
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, size * 0.7, size * 0.8)
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	mi.mesh = mesh
	mi.material_override = EnvMaterials.stone("StoneTower")
	body.add_child(mi)
	add_child(body)
