extends Node3D
class_name Arrow
## Enemy arrow: slow visible projectile with an arc. Stuns the player, wounds allies,
## sticks into whatever else it hits.

const ArrowScene := preload("res://assets/models/arrow.glb")

var velocity := Vector3.ZERO
var life := 0.0
var stuck := false
var shooter: Node = null


func launch(origin: Vector3, vel: Vector3, from: Node) -> void:
	global_position = origin
	velocity = vel
	shooter = from
	_orient()


func _ready() -> void:
	var model := ArrowScene.instantiate()
	add_child(model)
	EnvMaterials.apply_to(model)


func _orient() -> void:
	if velocity.length_squared() > 0.001:
		look_at(global_position + velocity, Vector3.UP)  # model shaft runs along -Z


func _physics_process(delta: float) -> void:
	if stuck:
		return
	life += delta
	if life > 8.0:
		queue_free()
		return
	var next := global_position + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(global_position, next, Game.LAYER_WORLD | Game.LAYER_HITBOX | Game.LAYER_PLAYER)
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		_on_hit(hit)
		return
	velocity.y -= 9.8 * delta
	global_position = next
	_orient()


func _on_hit(hit: Dictionary) -> void:
	var c: Object = hit.collider
	if c is CharacterBody3D and c.has_method("stun"):
		c.stun(velocity.normalized())
		queue_free()
		return
	if c is Area3D and c.has_meta("knight"):
		var k: Node = c.get_meta("knight")
		if is_instance_valid(k) and k != shooter:
			if k.faction != (shooter.faction if shooter else -1):
				k.take_arrow(c.get_meta("zone"), hit.position, velocity.normalized())
			queue_free()
			return
		# our own side: fly through
		global_position = hit.position + velocity.normalized() * 0.5
		return
	# world: stick
	stuck = true
	global_position = hit.position + velocity.normalized() * 0.25
	load("res://scripts/bullet.gd").spawn_puff(get_tree().current_scene, hit.position, hit.normal, Color(0.6, 0.55, 0.45, 0.8), 6, 0.15)
	get_tree().create_timer(10.0).timeout.connect(queue_free)
