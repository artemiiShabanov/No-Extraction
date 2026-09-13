extends Node3D
## Slow, heavy, visible bullet with gravity drop and a fading ribbon trail.

@export var speed := 170.0
@export var gravity := 9.8
@export var drag := 0.05
@export var max_life := 6.0
@export var trail_points := 40
@export var impact_impulse := 16.0

var velocity := Vector3.ZERO
var life := 0.0
var points: PackedVector3Array = []
var trail_mi: MeshInstance3D
var trail_mesh: ImmediateMesh
var head: MeshInstance3D
var active := false


func launch(origin: Vector3, direction: Vector3, visual_origin: Vector3 = Vector3.INF) -> void:
	global_position = origin
	velocity = direction.normalized() * speed
	points = PackedVector3Array([visual_origin if visual_origin != Vector3.INF else origin])
	active = true


func _ready() -> void:
	trail_mesh = ImmediateMesh.new()
	trail_mi = MeshInstance3D.new()
	trail_mi.mesh = trail_mesh
	trail_mi.top_level = true
	trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 3.0
	trail_mi.material_override = mat
	add_child(trail_mi)
	trail_mi.global_transform = Transform3D.IDENTITY

	head = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	head.mesh = sphere
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(1.0, 0.95, 0.8)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.8, 0.4)
	hm.emission_energy_multiplier = 6.0
	head.material_override = hm
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)


func _physics_process(delta: float) -> void:
	if not active:
		return
	life += delta
	if life > max_life:
		queue_free()
		return
	var next := global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next)
	query.collision_mask = Game.LAYER_WORLD | Game.LAYER_RAGDOLL | Game.LAYER_HITBOX
	query.collide_with_areas = true
	query.hit_from_inside = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_on_hit(hit)
		return
	velocity.y -= gravity * delta
	velocity -= velocity * drag * delta
	global_position = next
	points.append(next)
	if points.size() > trail_points:
		points.remove_at(0)
	_rebuild_trail()


func _on_hit(hit: Dictionary) -> void:
	var collider: Object = hit.collider
	var dir := velocity.normalized()
	if collider is Area3D and collider.has_meta("knight"):
		var knight: Node = collider.get_meta("knight")
		if is_instance_valid(knight):
			Game.hits += 1
			knight.hit_zone(collider.get_meta("zone"), hit.position, dir * impact_impulse)
	elif collider.has_method("hit"):
		collider.hit(hit.position, dir * impact_impulse, self)
	else:
		_spawn_impact(hit.position, hit.normal, Color(0.62, 0.58, 0.5, 0.9))
	queue_free()


func _spawn_impact(pos: Vector3, normal: Vector3, color: Color) -> void:
	spawn_puff(get_tree().current_scene, pos, normal, color)


static func spawn_puff(parent: Node, pos: Vector3, normal: Vector3, color: Color, amount: int = 14, size: float = 0.35) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = normal
	pm.spread = 55.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -4.0, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _soft_dot()
	quad.material = qm
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var timer := parent.get_tree().create_timer(1.5)
	timer.timeout.connect(p.queue_free)


static var _soft_dot_tex: GradientTexture2D


static func _soft_dot() -> GradientTexture2D:
	if _soft_dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.6))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_soft_dot_tex = t
	return _soft_dot_tex


func _rebuild_trail() -> void:
	trail_mesh.clear_surfaces()
	if points.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := points.size()
	for i in n:
		var t := float(i) / float(n - 1)
		var p := points[i]
		var d: Vector3
		if i < n - 1:
			d = (points[i + 1] - p).normalized()
		else:
			d = (p - points[i - 1]).normalized()
		var side := (cam_pos - p).cross(d).normalized() * (0.015 + 0.05 * t)
		trail_mesh.surface_set_color(Color(1, 1, 1, t * t))
		trail_mesh.surface_add_vertex(p + side)
		trail_mesh.surface_add_vertex(p - side)
	trail_mesh.surface_end()
