extends Node3D
## Holds every knight. Allies are placed at start; enemies are spawned by the WaveManager
## (or by the debug menu) through spawn_enemy().

const KnightScene := preload("res://scenes/knight.tscn")

@export var ally_count := 30
@export var wall_target_z := -5.0
@export var wall_x_half := 36.0
@export var ally_z_min := -30.0
@export var ally_z_max := -10.0
@export var pairing_range := 45.0

const ALLY_BLUE := Color(0.15, 0.30, 0.75)
const DEFAULT_ENEMY := {"id": "swordsman", "hp": 2, "melee_hp": 3, "speed": [5.0, 7.0], "tunic": "#bf1f1a", "shield": true, "scale": 1.0, "priority": false}

var pair_timer := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = Game.run_seed
	for i in ally_count:
		spawn_ally()


func _process(delta: float) -> void:
	# reinforcements file out of the gate one by one
	if not reinforce_queue.is_empty():
		reinforce_timer -= delta
		if reinforce_timer <= 0.0:
			reinforce_timer = 0.4
			spawn_ally(reinforce_queue.pop_front(), true)
	pair_timer -= delta
	if pair_timer <= 0.0:
		pair_timer = 0.5
		_pair_duels()


## Spawn one enemy from a type spec (see data/enemy_types.json). `at` may be null for a
## random field position (debug menu).
func spawn_enemy(at: Variant = null, spec: Dictionary = DEFAULT_ENEMY, target_x: float = NAN, r: RandomNumberGenerator = null) -> Node:
	if r == null:
		r = rng
	var k := KnightScene.instantiate()
	var x := r.randf_range(-40.0, 40.0)
	var z := r.randf_range(-110.0, -60.0)
	if at != null:
		x = at.x
		z = at.z
	k.position = Vector3(x, _ground(x, z) + 0.2, z)
	if is_nan(target_x):
		target_x = clampf(x * 0.6, -wall_x_half, wall_x_half)
		if r.randf() < 0.33:
			target_x = r.randf_range(-3.0, 3.0)
	k.target = Vector3(target_x, 0.0, wall_target_z - r.randf_range(0.0, 2.5))
	k.faction = Game.Faction.ENEMY
	k.apply_spec(spec, r)
	add_child(k)
	return k


const GATE_EXIT := Vector3(0.0, 0.0, -1.5)  # inside the arch, just outside the doors

var reinforce_queue: Array[Vector3] = []
var reinforce_timer := 0.0


## Spawn an ally. `at` = post to hold; `from_gate` = appear in the gate arch and run to the post.
func spawn_ally(at: Variant = null, from_gate: bool = false) -> Node:
	var k := KnightScene.instantiate()
	var x := rng.randf_range(-wall_x_half, wall_x_half)
	var z := rng.randf_range(ally_z_min, ally_z_max)
	if at != null:
		x = at.x
		z = at.z
	var post := Vector3(x, 0.0, z)
	var start := GATE_EXIT + Vector3(rng.randf_range(-1.2, 1.2), 0, 0) if from_gate else post
	k.position = Vector3(start.x, _ground(start.x, start.z) + 0.2, start.z)
	k.target = post
	k.hold = not from_gate  # runners hold once they reach the post
	k.speed = rng.randf_range(5.0, 7.0)
	k.faction = Game.Faction.ALLY
	k.tunic_color = ALLY_BLUE
	k.rotation.y = 0.0  # face the field (-Z)
	add_child(k)
	return k


## Between waves: bring back part of the fallen allies to the line.
func reinforce(ratio: float) -> int:
	var missing := ally_count - alive_count(Game.Faction.ALLY)
	var n := int(ceil(missing * ratio))
	for i in n:
		reinforce_queue.append(Vector3(rng.randf_range(-wall_x_half, wall_x_half), 0.0, rng.randf_range(ally_z_min, ally_z_max)))
	return n


func _pair_duels() -> void:
	## Each free ally picks the nearest free enemy within range; both lock onto each other.
	var free_allies: Array = []
	var free_enemies: Array = []
	for k in get_children():
		if not (k is CharacterBody3D) or k.dead or k.melee_target != null or k.fleeing:
			continue
		if k.faction == Game.Faction.ALLY:
			free_allies.append(k)
		else:
			free_enemies.append(k)
	for ally in free_allies:
		var best = null
		var bd := pairing_range * pairing_range
		for enemy in free_enemies:
			var d: float = ally.global_position.distance_squared_to(enemy.global_position)
			if d < bd:
				bd = d
				best = enemy
		if best:
			ally.melee_target = best
			best.melee_target = ally
			free_enemies.erase(best)


func _ground(x: float, z: float) -> float:
	return Game.terrain.height_at(x, z) if Game.terrain else 0.0


func alive_count(faction: int = Game.Faction.ENEMY) -> int:
	var n := 0
	for k in get_children():
		if k is CharacterBody3D and not k.dead and not k.fleeing and k.faction == faction:
			n += 1
	return n
