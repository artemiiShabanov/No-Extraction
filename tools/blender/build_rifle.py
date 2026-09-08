"""Procedural low-poly bolt-action sniper rifle. Barrel points -Y (Godot -Z).

Usage:
    blender -b -P tools/blender/build_rifle.py -- <out.glb>
"""
import math
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)


def make_mat(name, rgb, rough=0.6, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


MAT = {
    "Metal": make_mat("Metal", (0.10, 0.11, 0.12), rough=0.45, metal=0.8),
    "Wood": make_mat("Wood", (0.32, 0.18, 0.09), rough=0.7),
    "Black": make_mat("Black", (0.03, 0.03, 0.03), rough=0.5),
    "Lens": make_mat("Lens", (0.2, 0.5, 0.9), rough=0.1, metal=0.2),
}
parts = []


def box(name, size, center, material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(MAT[material])
    parts.append(o)
    return o


def cyl(name, radius, length, center, material, axis="Y", verts=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length, location=center)
    o = bpy.context.active_object
    o.name = name
    if axis == "Y":
        o.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(MAT[material])
    parts.append(o)
    return o


# Origin at the grip. -Y is forward.
box("Receiver", (0.05, 0.42, 0.07), (0, -0.10, 0.02), "Metal")
cyl("Barrel", 0.013, 0.62, (0, -0.60, 0.035), "Metal")
cyl("BarrelShroud", 0.02, 0.14, (0, -0.36, 0.035), "Metal")
box("Stock", (0.045, 0.30, 0.09), (0, 0.22, -0.02), "Wood")
box("StockButt", (0.05, 0.06, 0.13), (0, 0.38, -0.05), "Black")
box("Forend", (0.05, 0.36, 0.05), (0, -0.30, -0.01), "Wood")
box("Grip", (0.04, 0.06, 0.12), (0, 0.06, -0.08), "Wood")
box("Magazine", (0.04, 0.10, 0.08), (0, -0.14, -0.06), "Metal")
box("Trigger", (0.01, 0.02, 0.04), (0, 0.0, -0.05), "Black")
box("TriggerGuard", (0.03, 0.08, 0.008), (0, 0.0, -0.07), "Metal")
cyl("BoltHandle", 0.008, 0.06, (0.05, 0.02, 0.05), "Metal", axis="X")
cyl("BoltKnob", 0.014, 0.02, (0.075, 0.02, 0.05), "Black", axis="X")
# scope
box("MountR", (0.03, 0.03, 0.03), (0, -0.20, 0.07), "Metal")
box("MountF", (0.03, 0.03, 0.03), (0, 0.0, 0.07), "Metal")
cyl("ScopeTube", 0.017, 0.26, (0, -0.10, 0.10), "Black", verts=12)
cyl("ScopeFront", 0.024, 0.07, (0, -0.25, 0.10), "Black", verts=12)
cyl("ScopeRear", 0.021, 0.05, (0, 0.05, 0.10), "Black", verts=12)
cyl("Lens", 0.020, 0.004, (0, -0.286, 0.10), "Lens", verts=12)

bpy.ops.object.select_all(action="DESELECT")
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
rifle = bpy.context.active_object
rifle.name = "Rifle"
bpy.ops.object.shade_flat()

# muzzle marker
muzzle = bpy.data.objects.new("Muzzle", None)
muzzle.location = (0, -0.91, 0.035)
bpy.context.scene.collection.objects.link(muzzle)
muzzle.parent = rifle

bpy.ops.object.select_all(action="DESELECT")
rifle.select_set(True)
muzzle.select_set(True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_animations=False,
    export_yup=True,
    export_materials="EXPORT",
)
print("EXPORTED", OUT)
