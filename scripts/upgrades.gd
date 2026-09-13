class_name Upgrades
## Roguelike upgrades offered at the portal. Data in data/upgrades.json.

static var pool: Array = []
static var taken: Array[String] = []  # permanent upgrades already active this run


static func load_pool() -> void:
	var data := WaveManager._load_json("res://data/upgrades.json")
	pool = data.get("upgrades", [])
	taken.clear()


## Three distinct offers; permanent upgrades already taken are excluded.
static func roll(count: int, rng: RandomNumberGenerator) -> Array:
	if pool.is_empty():
		load_pool()
	var candidates: Array = []
	for u in pool:
		if u.get("permanent", false) and taken.has(u.id):
			continue
		candidates.append(u)
	var out: Array = []
	while out.size() < count and candidates.size() > 0:
		var i := rng.randi_range(0, candidates.size() - 1)
		out.append(candidates[i])
		candidates.remove_at(i)
	return out


static func apply(u: Dictionary, tree: SceneTree) -> void:
	var scene := tree.current_scene
	var player := scene.get_node_or_null("Player")
	var spawner := scene.get_node_or_null("Spawner")
	match str(u.effect):
		"gate_repair":
			if Game.gate and not Game.gate.fallen:
				Game.gate.repair(int(u.value))
		"reinforce":
			if spawner:
				spawner.reinforce_count(int(u.value))
		"ammo":
			if player:
				player.resupply(int(u.value))
		"armor_piercing":
			Game.armor_piercing = true
		"bolt_time_mul":
			if player:
				player.bolt_time *= float(u.value)
	if u.get("permanent", false):
		taken.append(u.id)
	Game.upgrades_taken.append(u.id)
	print("UPGRADE %s" % u.id)
