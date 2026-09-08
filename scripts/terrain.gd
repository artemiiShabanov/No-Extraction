extends StaticBody3D
class_name Terrain
## Heightfield around the castle: flat approach in front of the wall, rolling field further out.

@export var size := 600.0
@export var step := 2.0
@export var hill_height := 5.0

var noise := FastNoiseLite.new()
var mesh_instance: MeshInstance3D


func _ready() -> void:
	Game.terrain = self
	collision_layer = Game.LAYER_WORLD
	collision_mask = 0
	noise.seed = 11
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.008
	noise.fractal_octaves = 3
	_build()


## Terrain height at a world position (same function the mesh is built from).
func height_at(x: float, z: float) -> float:
	var h := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * hill_height
	h += noise.get_noise_2d(x * 4.0 + 500.0, z * 4.0) * 0.35  # small bumps
	# flat plateau where the castle stands and the army approaches
	var fx := smoothstep(70.0, 130.0, abs(x))
	var fz := smoothstep(70.0, 130.0, abs(z + 30.0))
	var flat: float = maxf(fx, fz)
	return h * flat


func _build() -> void:
	var n := int(size / step) + 1
	var half := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for iz in n:
		for ix in n:
			heights[iz * n + ix] = height_at(-half + ix * step, -half + iz * step)
	for iz in n:
		for ix in n:
			var x := -half + ix * step
			var z := -half + iz * step
			var hl := heights[iz * n + maxi(ix - 1, 0)]
			var hr := heights[iz * n + mini(ix + 1, n - 1)]
			var hd := heights[maxi(iz - 1, 0) * n + ix]
			var hu := heights[mini(iz + 1, n - 1) * n + ix]
			var normal := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			st.set_normal(normal)
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, heights[iz * n + ix], z))
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_tangents()
	var mesh := st.commit()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = EnvMaterials.terrain()
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	hm.map_data = heights
	shape.shape = hm
	shape.scale = Vector3(step, 1.0, step)
	add_child(shape)
