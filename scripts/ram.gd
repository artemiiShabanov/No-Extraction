extends Node3D
class_name Ram
## Battering ram: a log carried by a crew of knights straight to the gate. Speed scales with
## living carriers; below `min_crew` the log is dropped for good and the survivors fight on
## foot. Counts as a priority target for the wave (no rout while it is up).

const LogScene := preload("res://assets/models/ramlog.glb")
const CREW_OFFSETS := [Vector3(0.8, 0, 1.0), Vector3(-0.8, 0, 1.0), Vector3(0.8, 0, 0.0), Vector3(-0.8, 0, 0.0), Vector3(0.8, 0, -1.0), Vector3(-0.8, 0, -1.0)]

var crew: Array = []
var dead := false
var fleeing := false
var priority := true
var type_id := "ram"
var speed := 3.4
var damage := 25
var hit_every := 3.0
var min_crew := 3
var at_gate := false
var hit_timer := 1.0
var swing := 0.0
var log: Node3D
var body: AnimatableBody3D
var approach := Vector3(0, 0, -4.2)


func setup(spec: Dictionary, crew_knights: Array) -> void:
	speed = float(spec.get("speed", 3.4))
	damage = int(spec.get("damage", 25))
	hit_every = float(spec.get("hit_every", 3.0))
	min_crew = int(spec.get("min_crew", 3))
	crew = crew_knights
	for i in crew.size():
		crew[i].ram = self
		crew[i].ram_offset = CREW_OFFSETS[i % CREW_OFFSETS.size()]


func _ready() -> void:
	log = LogScene.instantiate()
	log.position.y = 1.0
	add_child(log)
	EnvMaterials.apply_to(log)
	body = AnimatableBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.collision_mask = 0
	body.sync_to_physics = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 3.2)
	shape.shape = box
	shape.position.y = 1.0
	body.add_child(shape)
	add_child(body)
	if Game.gate:
		approach = Game.gate.global_position + Vector3(0, 0, -4.6)
	print("RAM spawned at %s" % global_position.round())


func alive_crew() -> int:
	var n := 0
	for k in crew:
		if is_instance_valid(k) and not k.dead:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if dead:
		return
	var alive := alive_crew()
	if alive < min_crew or (Game.gate and Game.gate.fallen):
		drop()
		return
	if not at_gate:
		var to := approach - global_position
		to.y = 0.0
		if to.length() < 0.6:
			at_gate = true
			Game.gate.reserve_ram(self)
			print("RAM at the gate with %d carriers" % alive)
			return
		var dir := to.normalized()
		var v := speed * float(alive) / float(crew.size())
		global_position += dir * v * delta
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 4.0)  # +Z (iron cap) forward
		global_position.y = Game.terrain.height_at(global_position.x, global_position.z) if Game.terrain else 0.0
	else:
		hit_timer -= delta
		swing = max(swing - delta * 2.5, 0.0)
		log.position.z = -0.8 * sin(swing * PI)
		if hit_timer <= 0.0:
			hit_timer = hit_every * float(crew.size()) / float(alive)
			swing = 1.0
			Game.gate.damage(damage, Game.gate.attack_point(1) + Vector3(0, -0.6, 0))
			print("RAM hit gate, hp=%d" % Game.gate.hp)


func drop() -> void:
	if dead:
		return
	dead = true
	if Game.gate:
		Game.gate.release_slot(self)
	for k in crew:
		if is_instance_valid(k):
			k.ram = null
	crew.clear()
	if not (Game.gate and Game.gate.fallen):
		Game.award("ram")
		Game.priority_kills += 1
	# the log falls to the ground as physics debris
	var rb := RigidBody3D.new()
	rb.collision_layer = Game.LAYER_RAGDOLL
	rb.collision_mask = Game.LAYER_WORLD | Game.LAYER_RAGDOLL
	rb.mass = 40.0
	rb.global_transform = log.global_transform
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 3.2)
	shape.shape = box
	rb.add_child(shape)
	remove_child(log)
	log.position = Vector3.ZERO
	log.rotation = Vector3.ZERO
	rb.add_child(log)
	get_tree().current_scene.add_child(rb)
	rb.apply_central_impulse(Vector3(randf_range(-20, 20), 0, 0))
	print("RAM dropped")
	queue_free()


func flee() -> void:
	## Rout: the crew drops the log and runs with the rest.
	fleeing = true
	var runners := crew.duplicate()
	drop()
	for k in runners:
		if is_instance_valid(k) and not k.dead:
			k.flee()
