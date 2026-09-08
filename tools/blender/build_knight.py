"""Procedural blocky knight with armature and Run/Idle/Attack animations.

Usage:
    blender -b -P tools/blender/build_knight.py -- <out.glb> [preview_dir]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
PREVIEW_DIR = argv[1] if len(argv) > 1 and not argv[1].startswith("--") else None
# --mixamo <out.fbx>: export a T-posed, unrigged mesh for the Mixamo auto-rigger
MIXAMO_OUT = argv[argv.index("--mixamo") + 1] if "--mixamo" in argv else None
T_POSE = MIXAMO_OUT is not None

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30


# ---------------------------------------------------------------- materials
def make_mat(name, rgb, rough=0.85, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*rgb, 1.0)
    return m


MAT = {
    "Skin": make_mat("Skin", (0.87, 0.62, 0.45)),
    "Tunic": make_mat("Tunic", (0.75, 0.12, 0.10)),
    "Armor": make_mat("Armor", (0.55, 0.57, 0.60), rough=0.45, metal=0.6),
    "Leather": make_mat("Leather", (0.30, 0.18, 0.09)),
    "Wood": make_mat("Wood", (0.45, 0.30, 0.15)),
    "Dark": make_mat("Dark", (0.08, 0.08, 0.09)),
    "Shield": make_mat("Shield", (0.85, 0.75, 0.30), rough=0.6),
}

parts = []


# Coordinates below are authored with the character facing -Y (Blender "front").
# glTF export maps Blender -Y to +Z, which is *backwards* for Godot, so every
# Y coordinate and every X rotation is mirrored here to make the export face -Z.
# The FBX exporter has its own axis conversion, so the Mixamo mesh is not mirrored.
FLIP = 1.0 if T_POSE else -1.0


def box(name, size, center, bone, material):
    """Axis aligned box. size=(x,y,z) full extents, center=(x,y,z) authored with front at -Y."""
    center = (center[0], center[1] * FLIP, center[2])
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(MAT[material])
    vg = o.vertex_groups.new(name=bone)
    vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    parts.append(o)
    return o


# ---------------------------------------------------------------- geometry
# Chunky proportions: big head, wide torso, short legs. Height ~1.75 m.
HIP = 0.85
KNEE = 0.45
SHOULDER = 1.30
CHEST_TOP = 1.36
HEAD_BOTTOM = 1.40

# legs
for side, sx in (("L", 0.13), ("R", -0.13)):
    box(f"UpperLeg.{side}", (0.20, 0.22, HIP - KNEE), (sx, 0.0, (HIP + KNEE) / 2), f"UpperLeg.{side}", "Leather")
    box(f"LowerLeg.{side}", (0.18, 0.20, KNEE - 0.06), (sx, 0.0, (KNEE + 0.06) / 2), f"LowerLeg.{side}", "Armor")
    box(f"Foot.{side}", (0.19, 0.30, 0.10), (sx, -0.04, 0.05), f"LowerLeg.{side}", "Dark")

# pelvis + torso
box("Pelvis", (0.48, 0.30, 0.18), (0.0, 0.0, HIP + 0.02), "Hips", "Leather")
box("Torso", (0.56, 0.34, CHEST_TOP - HIP - 0.08), (0.0, 0.0, (CHEST_TOP + HIP) / 2), "Spine", "Tunic")
box("ChestPlate", (0.50, 0.12, 0.30), (0.0, -0.15, 1.18), "Spine", "Armor")
box("Belt", (0.58, 0.36, 0.06), (0.0, 0.0, 0.98), "Spine", "Dark")

# head + helmet
box("Head", (0.36, 0.36, 0.38), (0.0, 0.0, HEAD_BOTTOM + 0.19), "Head", "Skin")
box("HelmetTop", (0.42, 0.42, 0.14), (0.0, 0.0, HEAD_BOTTOM + 0.36), "Head", "Armor")
box("HelmetBack", (0.42, 0.20, 0.30), (0.0, 0.11, HEAD_BOTTOM + 0.17), "Head", "Armor")
box("HelmetSideL", (0.04, 0.42, 0.28), (0.20, 0.0, HEAD_BOTTOM + 0.18), "Head", "Armor")
box("HelmetSideR", (0.04, 0.42, 0.28), (-0.20, 0.0, HEAD_BOTTOM + 0.18), "Head", "Armor")
box("NoseGuard", (0.06, 0.05, 0.22), (0.0, -0.20, HEAD_BOTTOM + 0.16), "Head", "Armor")

# arms: authored hanging down, relative to the shoulder joint. In T-pose mode the
# whole arm (with shield and sword) is rotated 90 degrees to point sideways.
def arm_box(name, size, rel, side, bone, material):
    s = 1 if side == "L" else -1
    x, y, z = rel
    sx_, sy_, sz_ = size
    if T_POSE:
        # rotate about the front axis so "down" becomes "outward"
        x, z = -z * s, x * s
        sx_, sz_ = sz_, sx_
    box(name, (sx_, sy_, sz_), (0.36 * s + x, y, SHOULDER + z), bone, material)


for side in ("L", "R"):
    arm_box(f"Pauldron.{side}", (0.24, 0.30, 0.16), (0.0, 0.0, 0.02), side, f"UpperArm.{side}", "Armor")
    arm_box(f"UpperArm.{side}", (0.17, 0.18, 0.30), (0.0, 0.0, -0.17), side, f"UpperArm.{side}", "Tunic")
    arm_box(f"LowerArm.{side}", (0.15, 0.16, 0.30), (0.0, 0.0, -0.47), side, f"LowerArm.{side}", "Leather")
    arm_box(f"Hand.{side}", (0.14, 0.14, 0.12), (0.0, 0.0, -0.66), side, f"LowerArm.{side}", "Skin")

# shield on left forearm, sword in right hand
arm_box("Shield", (0.06, 0.50, 0.62), (0.12, 0.0, -0.45), "L", "LowerArm.L", "Shield")
arm_box("ShieldBoss", (0.04, 0.16, 0.16), (0.16, 0.0, -0.45), "L", "LowerArm.L", "Armor")
arm_box("SwordGrip", (0.05, 0.05, 0.16), (0.0, -0.12, -0.66), "R", "LowerArm.R", "Leather")
arm_box("SwordGuard", (0.22, 0.05, 0.04), (0.0, -0.12, -0.76), "R", "LowerArm.R", "Dark")
arm_box("SwordBlade", (0.07, 0.03, 0.46), (0.0, -0.12, -1.01), "R", "LowerArm.R", "Armor")

# join into one mesh
bpy.ops.object.select_all(action="DESELECT")
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
mesh = bpy.context.active_object
mesh.name = "KnightMesh"
bpy.ops.object.shade_flat()

if MIXAMO_OUT:
    os.makedirs(os.path.dirname(MIXAMO_OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=MIXAMO_OUT,
        use_selection=True,
        object_types={"MESH"},
        mesh_smooth_type="OFF",
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="COPY",
        embed_textures=False,
        apply_scale_options="FBX_SCALE_ALL",
    )
    if PREVIEW_DIR:
        os.makedirs(PREVIEW_DIR, exist_ok=True)
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "MATERIAL"
        scene.render.resolution_x = 640
        scene.render.resolution_y = 640
        cam_data = bpy.data.cameras.new("Cam")
        cam = bpy.data.objects.new("Cam", cam_data)
        scene.collection.objects.link(cam)
        cam.location = (0.0, -4.5, 1.0)
        cam.rotation_euler = (math.radians(90), 0, 0)
        scene.camera = cam
        scene.render.filepath = os.path.join(PREVIEW_DIR, "tpose_front.png")
        bpy.ops.render.render(write_still=True)
    print("EXPORTED", MIXAMO_OUT)
    sys.exit(0)

# ---------------------------------------------------------------- armature
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm = bpy.context.active_object
arm.name = "KnightRig"
arm.data.name = "KnightRig"
eb = arm.data.edit_bones
for b in list(eb):
    eb.remove(b)


def bone(name, head, tail, parent=None):
    b = eb.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    b.roll = 0.0
    if parent:
        b.parent = eb[parent]
    return b


bone("Hips", (0, 0, HIP), (0, 0, HIP + 0.12))
bone("Spine", (0, 0, HIP + 0.12), (0, 0, CHEST_TOP), "Hips")
bone("Head", (0, 0, CHEST_TOP), (0, 0, HEAD_BOTTOM + 0.42), "Spine")
for side, s in (("L", 1), ("R", -1)):
    bone(f"UpperArm.{side}", (0.36 * s, 0, SHOULDER), (0.36 * s, 0, SHOULDER - 0.32), "Spine")
    bone(f"LowerArm.{side}", (0.36 * s, 0, SHOULDER - 0.32), (0.36 * s, 0, SHOULDER - 0.72), f"UpperArm.{side}")
    bone(f"UpperLeg.{side}", (0.13 * s, 0, HIP), (0.13 * s, 0, KNEE), "Hips")
    bone(f"LowerLeg.{side}", (0.13 * s, 0, KNEE), (0.13 * s, 0, 0.0), f"UpperLeg.{side}")
bpy.ops.object.mode_set(mode="OBJECT")

mesh.parent = arm
mod = mesh.modifiers.new("Armature", "ARMATURE")
mod.object = arm

# ---------------------------------------------------------------- animation
for pb in arm.pose.bones:
    pb.rotation_mode = "XYZ"

arm.animation_data_create()


def deg(*a):
    return tuple(math.radians(x) for x in a)


def start_action(name, frame_end):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    # Blender 4.4+ slotted actions
    if hasattr(act, "slots"):
        slot = act.slots.new(id_type="OBJECT", name="KnightRig")
        arm.animation_data.action_slot = slot
    if hasattr(act, "use_frame_range"):
        act.use_frame_range = True
        act.frame_start = 1
        act.frame_end = frame_end
    for pb in arm.pose.bones:
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)
    return act


def key(bone_name, frame, rot=None, loc=None):
    pb = arm.pose.bones[bone_name]
    if rot is not None:
        pb.rotation_euler = deg(rot[0] * FLIP, rot[1], rot[2])
        pb.keyframe_insert("rotation_euler", frame=frame)
    if loc is not None:
        pb.location = loc
        pb.keyframe_insert("location", frame=frame)


def finish_action(act, name):
    arm.animation_data.action = None
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(act.frame_range[0]), act)
    strip.name = name
    if hasattr(strip, "action_slot") and hasattr(act, "slots"):
        strip.action_slot = act.slots[0]


# Run cycle: 20 frames (0.67 s). Bone local X is world X for vertical bones,
# so rotation about X swings limbs forward/back.
run = start_action("Run", 21)
LEG = 42
ARM = 30
for f, ph in ((1, 0.0), (6, 0.5), (11, 1.0), (16, 1.5), (21, 2.0)):
    s = math.sin(ph * math.pi)  # -1..1 over the cycle
    c = math.cos(ph * math.pi)
    key("UpperLeg.L", f, rot=(LEG * c, 0, 0))
    key("UpperLeg.R", f, rot=(-LEG * c, 0, 0))
    # knee bends while the leg swings forward (blocky, exaggerated)
    key("LowerLeg.L", f, rot=(-max(0.0, -s) * 75 - 8, 0, 0))
    key("LowerLeg.R", f, rot=(-max(0.0, s) * 75 - 8, 0, 0))
    key("UpperArm.L", f, rot=(-ARM * c - 10, 0, 0))
    key("UpperArm.R", f, rot=(ARM * c - 10, 0, 0))
    key("LowerArm.L", f, rot=(-70, 0, 0))
    key("LowerArm.R", f, rot=(-80, 0, 0))
    key("Spine", f, rot=(-12, 0, 0))
    key("Head", f, rot=(6, 0, 0))
    key("Hips", f, loc=(0, 0, -0.03 * abs(s)))
finish_action(run, "Run")

# Idle: two-frame gentle sway, 40 frames
idle = start_action("Idle", 41)
for f, ph in ((1, 0.0), (21, 1.0), (41, 2.0)):
    s = math.sin(ph * math.pi / 1.0)
    key("UpperLeg.L", f, rot=(0, 0, 0))
    key("UpperLeg.R", f, rot=(0, 0, 0))
    key("LowerLeg.L", f, rot=(0, 0, 0))
    key("LowerLeg.R", f, rot=(0, 0, 0))
    key("UpperArm.L", f, rot=(-10, 0, 0))
    key("UpperArm.R", f, rot=(-10, 0, 0))
    key("LowerArm.L", f, rot=(-60, 0, 0))
    key("LowerArm.R", f, rot=(-70, 0, 0))
    key("Spine", f, rot=(-2 - 2 * s, 0, 0))
    key("Head", f, rot=(2 * s, 0, 0))
    key("Hips", f, loc=(0, 0, -0.01 * s))
finish_action(idle, "Idle")

# Attack: raise sword and chop, 18 frames
atk = start_action("Attack", 19)
for f, ua, la, sp in ((1, -80, -80, -8), (7, -170, -60, 5), (11, -20, -30, -25), (19, -80, -80, -8)):
    key("UpperArm.R", f, rot=(ua, 0, 0))
    key("LowerArm.R", f, rot=(la, 0, 0))
    key("UpperArm.L", f, rot=(-30, 0, 0))
    key("LowerArm.L", f, rot=(-70, 0, 0))
    key("Spine", f, rot=(sp, 0, 0))
    key("Head", f, rot=(4, 0, 0))
    key("UpperLeg.L", f, rot=(15, 0, 0))
    key("UpperLeg.R", f, rot=(-15, 0, 0))
    key("LowerLeg.L", f, rot=(-15, 0, 0))
    key("LowerLeg.R", f, rot=(-10, 0, 0))
finish_action(atk, "Attack")

# ---------------------------------------------------------------- preview renders
if PREVIEW_DIR:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (2.6, -3.2, 1.6)
    cam.rotation_euler = (math.radians(78), 0, math.radians(38))
    scene.camera = cam
    # assign each action directly (NLA is not evaluated reliably in background mode)
    for t in arm.animation_data.nla_tracks:
        t.mute = True
    for act_name in ("Run", "Idle", "Attack"):
        act = bpy.data.actions[act_name]
        arm.animation_data.action = act
        if hasattr(act, "slots"):
            arm.animation_data.action_slot = act.slots[0]
        for frame in (1, 6, 11):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            scene.render.filepath = os.path.join(PREVIEW_DIR, f"{act_name}_{frame:02d}.png")
            bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None
    for t in arm.animation_data.nla_tracks:
        t.mute = False
    bpy.data.objects.remove(cam)

# ---------------------------------------------------------------- export
bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_yup=True,
    export_skins=True,
    export_materials="EXPORT",
)
print("EXPORTED", OUT)
