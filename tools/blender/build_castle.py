"""Modular castle pieces for the greybox replacement. One glb per module.

Authored in Blender with X along the wall, Z up and +Y towards the enemy
(glTF turns Blender +Y into Godot -Z, which is the direction the wall faces).

Usage:
    blender -b -P tools/blender/build_castle.py -- <out_dir> [preview_dir]
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR = argv[0]
PREVIEW_DIR = argv[1] if len(argv) > 1 else None
os.makedirs(OUT_DIR, exist_ok=True)
random.seed(3)

WALL_LEN = 10.0
WALK_Z = 10.0        # walkway height, matches the player spawn
PARAPET_Z = 11.0     # chest-high solid parapet
MERLON_H = 0.9
OUTER = 3.0          # outer face y (enemy side)
INNER = -3.0


def make_mat(name, rgb, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*rgb, 1.0)
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return {
        "Stone": make_mat("Stone", (0.55, 0.52, 0.48)),
        "StoneTower": make_mat("StoneTower", (0.48, 0.46, 0.44)),
        "Wood": make_mat("Wood", (0.36, 0.24, 0.12)),
        "Dark": make_mat("Dark", (0.10, 0.10, 0.11), rough=0.6),
    }


parts = []


def box(mats, name, size, center, material, rot_z=0.0, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.rotation_euler = (0, 0, rot_z)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mats[material])
    parts.append(o)
    return o


def cylinder(mats, name, radius, depth, center, material, verts=24, radius_top=None, bevel=0.0):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius if radius_top is None else radius_top, depth=depth, location=center)
    o = bpy.context.active_object
    o.name = name
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mats[material])
    parts.append(o)
    return o


def profile_extrude(mats, name, profile_yz, length, material):
    """Extrude a closed (y, z) polygon along X, centred on the origin."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    verts = [bm.verts.new(Vector((-length / 2, y, z))) for y, z in profile_yz]
    face = bm.faces.new(verts)
    r = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [g for g in r["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=Vector((length, 0, 0)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mats[material])
    parts.append(o)
    return o


def merlons_along_x(mats, x0, x1, y, z, material, step=2.2, width=1.2):
    x = x0 + step / 2
    while x <= x1 - width / 2 + 0.01:
        box(mats, "Merlon", (width, 0.8, MERLON_H), (x, y, z + MERLON_H / 2), material,
            rot_z=random.uniform(-0.02, 0.02), bevel=0.06)
        x += step


def export(name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.shade_flat()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    path = os.path.join(OUT_DIR, f"{name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_animations=False, export_yup=True)
    print("EXPORTED", path, "verts", len(obj.data.vertices))
    if PREVIEW_DIR:
        os.makedirs(PREVIEW_DIR, exist_ok=True)
        scene = bpy.context.scene
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "MATERIAL"
        scene.display.shading.show_shadows = True
        scene.render.resolution_x = 800
        scene.render.resolution_y = 600
        cam_data = bpy.data.cameras.new("Cam")
        cam = bpy.data.objects.new("Cam", cam_data)
        scene.collection.objects.link(cam)
        dims = obj.dimensions
        dist = max(dims) * 1.6
        cam.location = Vector((dist * 0.6, dist * 0.8, dims.z * 0.9 + dist * 0.25))
        direction = Vector((0, 0, dims.z * 0.45)) - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cam_data.clip_end = 1000
        scene.camera = cam
        scene.render.filepath = os.path.join(PREVIEW_DIR, f"{name}.png")
        bpy.ops.render.render(write_still=True)
    parts.clear()


# ---------------------------------------------------------------- wall segment
mats = reset()
# (y, z) profile: inner face, walkway, outer parapet, battered outer face
profile = [
    (INNER, 0.0), (OUTER + 1.0, 0.0),        # battered base spreads 1 m outward
    (OUTER, 3.0),                             # batter ends 3 m up
    (OUTER, PARAPET_Z), (OUTER - 0.8, PARAPET_Z),  # outer parapet 0.8 thick
    (OUTER - 0.8, WALK_Z), (INNER + 0.4, WALK_Z),   # walkway
    (INNER + 0.4, WALK_Z + 0.6), (INNER, WALK_Z + 0.6),  # low inner parapet
]
profile_extrude(mats, "WallBody", profile, WALL_LEN, "Stone")
merlons_along_x(mats, -WALL_LEN / 2, WALL_LEN / 2, OUTER - 0.4, PARAPET_Z, "Stone")
# string course ledge and corbels under the parapet on the outer face
box(mats, "Ledge", (WALL_LEN, 0.35, 0.3), (0, OUTER + 0.1, WALK_Z - 0.3), "Stone", bevel=0.04)
x = -WALL_LEN / 2 + 0.55
while x < WALL_LEN / 2:
    box(mats, "Corbel", (0.45, 0.45, 0.55), (x, OUTER + 0.05, WALK_Z - 0.75), "Stone", bevel=0.05)
    x += 1.1
export("wall_segment")

# ---------------------------------------------------------------- round tower
mats = reset()
R0, R1, H = 5.0, 4.6, 13.0
cylinder(mats, "TowerBody", R0, H, (0, 0, H / 2), "StoneTower", verts=28, radius_top=R1)
cylinder(mats, "TowerCap", R1 + 0.35, 1.2, (0, 0, H + 0.6), "StoneTower", verts=28)  # parapet ring, solid top
n = 18
for i in range(n):
    a = i / n * math.tau
    r = R1 + 0.05
    box(mats, "TowerMerlon", (1.1, 0.7, MERLON_H), (math.cos(a) * r, math.sin(a) * r, H + 1.2 + MERLON_H / 2),
        "StoneTower", rot_z=a + math.pi / 2, bevel=0.06)
    box(mats, "TowerCorbel", (0.5, 0.5, 0.55), (math.cos(a) * (R1 + 0.15), math.sin(a) * (R1 + 0.15), H - 0.4),
        "StoneTower", rot_z=a, bevel=0.05)
export("tower_round")

# ---------------------------------------------------------------- gatehouse (with arch)
mats = reset()
GW, GD, GH = 9.0, 6.0, 12.0
body = box(mats, "GateBody", (GW, GD + 1.0, GH), (0, 0.0, GH / 2), "Stone")
# passage: box + half cylinder, cut out with a boolean
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 1.75))
cut = bpy.context.active_object
cut.scale = (4.0, GD + 4.0, 3.5)
bpy.ops.object.transform_apply(scale=True)
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=2.0, depth=GD + 4.0, location=(0, 0, 3.5), rotation=(math.pi / 2, 0, 0))
arch = bpy.context.active_object
for cutter in (cut, arch):
    mod = body.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter)
merlons_along_x(mats, -GW / 2, GW / 2, OUTER + 0.1, GH, "Stone")
box(mats, "GateLedge", (GW, 0.35, 0.3), (0, OUTER + 0.6, GH - 1.3), "Stone", bevel=0.04)
x = -GW / 2 + 0.55
while x < GW / 2:
    box(mats, "GateCorbel", (0.45, 0.45, 0.55), (x, OUTER + 0.55, GH - 1.75), "Stone", bevel=0.05)
    x += 1.1
export("gatehouse")

# ---------------------------------------------------------------- gate doors
mats = reset()
for sx in (-1, 1):
    box(mats, "Door", (1.95, 0.3, 5.3), (sx * 1.0, 0.0, 2.65), "Wood")
    for z in (0.8, 2.6, 4.4):
        box(mats, "Band", (1.9, 0.06, 0.18), (sx * 1.0, 0.18, z), "Dark")
        box(mats, "Band", (1.9, 0.06, 0.18), (sx * 1.0, -0.18, z), "Dark")
export("gate_doors")
