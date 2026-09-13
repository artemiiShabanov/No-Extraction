extends CanvasLayer
class_name PortalMenu
## Portal screen: three upgrade cards or leave with the points. Opened at the rift with E.

signal chosen(upgrade: Dictionary)
signal left()

var root: Control
var offers: Array = []
var cards: Array[Button] = []
var title: Label
var preview: Label
var leave_btn: Button


func _ready() -> void:
	layer = 20
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.06, 0.78)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	preview = Label.new()
	preview.add_theme_font_size_override("font_size", 18)
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	box.add_child(preview)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(260, 150)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_on_card.bind(i))
		row.add_child(b)
		cards.append(b)
	leave_btn = Button.new()
	leave_btn.add_theme_font_size_override("font_size", 20)
	leave_btn.pressed.connect(func(): close(); left.emit())
	box.add_child(leave_btn)
	var hint := Label.new()
	hint.text = "Апгрейд запускает следующую волну. Выход сохраняет очки и заканчивает забег."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	box.add_child(hint)


func open(wave_index: int, next_types: Array, points: int, new_offers: Array) -> void:
	offers = new_offers
	title.text = "Волна %d отбита" % (wave_index + 1)
	preview.text = ("Следующая волна: " + ", ".join(next_types)) if next_types.size() > 0 else "Это была последняя волна"
	for i in cards.size():
		if i < offers.size():
			cards[i].text = "%s\n\n%s" % [offers[i].name, offers[i].desc]
			cards[i].visible = true
		else:
			cards[i].visible = false
	leave_btn.text = "Уйти с %d очками" % points
	root.visible = true
	Game.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	root.visible = false
	Game.ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return root.visible


func pick(i: int) -> void:
	_on_card(i)


func _on_card(i: int) -> void:
	if i >= offers.size():
		return
	var u: Dictionary = offers[i]
	close()
	chosen.emit(u)
