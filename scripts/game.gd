extends Node
## Autoload: input map setup and command-line options for automated runs.

const KEY_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"reload": [KEY_R],
	"toggle_mouse": [KEY_ESCAPE],
}

# Collision layers
const LAYER_WORLD := 1
const LAYER_KNIGHT := 2
const LAYER_RAGDOLL := 4
const LAYER_PLAYER := 8
const LAYER_HITBOX := 16  # per-bone Area3D hit zones on living knights

enum Faction { ENEMY, ALLY }

var screenshot_path := ""
var auto_test := false
var test_frames := 500
var kills := 0
var headshots := 0
var blocked := 0
var ally_kills := 0  # allies killed by the player (friendly fire)
var melee_deaths := 0
var last_kill: Node3D
var terrain: Node3D  # set by Terrain when it enters the tree


func _ready() -> void:
	for action_name in KEY_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for keycode in KEY_ACTIONS[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action_name, ev)
	_add_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_add_mouse_action("aim", MOUSE_BUTTON_RIGHT)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			screenshot_path = arg.get_slice("=", 1)
		elif arg == "--auto-test":
			auto_test = true
		elif arg.begins_with("--frames="):
			test_frames = int(arg.get_slice("=", 1))


func _add_mouse_action(action_name: String, button: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action_name, ev)
