extends Node
class_name WaveManager
## Waves = hand-authored beats (priority targets, lanes, timing) + a seeded generator that
## fills the budget with rank-and-file. A wave ends when every enemy is dead, or when the
## priority targets are dead and few enough enemies remain that the rest rout and flee.
## The next wave starts only when the player asks for it (portal choice later).

signal wave_started(index: int, info: Dictionary)
signal wave_cleared(index: int, stats: Dictionary)
signal run_won()

enum State { IDLE, ACTIVE, ROUT, CLEARED, WON, LOST }

const WAVES_PATH := "res://data/waves.json"
const TYPES_PATH := "res://data/enemy_types.json"

var spawner: Node3D
var data := {}
var types := {}
var state := State.IDLE
var wave_index := -1  # 0-based, -1 before the first wave
var wave_time := 0.0
var wave_total := 0
var pending: Array = []  # [{t, type, lane}] sorted by t
var spawned: Array = []
var priority_alive := 0
var rng := RandomNumberGenerator.new()
var budget_scale := 1.0  # auto-test uses smaller waves
var castle_cfg := {}
var _groups := {}  # escort group id -> shared spawn point
var lane_override := {}   # auto-test: bring spawns closer


func _ready() -> void:
	data = _load_json(WAVES_PATH)
	types = _load_json(TYPES_PATH)
	castle_cfg = _load_json("res://data/castle.json")
	Game.points_cfg = castle_cfg.get("points", Game.points_cfg)
	wave_index = clampi(Game.start_wave, 1, wave_count()) - 2  # start_next_wave() adds one


static func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func wave_count() -> int:
	return data.get("waves", []).size()


func current_wave() -> Dictionary:
	return data["waves"][wave_index] if wave_index >= 0 and wave_index < wave_count() else {}


func next_wave_info() -> Dictionary:
	## Preview for the portal: composition of the wave after the current one.
	var i := wave_index + 1
	if i >= wave_count():
		return {}
	return _describe(_compose(i, RandomNumberGenerator.new()))


func can_start_next() -> bool:
	return state in [State.IDLE, State.CLEARED] and wave_index + 1 < wave_count()


func start_next_wave() -> void:
	if not can_start_next():
		return
	wave_index += 1
	rng.seed = Game.run_seed + wave_index * 7919
	pending = _compose(wave_index, rng)
	pending.sort_custom(func(a, b): return a.t < b.t)
	spawned.clear()
	_groups.clear()
	wave_total = pending.size()
	priority_alive = 0
	for p in pending:
		if types[p.type].get("priority", false):
			priority_alive += 1
	if priority_alive > 0:
		Game.play_horn()
	wave_time = 0.0
	state = State.ACTIVE
	var info := _describe(pending)
	info["name"] = current_wave().get("name", "")
	print("WAVE %d/%d start: %s" % [wave_index + 1, wave_count(), info])
	wave_started.emit(wave_index, info)


func _compose(i: int, r: RandomNumberGenerator) -> Array:
	## Beats verbatim + generated filler spread over the wave duration.
	var w: Dictionary = data["waves"][i]
	var out: Array = []
	var group := 0
	for beat in w.get("beats", []):
		for n in int(beat.get("count", 1)):
			var t0 := float(beat.get("at", 0)) + n * 0.4
			var entry := {"t": t0, "type": beat["type"], "lane": beat["lane"]}
			var escort: Array = types[beat["type"]].get("escort", [])
			if escort.size() == 2:
				# e.g. a captain arrives surrounded by rank-and-file from the same lane
				group += 1
				entry["group"] = group
				for e in r.randi_range(int(escort[0]), int(escort[1])):
					out.append({"t": t0 + r.randf_range(-0.3, 0.6), "type": "swordsman", "lane": beat["lane"], "group": group, "escort": true})
			out.append(entry)
	var budget: float = float(w.get("budget", 0)) * budget_scale
	var weights: Dictionary = w.get("weights", {"swordsman": 1.0})
	var lanes: Dictionary = w.get("lanes", {"center": 1.0})
	var filler: Array = []
	var guard := 0
	while budget > 0.0 and guard < 500:
		guard += 1
		var t := _weighted_pick(weights, r)
		var cost: float = float(types[t].get("cost", 1.0))
		if cost > budget and filler.size() > 0:
			break
		budget -= cost
		filler.append({"type": t, "lane": _weighted_pick(lanes, r)})
	var duration: float = float(w.get("duration", 30))
	for n in filler.size():
		var f: Dictionary = filler[n]
		# batches: knights of the same batch arrive within a couple of seconds
		f["t"] = 1.0 + duration * float(n) / max(filler.size(), 1) + r.randf_range(0.0, 1.5)
		out.append(f)
	return out


