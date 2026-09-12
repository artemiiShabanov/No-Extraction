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
	"next_wave": [KEY_N],
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
var run_seed := 0  # seed of the current run, printed at start so a run can be reproduced
var start_wave := 1  # --wave=N starts the run at wave N (playtesting)
var gate_test := false  # --gate-test: the auto-test forces the gate to fall
var gate_cam := false  # --gate-cam[=fraction]: the auto-test photographs the gate from above (default at 60%)
var gate_cam_at := 0.6
var passive := false  # --passive: the aim bot does not shoot
var kills := 0
var headshots := 0
var blocked := 0
var ally_kills := 0  # allies killed by the player (friendly fire)
var melee_deaths := 0
var stuns := 0
var arrows := 0
var last_kill: Node3D
var terrain: Node3D  # set by Terrain when it enters the tree
var gate: Node3D  # set by Gate when it enters the tree
var run_points := 0
var defeated := false
var points_cfg := {"kill": 10, "headshot": 5, "priority": 50, "wave": 100}


func award(kind: String) -> void:
	run_points += int(points_cfg.get(kind, 0))


var _horn: AudioStreamPlayer


## Placeholder war horn when a priority target appears (synthesised until real audio lands).
const HORN_ENABLED := false  # playtest: annoying; kept for a real sound later


func play_horn() -> void:
	if not HORN_ENABLED:
		return
	if _horn == null:
		_horn = AudioStreamPlayer.new()
		_horn.stream = _make_horn()
		_horn.volume_db = -6.0
		add_child(_horn)
	if not _horn.playing:
		_horn.play()


static func _make_horn() -> AudioStreamWAV:
	var rate := 22050
	var seconds := 1.4
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := minf(t / 0.08, 1.0) * clampf((seconds - t) / 0.5, 0.0, 1.0)
		var f := 174.6 * (1.0 + 0.004 * sin(t * 30.0))
		var v := sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.0 * t) * 0.3 + sin(TAU * f * 3.0 * t) * 0.15
		var s := int(clampf(v * env * 0.8, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav


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
		elif arg.begins_with("--seed="):
			run_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--wave="):
			start_wave = int(arg.get_slice("=", 1))
		elif arg == "--gate-test":
			gate_test = true
			gate_cam = true
		elif arg.begins_with("--gate-cam"):
			gate_cam = true
			if "=" in arg:
				gate_cam_at = float(arg.get_slice("=", 1))
		elif arg == "--passive":
			passive = true
	if not auto_test:
		# fullscreen by default; the auto-test keeps the 1600x900 window so screenshots are stable
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if run_seed == 0:
		run_seed = randi() % 1000000
	print("RUN seed ", run_seed)


func _add_mouse_action(action_name: String, button: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action_name, ev)
