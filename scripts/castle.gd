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
const GateStairsL := preload("res://assets/models/castle/gate_stairs_l.glb")
const GateStairsR := preload("res://assets/models/castle/gate_stairs_r.glb")
const TowerStairsL := preload("res://assets/models/castle/tower_stairs_l.glb")
const TowerStairsR := preload("res://assets/models/castle/tower_stairs_r.glb")
const STAIR_Z := 1.65  # inner strip of the walkway
const ROOF_Y := 14.0
const TOWER_TOP_Y := 14.2


func _ready() -> void:
	# wall segments either side of the gate
	var x := GATE_HALF + SEGMENT_LEN / 2
	while x < WALL_HALF:
		_place(WallSegment, Vector3(x, 0, 0))
		_place(WallSegment, Vector3(-x, 0, 0))
		x += SEGMENT_LEN
	_place(Gatehouse, Vector3(0, 0, 0))
	var gate := Gate.new()
	gate.name = "Gate"
	gate.position = Vector3(0, 0, 0.6)
	add_child(gate)
	# corner towers with stairs from the walkway; stairs to the gatehouse roof
	for sx in [-1.0, 1.0]:
		_place(TowerRound, Vector3(sx * WALL_HALF, 0, 0))
	_place(GateStairsL, Vector3(12.5, WALK_Y, STAIR_Z))
	_place(GateStairsR, Vector3(-12.5, WALK_Y, STAIR_Z))
	_place(TowerStairsR, Vector3(34.0, WALK_Y, STAIR_Z))
	_place(TowerStairsL, Vector3(-34.0, WALK_Y, STAIR_Z))
	_build_boundaries()
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
		if mi.name.begins_with("Steps") and not mi.name.begins_with("StepsWall"):
			continue  # visual sawtooth; the hidden Ramp mesh carries the collision
		if mi.name.begins_with("Ramp"):
			mi.visible = false
		var body := StaticBody3D.new()
		body.collision_layer = Game.LAYER_WORLD
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_trimesh_shape()
		body.add_child(shape)
		mi.add_child(body)
	return inst


## Invisible walls: nobody leaves the wall walk, the gatehouse roof or the tower tops.
func _build_boundaries() -> void:
	var h := 7.0
	var y := WALK_Y + h / 2
	# outer parapet and inner edge along both wall halves, stopping at the tower bodies
	for sx in [-1.0, 1.0]:
		var x0 := 6.5
		var x1 := WALL_HALF - 4.7
		var cx: float = sx * (x0 + x1) / 2
		_wall(Vector3(cx, y, -2.55), Vector3(x1 - x0, h, 0.2))
		_wall(Vector3(cx, y, 2.65), Vector3(x1 - x0, h, 0.2))
	# gatehouse roof: front and back edges only; the sides drop onto the walkway (a shortcut)
	var ry := ROOF_Y + h / 2
	_wall(Vector3(0, ry, -3.65), Vector3(13.4, h, 0.2))
	_wall(Vector3(0, ry, 3.65), Vector3(13.4, h, 0.2))
	# corner tower tops: a ring of panels with a wide gap where the stairs arrive, plus end caps
	for sx in [-1.0, 1.0]:
		var c := Vector3(sx * WALL_HALF, TOWER_TOP_Y + h / 2, 0)
		var arrival := PI if sx > 0 else 0.0
		for i in 24:
			var a := TAU * i / 24
			if abs(angle_difference(a, arrival)) < 0.5:
				continue
			var seg := _wall(c + Vector3(cos(a), 0, sin(a)) * 4.85, Vector3(1.35, h, 0.2))
			seg.rotation.y = -a + PI / 2
		_wall(Vector3(sx * (WALL_HALF + 5.3), y, 0), Vector3(0.2, h, 12.0))


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_BOUNDS  # bullets, arrows and knights pass through
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body


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
	mi.material_override = EnvMaterials.stone("StoneTower", true)
	body.add_child(mi)
	add_child(body)
