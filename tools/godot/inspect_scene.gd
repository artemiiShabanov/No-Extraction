extends SceneTree
## Prints skeleton bones, animations and mesh info for imported model scenes.
## Usage: Godot --headless --path . --script tools/godot/inspect_scene.gd -- res://path/a.fbx [res://path/b.glb ...]

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("res://"):
			continue
		print("==== ", arg)
		var packed: PackedScene = load(arg)
		if packed == null:
			print("  FAILED to load")
			continue
		var root := packed.instantiate()
		_dump(root, 0)
		root.free()
	quit()


func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var info := "%s%s (%s)" % [pad, n.name, n.get_class()]
	if n is Skeleton3D:
		info += " bones=%d" % n.get_bone_count()
	if n is MeshInstance3D and n.mesh:
		var aabb: AABB = n.mesh.get_aabb()
		info += " surfaces=%d aabb=%s" % [n.mesh.get_surface_count(), aabb]
		for i in n.mesh.get_surface_count():
			var m: Material = n.mesh.surface_get_material(i)
			info += " [%s]" % (m.resource_name if m else "null")
	if n is AnimationPlayer:
		info += " root=%s" % n.root_node
		for lib in n.get_animation_library_list():
			for a in n.get_animation_library(lib).get_animation_list():
				var anim: Animation = n.get_animation(a)
				info += "\n%s  anim '%s/%s' len=%.2f tracks=%d first=%s" % [pad, lib, a, anim.length, anim.get_track_count(), anim.track_get_path(0) if anim.get_track_count() > 0 else "-"]
	print(info)
	if n is Skeleton3D:
		for i in n.get_bone_count():
			var rest: Transform3D = n.get_bone_rest(i)
			print("%s    bone %2d %-28s parent=%2d rest.origin=%s" % [pad, i, n.get_bone_name(i), n.get_bone_parent(i), rest.origin])
	for c in n.get_children():
		_dump(c, depth + 1)
