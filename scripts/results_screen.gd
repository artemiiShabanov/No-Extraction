extends CanvasLayer
class_name ResultsScreen
## One results screen for the three outcomes: castle fell, left through the rift, siege repelled.

const KIND_LABELS := {
	"kill": "Убийства", "headshot": "Хедшоты", "priority": "Приоритетные цели", "archer": "Лучники",
	"ram": "Тараны", "wave": "Отбитые волны", "victory": "Бонус за победу",
}

signal restart_requested()

var root: Control


func _ready() -> void:
	layer = 30
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)


func show_outcome(outcome: String, waves_cleared: int, burned: int) -> void:
	for c in root.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.82)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var titles := {"defeat": "Замок пал", "extract": "Вы ушли через разлом", "victory": "Осада отбита"}
	var colors := {"defeat": Color(0.95, 0.35, 0.3), "extract": Color(0.75, 0.6, 1.0), "victory": Color(1.0, 0.85, 0.35)}
	var title := Label.new()
	title.text = titles.get(outcome, "Забег окончен")
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", colors.get(outcome, Color.WHITE))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var minutes := int(Game.run_seconds()) / 60
	var seconds := int(Game.run_seconds()) % 60
	var accuracy := (100.0 * Game.hits / Game.shots) if Game.shots > 0 else 0.0
	var stats := Label.new()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 19)
	stats.text = "Волн отбито: %d из %d    Время: %d:%02d\nУбийств: %d   хедшотов: %d   приоритетных: %d   блоков щитом: %d\nТочность: %d%% (%d из %d выстрелов)" % [
		waves_cleared, Game.wave_total, minutes, seconds, Game.kills, Game.headshots, Game.priority_kills, Game.blocked, int(accuracy), Game.hits, Game.shots]
	box.add_child(stats)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 2)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	box.add_child(gc)
	for kind in KIND_LABELS:
		var v: int = Game.breakdown.get(kind, 0)
		if v == 0:
			continue
		_row(grid, KIND_LABELS[kind], "+%d" % v)
	var total := Game.run_points if outcome != "defeat" else 0
	_row(grid, "Итого за забег", str(total), true)
	if outcome == "defeat":
		_row(grid, "Сгорело", "-%d" % burned, true, Color(0.95, 0.4, 0.3))
	_row(grid, "В казне", str(Game.meta_points), true, Color(0.9, 0.8, 0.4))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	var again := Button.new()
	again.text = "Новый забег  [E]"
	again.add_theme_font_size_override("font_size", 20)
	again.pressed.connect(func(): restart_requested.emit())
	buttons.add_child(again)
	var menu := Button.new()
	menu.text = "В меню"
	menu.disabled = true
	menu.tooltip_text = "Главное меню появится позже"
	menu.add_theme_font_size_override("font_size", 20)
	buttons.add_child(menu)

	root.visible = true
	Game.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _row(grid: GridContainer, name: String, value: String, bold := false, color := Color.WHITE) -> void:
	var a := Label.new()
	a.text = name
	a.add_theme_font_size_override("font_size", 20 if bold else 17)
	a.add_theme_color_override("font_color", color if bold else Color(0.85, 0.85, 0.9))
	var b := Label.new()
	b.text = value
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_theme_font_size_override("font_size", 20 if bold else 17)
	b.add_theme_color_override("font_color", color)
	grid.add_child(a)
	grid.add_child(b)


func is_open() -> bool:
	return root.visible
