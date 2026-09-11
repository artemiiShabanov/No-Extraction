"""Hand-held props for the blocky knights, one glb per prop.

Each prop is authored so that in Godot the grip sits at the origin and the
"business end" points along +Y, matching the direction of a hand/forearm bone.

Usage:
    blender -b -P tools/blender/build_weapons.py -- <out_dir>
"""
import os
import sys

import bpy

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT_DIR, exist_ok=True)


def make_mat(name, rgb, rough=0.85, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*rgb, 1.0)
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return {
        "Armor": make_mat("Armor", (0.55, 0.57, 0.60), rough=0.45, metal=0.6),
        "Leather": make_mat("Leather", (0.30, 0.18, 0.09)),
        "Dark": make_mat("Dark", (0.08, 0.08, 0.09)),
        "Shield": make_mat("Shield", (0.85, 0.75, 0.30), rough=0.6),
        "Wood": make_mat("Wood", (0.45, 0.30, 0.15)),
    }


def box(parts, mats, name, size, center, material):
    """Blender coords: +Z becomes Godot +Y (along the bone), -Y becomes Godot -Z (forward)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mats[material])
    parts.append(o)
    return o


def export(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.shade_flat()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    path = os.path.join(OUT_DIR, f"{name.lower()}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_animations=False, export_yup=True)
    print("EXPORTED", path)


# Sword: grip centred at the origin, blade along +Z (Godot +Y, beyond the fist)
mats = reset()
parts = []
box(parts, mats, "Grip", (0.05, 0.05, 0.16), (0, 0, 0.0), "Leather")
box(parts, mats, "Pommel", (0.07, 0.07, 0.04), (0, 0, -0.10), "Dark")
box(parts, mats, "Guard", (0.22, 0.05, 0.04), (0, 0, 0.10), "Dark")
box(parts, mats, "Blade", (0.07, 0.03, 0.46), (0, 0, 0.35), "Armor")
box(parts, mats, "Tip", (0.04, 0.02, 0.06), (0, 0, 0.61), "Armor")
export(parts, "Sword")

# Shield: strapped to the forearm. Thin along X (outward), long along Z (the bone), wide along Y.
mats = reset()
parts = []
box(parts, mats, "Board", (0.06, 0.50, 0.62), (0, 0, 0), "Shield")
box(parts, mats, "Rim", (0.07, 0.54, 0.05), (0, 0, 0.31), "Dark")
box(parts, mats, "RimBottom", (0.07, 0.54, 0.05), (0, 0, -0.31), "Dark")
box(parts, mats, "Boss", (0.05, 0.16, 0.16), (0.05, 0, 0), "Armor")
export(parts, "Shield")

# Banner: pole up the back (Blender +Z = Godot +Y along the spine), flag to the side
mats = reset()
mats["Flag"] = make_mat("Flag", (0.85, 0.15, 0.12))
parts = []
box(parts, mats, "Pole", (0.05, 0.05, 1.7), (0, 0, 0.55), "Wood")
box(parts, mats, "Finial", (0.09, 0.09, 0.09), (0, 0, 1.42), "Armor")
box(parts, mats, "Flag", (0.6, 0.02, 0.42), (0.32, 0, 1.12), "Flag")
box(parts, mats, "FlagTail", (0.2, 0.02, 0.2), (0.7, 0, 1.05), "Flag")
export(parts, "Banner")

# Plume: on top of the helmet, leaning back (Blender +Y = Godot -Z is forward, so back is -Y)
mats = reset()
mats["Plume"] = make_mat("Plume", (0.85, 0.15, 0.12))
parts = []
box(parts, mats, "Base", (0.08, 0.08, 0.08), (0, 0, 0.03), "Armor")
box(parts, mats, "P1", (0.07, 0.10, 0.16), (0, 0.02, 0.15), "Plume")
box(parts, mats, "P2", (0.06, 0.12, 0.14), (0, 0.08, 0.27), "Plume")
box(parts, mats, "P3", (0.05, 0.14, 0.10), (0, 0.16, 0.34), "Plume")
export(parts, "Plume")

# Ram log: along Blender Y (Godot Z); the iron cap at -Y is the front (Godot +Z, towards the gate)
mats = reset()
parts = []
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.22, depth=3.2, location=(0, 0, 0), rotation=(1.5708, 0, 0))
log = bpy.context.active_object
log.name = "Log"
bpy.ops.object.transform_apply(rotation=True)
log.data.materials.append(mats["Wood"])
parts.append(log)
box(parts, mats, "Cap", (0.5, 0.3, 0.5), (0, -1.55, 0), "Armor")
for y in (-0.9, -0.3, 0.3, 0.9):
    box(parts, mats, "Bar", (1.3, 0.07, 0.07), (0, y, 0.05), "Dark")
export(parts, "RamLog")

# Spear: for later enemy variants
mats = reset()
parts = []
box(parts, mats, "Shaft", (0.04, 0.04, 2.0), (0, 0, 0.6), "Wood")
box(parts, mats, "Head", (0.06, 0.03, 0.30), (0, 0, 1.72), "Armor")
export(parts, "Spear")
