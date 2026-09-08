class_name EnvMaterials
## Builds the environment materials. Uses the Poly Haven texture sets in assets/env when
## present (see tools/fetch_polyhaven.py), otherwise falls back to tinted noise so the
## scene still renders without downloads.

const ENV_DIR := "res://assets/env/"

# material name in the castle glbs -> [texture set id, tint, world size of one tile in metres]
const STONE_SETS := {
	"Stone": ["medieval_blocks_03", Color(0.9, 0.88, 0.85), 3.0],
	"StoneTower": ["castle_brick_07", Color(0.85, 0.84, 0.82), 3.0],
	"Wood": ["weathered_brown_planks", Color(0.8, 0.7, 0.6), 2.0],
	"Dark": ["", Color(0.10, 0.10, 0.11), 1.0],
}
static var _cache := {}


static func has_set(set_id: String) -> bool:
	return set_id != "" and FileAccess.file_exists(ENV_DIR + set_id + "_diffuse.jpg")


static func texture(set_id: String, map: String) -> Texture2D:
	var path := ENV_DIR + set_id + "_" + map + ".jpg"
	if not FileAccess.file_exists(path):
		return null
	return load(path)


## Triplanar PBR material for castle geometry, keyed by the glb material name.
static func stone(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var spec: Array = STONE_SETS.get(name, STONE_SETS["Stone"])
	var set_id: String = spec[0]
	var tint: Color = spec[1]
	var tile: float = spec[2]
	var mat := StandardMaterial3D.new()
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 8.0
	mat.uv1_scale = Vector3.ONE / tile
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if has_set(set_id):
		mat.albedo_color = tint
		mat.albedo_texture = texture(set_id, "diffuse")
		var nrm := texture(set_id, "normal")
		if nrm:
			mat.normal_enabled = true
			mat.normal_texture = nrm
			mat.normal_scale = 1.0
		var arm := texture(set_id, "arm")
		if arm:
			mat.ao_enabled = true
			mat.ao_texture = arm
			mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			mat.roughness_texture = arm
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			mat.roughness = 1.0
	else:
		# fallback: tinted cellular noise
		var base := Color(0.55, 0.52, 0.48) if name != "Wood" else Color(0.36, 0.24, 0.12)
		if name == "Dark":
			base = tint
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		noise.fractal_octaves = 4
		var tex := NoiseTexture2D.new()
		tex.noise = noise
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.72, 0.72, 0.72))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		tex.color_ramp = ramp
		mat.albedo_color = base
		mat.albedo_texture = tex
		mat.roughness = 0.95
	_cache[name] = mat
	return mat


## Apply materials by name to every MeshInstance3D under a node.
static func apply_to(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m: Material = mesh.surface_get_material(i)
			var mat_name := m.resource_name if m else "Stone"
			mi.set_surface_override_material(i, stone(mat_name))


## Terrain shader material blending grass and trampled mud.
static func terrain() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	var grass := "aerial_grass_rock"
	var mud := "brown_mud_leaves_01"
	var textured := has_set(grass) and has_set(mud)
	if textured:
		for pair in [[grass, "grass"], [mud, "mud"]]:
			mat.set_shader_parameter(pair[1] + "_diffuse", texture(pair[0], "diffuse"))
			mat.set_shader_parameter(pair[1] + "_normal", texture(pair[0], "normal"))
			mat.set_shader_parameter(pair[1] + "_arm", texture(pair[0], "arm"))
		mat.set_shader_parameter("grass_tint", Color(1, 1, 1))
		mat.set_shader_parameter("mud_tint", Color(1, 1, 1))
	else:
		mat.set_shader_parameter("grass_tint", Color(0.36, 0.42, 0.20))
		mat.set_shader_parameter("mud_tint", Color(0.36, 0.28, 0.18))
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	mat.set_shader_parameter("noise_tex", tex)
	mat.set_shader_parameter("textured", textured)
	return mat


static func sky_hdri() -> Texture2D:
	var path := ENV_DIR + "kloofendal_48d_partly_cloudy_puresky.hdr"
	return load(path) if FileAccess.file_exists(path) else null