static func _weighted_pick(weights: Dictionary, r: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := r.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return weights.keys()[0]


func _describe(list: Array) -> Dictionary:
	var by_type := {}
	var by_lane := {}
	for p in list:
		by_type[p.type] = by_type.get(p.type, 0) + 1
		by_lane[p.lane] = by_lane.get(p.lane, 0) + 1
	return {"total": list.size(), "types": by_type, "lanes": by_lane}


func lose() -> void:
	## The gate fell: the run is over, points burn.
	if state == State.LOST:
		return
	state = State.LOST
	Game.defeated = true
	Game.run_points = 0
	print("RUN LOST at wave %d" % (wave_index + 1))


func _process(delta: float) -> void:
	if state != State.ACTIVE and state != State.ROUT:
		return
	wave_time += delta
	while pending.size() > 0 and pending[0].t <= wave_time:
		var p: Dictionary = pending.pop_front()
		var k := _spawn(p)
		if k:
			spawned.append(k)
	# living enemies of this wave
	var alive := 0
	var fleeing := 0
	priority_alive = 0
	for k in spawned:
		if not is_instance_valid(k) or k.dead:
			continue
		if k is Ram:
			priority_alive += 1
			continue
		if k.fleeing:
			fleeing += 1
			continue
		alive += 1
		if k.priority:
			priority_alive += 1
	# beats/filler still to come count as alive for the rout rule
	var remaining := alive + pending.size()
	# fleeing knights do not hold the wave: once nobody is fighting, the wave is cleared
	if state == State.ACTIVE:
		var ratio: float = float(current_wave().get("rout_ratio", 0.2))
		if remaining == 0:
			_cleared()
		elif pending.is_empty() and priority_alive == 0 and remaining <= ceil(wave_total * ratio):
			_rout()
			if alive == 0:
				_cleared()
	elif state == State.ROUT:
		if alive == 0:
			_cleared()


func _spawn(p: Dictionary) -> Node:
	var lane_id: String = p.lane
	var lane: Dictionary = data["lanes"].get(lane_id, data["lanes"]["center"]).duplicate()
	if lane_override.has(lane_id):
		lane.merge(lane_override[lane_id], true)
	var pos := Vector3(rng.randf_range(lane.spawn_x[0], lane.spawn_x[1]), 0.0, rng.randf_range(lane.spawn_z[0], lane.spawn_z[1]))
	var target_x := rng.randf_range(lane.target_x[0], lane.target_x[1])
	if p.has("group"):
		# escort groups share one spawn point and one destination, spread a few metres around it
		if not _groups.has(p.group):
			_groups[p.group] = {"pos": pos, "target_x": target_x}
		pos = _groups[p.group].pos + Vector3(rng.randf_range(-4.0, 4.0), 0.0, rng.randf_range(-4.0, 4.0)) * (1.0 if p.get("escort", false) else 0.0)
		target_x = _groups[p.group].target_x + (rng.randf_range(-3.0, 3.0) if p.get("escort", false) else 0.0)
	var spec: Dictionary = types[p.type].duplicate()
	spec["id"] = p.type
	spec["flee_to"] = pos
	if p.type == "ram":
		var crew_spec: Dictionary = types["ram_crew"].duplicate()
		crew_spec["id"] = "ram_crew"
		crew_spec["flee_to"] = pos
		var ram: Node = spawner.spawn_ram(pos, spec, crew_spec, rng)
		for k in ram.crew:
			spawned.append(k)
		Game.play_horn()
		return ram
	if spec.get("priority", false):
		Game.play_horn()
	return spawner.spawn_enemy(pos, spec, target_x, rng)


func _rout() -> void:
	state = State.ROUT
	var n := 0
	for k in spawned:
		if is_instance_valid(k) and not k.dead and not k.fleeing:
			k.flee()
			n += 1
	print("WAVE %d rout: %d flee at t=%.1f" % [wave_index + 1, n, wave_time])


func _cleared() -> void:
	state = State.CLEARED
	var stats := {"time": wave_time, "total": wave_total, "kills": Game.kills, "headshots": Game.headshots}
	Game.award("wave")
	var back: int = spawner.reinforce(float(castle_cfg.get("reinforce_ratio", 0.5)))
	print("WAVE %d cleared at t=%.1f, %d allies reinforced, points %d" % [wave_index + 1, wave_time, back, Game.run_points])
	wave_cleared.emit(wave_index, stats)
	if wave_index + 1 >= wave_count():
		state = State.WON
		print("RUN WON")
		run_won.emit()


func status_text() -> String:
	match state:
		State.IDLE:
			return "Нажмите [N], чтобы начать волну 1 из %d" % wave_count()
		State.ACTIVE, State.ROUT:
			var alive := 0
			for k in spawned:
				if is_instance_valid(k) and not k.dead and not k.fleeing:
					alive += 1
			return "ВОЛНА %d/%d «%s»  врагов %d + на подходе %d  приоритетных %d%s" % [
				wave_index + 1, wave_count(), current_wave().get("name", ""), alive, pending.size(), priority_alive,
				"  БЕГУТ!" if state == State.ROUT else ""]
		State.CLEARED:
			return "Волна %d отбита за %.0f с. [N] следующая волна" % [wave_index + 1, wave_time]
		State.WON:
			return "ПОБЕДА: все %d волн отбиты, очки %d" % [wave_count(), Game.run_points]
		State.LOST:
			return "ВОРОТА ПАЛИ. Очки забега сгорели. Перезапуск: дебаг-меню или F1"
	return ""
