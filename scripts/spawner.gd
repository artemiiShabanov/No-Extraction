extends Node3D
## Spawns the enemy crowd charging the wall and the allied line holding the field,
## then pairs opposing knights into 1-on-1 duels.

const KnightScene := preload("res://scenes/knight.tscn")

@export var count := 90
@export var ally_count := 30
@export var spawn_z_min := -230.0
@export var spawn_z_max := -140.0
@export var spawn_x_half := 60.0
@export var wall_target_z := -5.0
@export var wall_x_half := 36.0
@export var ally_z_min := -30.0
@export var ally_z_max := -10.0
@export var batch := 6
@export var interval := 0.35
@export var pairing_range := 45.0

const ENEMY_RED := Color(0.75, 0.12, 0.10)
const ENEMY_BLACK := Color(0.2, 0.2, 0.22)
const ALLY_BLUE := Color(0.15, 0.30, 0.75)

var spawned := 0
var timer := 0.0
var pair_timer := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 42
	for i in ally_count:
		_spawn_ally()


func _process(delta: float) -> void:
	pair_timer -= delta
	if pair_timer <= 0.0:
		pair_timer = 0.5
		_pair_duels()
	if spawned >= count:
		return
	timer -= delta
	if timer > 0.0:
		return
	timer = interval
	for i in batch:
		if spawned >= count:
			break
		_spawn_enemy()


func _spawn_enemy() -> void:
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
	k.faction = Game.Faction.ENEMY
	k.tunic_color = ENEMY_RED if rng.randf() > 0.15 else ENEMY_BLACK
	add_child(k)
	spawned += 1


func _spawn_ally() -> void:
	var k := KnightScene.instantiate()
	var x := rng.randf_range(-wall_x_half, wall_x_half)
	var z := rng.randf_range(ally_z_min, ally_z_max)
	k.position = Vector3(x, 0.0, z)
	k.target = k.position
	k.hold = true
	k.speed = rng.randf_range(5.0, 7.0)
	k.faction = Game.Faction.ALLY
	k.tunic_color = ALLY_BLUE
	k.rotation.y = PI  # face the field (-Z)
	add_child(k)


func _pair_duels() -> void:
	## Each free ally picks the nearest free enemy within range; both lock onto each other.
	var free_allies: Array = []
	var free_enemies: Array = []
	for k in get_children():
		if k.dead or k.melee_target != null:
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


func alive_count(faction: int = Game.Faction.ENEMY) -> int:
	var n := 0
	for k in get_children():
		if not k.dead and k.faction == faction:
			n += 1
	return n
