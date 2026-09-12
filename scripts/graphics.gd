class_name Graphics
## Graphics presets. Applied at startup and switchable at runtime; the choice is saved in
## user://settings.cfg. Numbers from the first Mac playtest: SDFGI costs ~10 fps at fullscreen,
## FSR2 upscaling is itself several ms on integrated GPUs, so the default is FSR1 without SDFGI.

const PRESETS := {
	"low": {
		"target_pixels": 1.1e6, "upscaler": Viewport.SCALING_3D_MODE_FSR, "sdfgi": false, "ssao": false,
		"msaa": Viewport.MSAA_DISABLED, "shadow_size": 2048, "shadow_splits": 2, "soft_shadows": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"glow": false, "shadow_distance": 200.0,
	},
	"medium": {
		"target_pixels": 1.7e6, "upscaler": Viewport.SCALING_3D_MODE_FSR, "sdfgi": false, "ssao": true,
		"msaa": Viewport.MSAA_2X, "shadow_size": 4096, "shadow_splits": 3, "soft_shadows": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		"glow": true, "shadow_distance": 320.0,
	},
	"high": {
		"target_pixels": 4.0e6, "upscaler": Viewport.SCALING_3D_MODE_FSR2, "sdfgi": true, "ssao": true,
		"msaa": Viewport.MSAA_2X, "shadow_size": 4096, "shadow_splits": 4, "soft_shadows": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"glow": true, "shadow_distance": 320.0,
	},
}
const SETTINGS_PATH := "user://settings.cfg"

static var current := "medium"
static var env: Environment
static var sun: DirectionalLight3D


static func load_choice() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		current = str(cfg.get_value("graphics", "preset", current))
	if not PRESETS.has(current):
		current = "medium"
	return current


static func save_choice() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "preset", current)
	cfg.save(SETTINGS_PATH)


## Apply a preset to the scene's environment, sun and the root viewport.
static func apply(preset: String, tree: SceneTree) -> void:
	if not PRESETS.has(preset):
		return
	current = preset
	var p: Dictionary = PRESETS[preset]
	var vp := tree.root
	vp.msaa_3d = p.msaa
	RenderingServer.directional_shadow_atlas_set_size(int(p.shadow_size), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p.soft_shadows)
	if env:
		env.sdfgi_enabled = p.sdfgi
		env.ssao_enabled = p.ssao
		env.glow_enabled = p.glow
		# without GI the ambient term carries the shading: lift it a little
		env.ambient_light_energy = 0.8 if p.sdfgi else 1.0
	if sun:
		sun.directional_shadow_max_distance = float(p.shadow_distance)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(p.shadow_splits) >= 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	Game.apply_render_scale()
	print("GRAPHICS preset ", preset)


static func target_pixels() -> float:
	return float(PRESETS[current].target_pixels)


static func upscaler() -> int:
	return int(PRESETS[current].upscaler)
