"""Builds the desktop mascots (pig, cat) in Blender, animates every clip and renders one sprite sheet per animal.

Run inside Blender (Text editor or `blender -b -P Art/mascots/build_mascots.py`). Writes:
  Resources/Mascots/<animal>.png              8 x 6 sheet of 160 px frames, transparent
  Sources/SoundControlCore/MascotSpriteData.swift   eye spots, head anchors and stride lengths per frame

The pupils, eyelids, brows and mood marks are not rendered: the app draws them on top so the eyes can follow the
mouse and the face can change without extra frames.
"""
import math
import os

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

ROOT = os.environ.get("MASCOT_ROOT", "/Users/pond/Documents/Goal/system-controller")
FRAME_PX = 160
COLUMNS = 8
ROWS = 6
VIEW_POINTS = 80  # MascotStroll.size: the sprite is shown this many points wide.
CLIPS = [("walk", 16), ("run", 8), ("idle", 12), ("held", 6), ("fly", 4)]
LEGS = ("FL", "FR", "BL", "BR")


def smooth(u):
    return u * u * (3 - 2 * u)


# MARK: - Scene helpers

def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for collection in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights,
                       bpy.data.actions):
        for block in list(collection):
            if block.users == 0:
                collection.remove(block)


def material(name, color, roughness=0.55, stripes=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = roughness
    if stripes is None:
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        return mat
    # Tabby stripes: a wave across the body, mixed between the base and the darker stripe colour.
    links = mat.node_tree.links
    coords = nodes.new("ShaderNodeTexCoord")
    wave = nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 2.2
    wave.inputs["Distortion"].default_value = 3.0
    wave.inputs["Detail"].default_value = 1.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45
    ramp.color_ramp.elements[0].color = (*stripes, 1)
    ramp.color_ramp.elements[1].position = 0.62
    ramp.color_ramp.elements[1].color = (*color, 1)
    links.new(coords.outputs["Generated"], wave.inputs["Vector"])
    links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def empty(name, parent, loc=(0, 0, 0), rot=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    attach(obj, parent, loc, rot)
    return obj


def attach(obj, parent, loc, rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.parent = parent
    obj.matrix_parent_inverse.identity()
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale


def sphere(name, parent, loc, scale, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=28, ring_count=14, radius=1)
    obj = bpy.context.active_object
    finish(obj, name, parent, loc, rot, scale, mat)
    return obj


def cone(name, parent, loc, bottom, top, depth, mat, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cone_add(vertices=20, radius1=bottom, radius2=top, depth=depth)
    obj = bpy.context.active_object
    finish(obj, name, parent, loc, rot, scale, mat)
    return obj


def torus(name, parent, loc, major, minor, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=24, minor_segments=10)
    obj = bpy.context.active_object
    finish(obj, name, parent, loc, rot, (1, 1, 1), mat)
    return obj


def finish(obj, name, parent, loc, rot, scale, mat):
    obj.name = name
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    attach(obj, parent, loc, rot, scale)


# MARK: - Animals

class Rig:
    """The moving parts of one animal and the numbers its clips need."""

    def __init__(self, name):
        self.name = name
        self.root = empty(name, None)
        self.torso = empty(name + "Torso", self.root)
        self.body = None
        self.head = None
        self.head_top = None
        self.hips = {}
        self.knees = {}
        self.ears = []
        self.tail = []
        self.eyes = {}
        self.feet = {}
        self.walk_amp = {"F": 0.3, "B": 0.34}
        self.walk_knee = {"F": 0.9, "B": 0.6}
        self.bob = 0.035
        self.tail_rest = []
        self.ear_rest = []
        self.ortho = 3.4
        self.pupil = "round"
        self.center = 0.5
        # Eyelid colour when the skin above the eye is not what the lid should be (a panda's black patch).
        self.lid = None


def leg(rig, key, hip_loc, thigh, shin, foot_mat, fur, foot):
    """A hip that swings, a knee that bends, and a foot whose bottom sits on the floor at rest."""
    hip = empty(f"{rig.name}Hip{key}", rig.torso, hip_loc)
    upper_len, upper_top, upper_bottom = thigh
    lower_len, lower_top, lower_bottom = shin
    cone(f"{rig.name}Thigh{key}", hip, (0, 0, -upper_len / 2), upper_bottom, upper_top, upper_len, fur)
    sphere(f"{rig.name}HipBall{key}", hip, (0, 0, 0), (upper_top,) * 3, fur)
    knee = empty(f"{rig.name}Knee{key}", hip, (0, 0, -upper_len))
    sphere(f"{rig.name}KneeBall{key}", knee, (0, 0, 0), (upper_bottom,) * 3, fur)
    cone(f"{rig.name}Shin{key}", knee, (0, 0, -lower_len / 2), lower_bottom, lower_top, lower_len, fur)
    foot(rig, key, knee, lower_len, foot_mat)
    rig.hips[key] = hip
    rig.knees[key] = knee


def build_pig():
    pink = material("PigSkin", (0.96, 0.36, 0.52))
    snout_mat = material("PigSnout", (0.9, 0.3, 0.45))
    hoof = material("PigHoof", (0.28, 0.17, 0.17), roughness=0.35)
    white = material("PigEye", (0.97, 0.97, 0.95), roughness=0.2)
    dark = material("PigNostril", (0.35, 0.14, 0.2))

    rig = Rig("Pig")
    rig.body = sphere("PigBody", rig.torso, (0, 0, 1.42), (1.05, 0.76, 0.72), pink)
    sphere("PigRump", rig.torso, (-0.55, 0, 1.38), (0.62, 0.68, 0.66), pink)

    def hoof_foot(rig, key, knee, length, mat):
        cone(f"PigHoof{key}", knee, (0, 0, -length - 0.05), 0.125, 0.115, 0.1, mat)

    for key in LEGS:
        front = key[0] == "F"
        y = 0.38 if key[1] == "L" else -0.38
        leg(rig, key, (0.62 if front else -0.62, y, 1.25), (0.75, 0.16, 0.12), (0.4, 0.115, 0.11),
            hoof, pink, hoof_foot)

    head = empty("PigHeadPivot", rig.torso, (0.78, 0, 1.62))
    rig.head = head
    sphere("PigHead", head, (0.3, 0, 0.1), (0.52, 0.5, 0.47), pink)
    sphere("PigCheeks", head, (0.42, 0, -0.05), (0.38, 0.46, 0.32), pink)
    bpy.ops.mesh.primitive_cylinder_add(vertices=28, radius=0.2, depth=0.2)
    snout = bpy.context.active_object
    finish(snout, "PigSnout", head, (0.8, 0, 0.0), (0, math.pi / 2, 0), (1, 1.15, 0.85), snout_mat)
    for side in (1, -1):
        sphere(f"PigNostril{side}", head, (0.9, 0.07 * side, 0.0), (0.02, 0.035, 0.055), dark)
        ear = empty(f"PigEarPivot{side}", head, (0.24, 0.27 * side, 0.5), (0.35 * side, 0.65, 0))
        sphere(f"PigEar{side}", ear, (0, 0, 0.12), (0.12, 0.17, 0.22), pink)
        rig.ears.append(ear)
        rig.eyes["near" if side < 0 else "far"] = sphere(
            f"PigEye{side}", head, (0.63, 0.23 * side, 0.25), (0.12, 0.12, 0.13), white)
    rig.head_top = empty("PigHeadTop", head, (0.3, 0, 0.75))
    rig.ear_rest = [tuple(e.rotation_euler) for e in rig.ears]

    tail = empty("PigTail", rig.torso, (-1.12, 0, 1.6), (0, -0.5, 0))
    cone("PigTailStub", tail, (-0.08, 0, 0), 0.035, 0.045, 0.16, pink, rot=(0, math.pi / 2, 0))
    torus("PigTailCurl", tail, (-0.24, 0, 0.07), 0.08, 0.028, pink, rot=(math.pi / 2, 0, 0))
    rig.tail = [tail]
    rig.tail_rest = [tuple(tail.rotation_euler)]
    rig.ortho = 3.5
    rig.pupil = "round"
    return rig


def build_cat():
    ginger = material("CatFur", (0.96, 0.58, 0.24), stripes=(0.72, 0.34, 0.1))
    plain = material("CatFurPlain", (0.96, 0.58, 0.24))
    cream = material("CatCream", (0.99, 0.93, 0.84))
    pink = material("CatPink", (0.98, 0.6, 0.66))
    iris = material("CatIris", (0.72, 0.82, 0.32), roughness=0.15)

    rig = Rig("Cat")
    rig.body = sphere("CatBody", rig.torso, (0, 0, 1.07), (0.88, 0.36, 0.37), ginger)
    sphere("CatHaunch", rig.torso, (-0.5, 0, 1.06), (0.42, 0.38, 0.42), ginger)
    sphere("CatChest", rig.torso, (0.5, 0, 1.02), (0.36, 0.32, 0.36), cream)
    sphere("CatNeck", rig.torso, (0.66, 0, 1.2), (0.26, 0.24, 0.27), plain)

    def paw(rig, key, knee, length, mat):
        sphere(f"CatPaw{key}", knee, (0.03, 0, -length - 0.02), (0.12, 0.09, 0.065), mat)

    for key in LEGS:
        front = key[0] == "F"
        y = 0.2 if key[1] == "L" else -0.2
        thigh = (0.5, 0.1, 0.075) if front else (0.5, 0.15, 0.08)
        leg(rig, key, (0.52 if front else -0.56, y, 0.95), thigh, (0.39, 0.07, 0.06), cream, ginger, paw)

    head = empty("CatHeadPivot", rig.torso, (0.84, 0, 1.34))
    rig.head = head
    sphere("CatHead", head, (0.12, 0, 0.08), (0.34, 0.32, 0.29), ginger)
    for side in (1, -1):
        sphere(f"CatMuzzle{side}", head, (0.38, 0.06 * side, -0.05), (0.1, 0.09, 0.075), cream)
        ear = empty(f"CatEarPivot{side}", head, (0.06, 0.16 * side, 0.3), (-0.28 * side, -0.12, 0))
        cone(f"CatEar{side}", ear, (0, 0, 0.1), 0.12, 0.0, 0.24, plain, scale=(0.6, 1, 1))
        cone(f"CatEarInner{side}", ear, (0.035, 0, 0.08), 0.07, 0.0, 0.16, pink, scale=(0.4, 0.8, 1))
        rig.ears.append(ear)
        rig.eyes["near" if side < 0 else "far"] = sphere(
            f"CatEye{side}", head, (0.33, 0.135 * side, 0.12), (0.1, 0.1, 0.11), iris)
    sphere("CatNose", head, (0.46, 0, 0.0), (0.03, 0.045, 0.028), pink)
    rig.head_top = empty("CatHeadTop", head, (0.1, 0, 0.62))
    rig.ear_rest = [tuple(e.rotation_euler) for e in rig.ears]

    # Six joints, each bent a little, so the tail curls and waves instead of swinging as one stick.
    parent = empty("CatTail0", rig.torso, (-0.8, 0, 1.18), (0, -0.55, 0))
    rig.tail.append(parent)
    for index in range(6):
        radius = 0.065 - index * 0.004
        cone(f"CatTailBone{index}", parent, (-0.09, 0, 0), radius, radius + 0.004, 0.2, ginger,
             rot=(0, math.pi / 2, 0))
        sphere(f"CatTailJoint{index}", parent, (-0.18, 0, 0), (radius,) * 3, ginger)
        if index < 5:
            parent = empty(f"CatTail{index + 1}", parent, (-0.18, 0, 0), (0, -0.18, 0))
            rig.tail.append(parent)
    rig.tail_rest = [tuple(t.rotation_euler) for t in rig.tail]

    rig.walk_amp = {"F": 0.36, "B": 0.4}
    rig.walk_knee = {"F": 1.1, "B": 0.85}
    rig.bob = 0.02
    rig.ortho = 3.25
    rig.center = 0.56
    rig.pupil = "slit"
    return rig


def build_panda():
    white = material("PandaWhite", (0.95, 0.95, 0.93))
    black = material("PandaBlack", (0.015, 0.015, 0.02), roughness=0.9)
    eye_mat = material("PandaEye", (0.97, 0.97, 0.95), roughness=0.2)

    rig = Rig("Panda")
    rig.body = sphere("PandaBody", rig.torso, (0, 0, 1.05), (0.95, 0.62, 0.6), white)
    sphere("PandaShoulders", rig.torso, (0.42, 0, 1.08), (0.4, 0.64, 0.62), black)
    sphere("PandaRump", rig.torso, (-0.5, 0, 1.02), (0.5, 0.6, 0.58), white)

    def paw(rig, key, knee, length, mat):
        sphere(f"PandaPaw{key}", knee, (0.04, 0, -length), (0.2, 0.17, 0.08), mat)

    for key in LEGS:
        front = key[0] == "F"
        y = 0.34 if key[1] == "L" else -0.34
        leg(rig, key, (0.55 if front else -0.55, y, 0.85), (0.45, 0.2, 0.17), (0.32, 0.16, 0.15), black, black, paw)

    head = empty("PandaHeadPivot", rig.torso, (0.85, 0, 1.32))
    rig.head = head
    sphere("PandaHead", head, (0.15, 0, 0.05), (0.45, 0.45, 0.4), white)
    sphere("PandaMuzzle", head, (0.47, 0, -0.07), (0.17, 0.19, 0.13), white)
    sphere("PandaNose", head, (0.63, 0, -0.02), (0.05, 0.075, 0.04), black)
    for side in (1, -1):
        ear = empty(f"PandaEarPivot{side}", head, (0.05, 0.3 * side, 0.4), (0.3 * side, 0, 0))
        sphere(f"PandaEar{side}", ear, (0, 0, 0), (0.12, 0.06, 0.12), black)
        rig.ears.append(ear)
        sphere(f"PandaPatch{side}", head, (0.52, 0.17 * side, 0.07), (0.07, 0.1, 0.14), black, rot=(0.4 * side, 0, 0))
        rig.eyes["near" if side < 0 else "far"] = sphere(
            f"PandaEye{side}", head, (0.575, 0.175 * side, 0.09), (0.065, 0.065, 0.07), eye_mat)
    rig.head_top = empty("PandaHeadTop", head, (0.15, 0, 0.62))
    rig.ear_rest = [tuple(e.rotation_euler) for e in rig.ears]
    tail = empty("PandaTail", rig.torso, (-0.98, 0, 1.15))
    sphere("PandaTailBall", tail, (-0.04, 0, 0), (0.1, 0.1, 0.1), white)
    rig.tail = [tail]
    rig.tail_rest = [tuple(tail.rotation_euler)]
    rig.walk_amp = {"F": 0.32, "B": 0.34}
    rig.walk_knee = {"F": 0.8, "B": 0.7}
    rig.bob = 0.03
    rig.ortho = 3.1
    rig.lid = (0.06, 0.06, 0.07)
    return rig


def build_hippo():
    skin = material("HippoSkin", (0.11, 0.065, 0.14), roughness=0.75)
    muzzle_mat = material("HippoMuzzle", (0.45, 0.18, 0.28), roughness=0.75)
    dark = material("HippoDark", (0.06, 0.03, 0.05))
    eye_mat = material("HippoEye", (0.97, 0.97, 0.95), roughness=0.2)

    rig = Rig("Hippo")
    rig.body = sphere("HippoBody", rig.torso, (0, 0, 1.0), (1.15, 0.76, 0.68), skin)
    sphere("HippoBelly", rig.torso, (0.1, 0, 0.82), (0.95, 0.66, 0.42), skin)

    def foot(rig, key, knee, length, mat):
        sphere(f"HippoFoot{key}", knee, (0.02, 0, -length), (0.21, 0.21, 0.05), mat)

    for key in LEGS:
        front = key[0] == "F"
        y = 0.42 if key[1] == "L" else -0.42
        leg(rig, key, (0.65 if front else -0.65, y, 0.62), (0.35, 0.22, 0.2), (0.22, 0.19, 0.2), dark, skin, foot)

    head = empty("HippoHeadPivot", rig.torso, (1.0, 0, 1.15))
    rig.head = head
    sphere("HippoHead", head, (0.25, 0, 0.05), (0.46, 0.46, 0.4), skin)
    sphere("HippoMuzzle", head, (0.62, 0, -0.13), (0.34, 0.43, 0.28), muzzle_mat)
    for side in (1, -1):
        sphere(f"HippoNostril{side}", head, (0.84, 0.12 * side, 0.08), (0.04, 0.05, 0.03), dark)
        ear = empty(f"HippoEarPivot{side}", head, (0.06, 0.28 * side, 0.38), (0.25 * side, -0.2, 0))
        sphere(f"HippoEar{side}", ear, (0, 0, 0.04), (0.06, 0.04, 0.09), skin)
        rig.ears.append(ear)
        sphere(f"HippoBrow{side}", head, (0.4, 0.25 * side, 0.31), (0.12, 0.12, 0.1), skin)
        rig.eyes["near" if side < 0 else "far"] = sphere(
            f"HippoEye{side}", head, (0.47, 0.26 * side, 0.36), (0.085, 0.085, 0.085), eye_mat)
    rig.head_top = empty("HippoHeadTop", head, (0.25, 0, 0.62))
    rig.ear_rest = [tuple(e.rotation_euler) for e in rig.ears]
    tail = empty("HippoTail", rig.torso, (-1.12, 0, 1.05), (0, 0.6, 0))
    cone("HippoTailStub", tail, (-0.09, 0, 0), 0.03, 0.06, 0.2, skin, rot=(0, math.pi / 2, 0))
    rig.tail = [tail]
    rig.tail_rest = [tuple(tail.rotation_euler)]
    rig.walk_amp = {"F": 0.26, "B": 0.28}
    rig.walk_knee = {"F": 0.7, "B": 0.6}
    rig.bob = 0.03
    rig.ortho = 3.6
    rig.center = 0.47
    return rig


# MARK: - Clips

def pose_leg(rig, key, hip, knee):
    rig.hips[key].rotation_euler = (0, -hip, 0)
    rig.knees[key].rotation_euler = (0, knee, 0)


def gait(t, phase, duty, amp, knee_lift):
    """Hip angle and knee bend for one leg: back along the floor while it carries weight, then lifted forward."""
    u = (t + phase) % 1
    if u < duty:
        s = u / duty
        return amp - 2 * amp * s, 0.04 * math.sin(math.pi * s)
    s = (u - duty) / (1 - duty)
    return -amp + 2 * amp * smooth(s), knee_lift * math.sin(math.pi * s)


def rest_parts(rig):
    rig.torso.location = (0, 0, 0)
    rig.torso.rotation_euler = (0, 0, 0)
    rig.body.scale = rig.body_rest_scale
    rig.head.rotation_euler = (0, 0, 0)
    for ear, rest in zip(rig.ears, rig.ear_rest):
        ear.rotation_euler = rest
    for bone, rest in zip(rig.tail, rig.tail_rest):
        bone.rotation_euler = rest


def wave_tail(rig, t, swing, lift=0.0, speed=1):
    for index, (bone, rest) in enumerate(zip(rig.tail, rig.tail_rest)):
        wave = math.sin(2 * math.pi * speed * t - index * 0.7)
        bone.rotation_euler = (rest[0], rest[1] - lift / len(rig.tail), rest[2] + swing * wave)


WALK_PHASE = {"BL": 0.0, "FL": 0.25, "BR": 0.5, "FR": 0.75}
RUN_PHASE = {"BL": 0.0, "BR": 0.08, "FL": 0.45, "FR": 0.55}
WALK_DUTY = 0.62
RUN_DUTY = 0.38


def clip_walk(rig, t):
    for key in LEGS:
        hip, knee = gait(t, WALK_PHASE[key], WALK_DUTY, rig.walk_amp[key[0]], rig.walk_knee[key[0]])
        pose_leg(rig, key, hip, knee)
    rig.torso.location = (0.015 * math.sin(4 * math.pi * t), 0.02 * math.sin(2 * math.pi * t),
                          -rig.bob * math.cos(4 * math.pi * t) + rig.bob * 0.3)
    rig.torso.rotation_euler = (0.025 * math.sin(2 * math.pi * t), 0.012 * math.sin(4 * math.pi * t),
                                0.02 * math.sin(2 * math.pi * t))
    rig.head.rotation_euler = (0, 0.05 * math.sin(4 * math.pi * t + 0.8), 0)
    for side, (ear, rest) in enumerate(zip(rig.ears, rig.ear_rest)):
        ear.rotation_euler = (rest[0], rest[1] + 0.08 * math.sin(4 * math.pi * t + side), rest[2])
    wave_tail(rig, t, 0.3)


def clip_run(rig, t):
    amp = {"F": rig.walk_amp["F"] * 1.9, "B": rig.walk_amp["B"] * 1.9}
    for key in LEGS:
        hip, knee = gait(t, RUN_PHASE[key], RUN_DUTY, amp[key[0]], rig.walk_knee[key[0]] * 1.5)
        pose_leg(rig, key, hip, knee)
    rig.torso.location = (0, 0, 0.06 + 0.07 * math.sin(2 * math.pi * t + 1.2))
    rig.torso.rotation_euler = (0, 0.09 * math.sin(2 * math.pi * t), 0)
    rig.head.rotation_euler = (0, -0.08 * math.sin(2 * math.pi * t) + 0.1, 0)
    for ear, rest in zip(rig.ears, rig.ear_rest):
        ear.rotation_euler = (rest[0], rest[1] - 0.55, rest[2])
    wave_tail(rig, t, 0.12, lift=-0.6)


def clip_idle(rig, t):
    for key in LEGS:
        pose_leg(rig, key, 0, 0)
    breath = math.sin(2 * math.pi * t)
    sx, sy, sz = rig.body_rest_scale
    rig.body.scale = (sx, sy * (1 + 0.025 * breath), sz * (1 + 0.03 * breath))
    rig.torso.location = (0, 0, 0.008 * breath)
    rig.head.rotation_euler = (0.04 * math.sin(2 * math.pi * t), 0.03 * breath, 0.06 * math.sin(2 * math.pi * t))
    for side, (ear, rest) in enumerate(zip(rig.ears, rig.ear_rest)):
        flick = 0.35 if side == 0 and 0.62 < t < 0.75 else 0.0
        ear.rotation_euler = (rest[0], rest[1] - flick, rest[2])
    wave_tail(rig, t, 0.22)


def clip_held(rig, t):
    for key in LEGS:
        offset = {"FL": 0, "FR": 0.5, "BL": 0.25, "BR": 0.75}[key]
        kick = math.sin(2 * math.pi * (t + offset))
        base = 0.18 if key[0] == "F" else -0.1
        pose_leg(rig, key, base + 0.22 * kick, 0.35 + 0.3 * max(kick, 0))
    rig.torso.location = (0, 0, 0.03 * math.sin(4 * math.pi * t))
    rig.torso.rotation_euler = (0.04 * math.sin(2 * math.pi * t), 0, 0)
    rig.head.rotation_euler = (0, -0.18, 0)
    for ear, rest in zip(rig.ears, rig.ear_rest):
        ear.rotation_euler = (rest[0], rest[1] - 0.4, rest[2])
    wave_tail(rig, t, 0.45, lift=-1.2, speed=2)


def clip_fly(rig, t):
    flutter = 0.08 * math.sin(2 * math.pi * t)
    for key in LEGS:
        reach = 0.7 if key[0] == "F" else -0.7
        pose_leg(rig, key, reach + flutter, 0.25)
    rig.torso.location = (0, 0, 0.18)
    rig.torso.rotation_euler = (0, -0.06, 0)
    rig.head.rotation_euler = (0, -0.2, 0)
    for ear, rest in zip(rig.ears, rig.ear_rest):
        ear.rotation_euler = (rest[0], rest[1] - 0.7 + 0.15 * math.sin(2 * math.pi * t), rest[2])
    wave_tail(rig, t, 0.15, lift=1.0, speed=1)


CLIP_FUNCS = {"walk": clip_walk, "run": clip_run, "idle": clip_idle, "held": clip_held, "fly": clip_fly}


# MARK: - Camera and render

def setup_render(rig):
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        pass
    scene.render.resolution_x = FRAME_PX
    scene.render.resolution_y = FRAME_PX
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.compression = 100
    scene.view_settings.view_transform = "Standard"
    if hasattr(scene.render, "use_freestyle"):
        scene.render.use_freestyle = False
    try:
        scene.view_settings.look = "Medium High Contrast"
    except TypeError:
        pass

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    background.inputs["Color"].default_value = (0.75, 0.78, 0.85, 1)
    background.inputs["Strength"].default_value = 0.55

    sun_data = bpy.data.lights.new("Key", "SUN")
    sun_data.energy = 3.6
    sun_data.angle = 0.6
    sun = bpy.data.objects.new("Key", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    fill_data = bpy.data.lights.new("Rim", "SUN")
    fill_data.energy = 1.2
    fill = bpy.data.objects.new("Rim", fill_data)
    scene.collection.objects.link(fill)
    fill.rotation_euler = (math.radians(70), 0, math.radians(160))

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = rig.ortho
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    # Three-quarter view from the animal's right side, a little from the front and above, so both eyes show.
    yaw = math.radians(28)
    pitch = math.radians(10)
    distance = 20
    direction = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    cam.location = direction * distance
    cam.rotation_euler = (math.radians(90) - pitch, 0, yaw)
    scene.camera = cam
    bpy.context.view_layer.update()
    # Put the spot between the front and back feet on the floor near the bottom of the frame.
    floor = world_to_camera_view(scene, cam, Vector((0, 0, 0)))
    cam_data.shift_x = floor.x - rig.center
    cam_data.shift_y = floor.y - 0.1
    bpy.context.view_layer.update()
    return cam


def pixel(scene, cam, point):
    view = world_to_camera_view(scene, cam, point)
    return view.x * FRAME_PX, (1 - view.y) * FRAME_PX


def eye_spot(scene, cam, eye):
    """Where an eye shows in the frame, how big, and whether the head hides it."""
    center = eye.matrix_world.translation
    x, y = pixel(scene, cam, center)
    radius_world = max(eye.matrix_world.to_scale())
    radius = radius_world * FRAME_PX / cam.data.ortho_scale
    view_dir = (cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))).normalized()
    surface = center - view_dir * radius_world * 0.9
    depsgraph = bpy.context.evaluated_depsgraph_get()
    hit, _, _, _, hit_obj, _ = scene.ray_cast(depsgraph, surface - view_dir * 15, view_dir)
    visible = hit and hit_obj is not None and hit_obj.name == eye.name
    return (round(x, 2), round(y, 2), round(radius, 2), visible)


def stride_points(rig, scene, clip, duty, phase_key, phase):
    """Body travel per gait cycle, in view points, so the feet do not slide on the floor."""
    func = CLIP_FUNCS[clip]
    foot = rig.knees[phase_key]

    def foot_x(t):
        func(rig, t)
        bpy.context.view_layer.update()
        return (foot.matrix_world @ Vector((0, 0, -0.4))).x

    start = (-phase) % 1
    end = (start + duty * 0.999) % 1
    travel = abs(foot_x(start) - foot_x(end))
    return travel / duty * VIEW_POINTS / rig.ortho


def render_sheet(rig):
    scene = bpy.context.scene
    cam = setup_render(rig)
    rig.body_rest_scale = tuple(rig.body.scale)
    out_dir = os.path.join(ROOT, "build", "mascot-frames", rig.name.lower())
    os.makedirs(out_dir, exist_ok=True)
    frames = []
    index = 0
    for clip, count in CLIPS:
        for frame in range(count):
            rest_parts(rig)
            CLIP_FUNCS[clip](rig, frame / count)
            bpy.context.view_layer.update()
            path = os.path.join(out_dir, f"{index:02d}.png")
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            near = eye_spot(scene, cam, rig.eyes["near"])
            far = eye_spot(scene, cam, rig.eyes["far"])
            top = pixel(scene, cam, rig.head_top.matrix_world.translation)
            frames.append({"near": near, "far": far, "top": (round(top[0], 2), round(top[1], 2)), "path": path})
            index += 1
    rest_parts(rig)
    walk = stride_points(rig, scene, "walk", WALK_DUTY, "BL", WALK_PHASE["BL"])
    run = stride_points(rig, scene, "run", RUN_DUTY, "BL", RUN_PHASE["BL"])
    rest_parts(rig)
    return frames, walk, run


OUTLINE = (0.24, 0.13, 0.14)
OUTLINE_RADIUS = 1.6  # pixels at 160 px, a little under one point on screen


def outlined(rgba):
    """Adds a soft dark edge around the silhouette, so the animal reads on any wallpaper."""
    alpha = rgba[..., 3]
    grown = alpha.copy()
    reach = int(math.ceil(OUTLINE_RADIUS))
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            distance = math.hypot(dx, dy)
            if distance == 0 or distance > OUTLINE_RADIUS + 0.5:
                continue
            weight = min(1.0, OUTLINE_RADIUS + 0.5 - distance)
            shifted = np.roll(np.roll(alpha, dy, axis=0), dx, axis=1) * weight
            np.maximum(grown, shifted, out=grown)
    edge = grown * 0.9
    out_alpha = alpha + edge * (1 - alpha)
    safe = np.where(out_alpha > 0, out_alpha, 1)
    result = np.empty_like(rgba)
    for channel in range(3):
        result[..., channel] = (rgba[..., channel] * alpha + OUTLINE[channel] * edge * (1 - alpha)) / safe
    result[..., 3] = out_alpha
    return result


def pack_sheet(name, frames):
    """Lays the outlined frames out in one image (row 0 at the top) and saves it as a PNG."""
    width, height = FRAME_PX * COLUMNS, FRAME_PX * ROWS
    sheet_pixels = np.zeros((height, width, 4), dtype=np.float32)
    for index, frame in enumerate(frames):
        image = bpy.data.images.load(frame["path"], check_existing=False)
        buffer = np.empty(FRAME_PX * FRAME_PX * 4, dtype=np.float32)
        image.pixels.foreach_get(buffer)
        bpy.data.images.remove(image)
        tile = outlined(buffer.reshape(FRAME_PX, FRAME_PX, 4))
        col, row = index % COLUMNS, index // COLUMNS
        # Blender images start at the bottom row.
        base_y = height - (row + 1) * FRAME_PX
        sheet_pixels[base_y:base_y + FRAME_PX, col * FRAME_PX:(col + 1) * FRAME_PX] = tile
    sheet = bpy.data.images.new(f"{name}Sheet", width, height, alpha=True)
    sheet.pixels.foreach_set(sheet_pixels.ravel())
    out = os.path.join(ROOT, "Resources", "Mascots", f"{name.lower()}.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.filepath_raw = out
    sheet.file_format = "PNG"
    sheet.save()
    bpy.data.images.remove(sheet)
    return out, lid_colour(sheet_pixels, frames)


def lid_colour(sheet_pixels, frames):
    """The lit skin colour just above the near eye in the first idle frame, used for drawn eyelids."""
    index = sum(count for _, count in CLIPS[:2])
    x, y, radius, _ = frames[index]["near"]
    col, row = index % COLUMNS, index // COLUMNS
    px = int(col * FRAME_PX + x)
    py = int(row * FRAME_PX + y - radius * 1.9)
    height = sheet_pixels.shape[0]
    patch = sheet_pixels[height - 2 - py:height + 1 - py, px - 1:px + 2, :3].reshape(-1, 3).mean(axis=0)
    return tuple(round(float(min(max(c, 0), 1)), 3) for c in patch)


# MARK: - Swift data

def swift_spot(spot):
    x, y, r, visible = spot
    return f"MascotEyeSpot(x: {x}, y: {y}, radius: {r}, isVisible: {'true' if visible else 'false'})"


def write_swift(results):
    lines = [
        "// Generated by Art/mascots/build_mascots.py. Do not edit: run the script in Blender instead.",
        "",
        "extension MascotSpriteLayout {",
    ]
    for name, (frames, walk, run, lid, pupil, floor_x) in results.items():
        lines.append(f"    static let {name.lower()} = MascotSpriteLayout(")
        lines.append(f"        lidColor: MascotColor(red: {lid[0]}, green: {lid[1]}, blue: {lid[2]}),")
        lines.append(f"        pupil: .{pupil}, walkStride: {walk:.2f}, runStride: {run:.2f}, floorX: {floor_x:.1f},")
        lines.append("        frames: [")
        for frame in frames:
            tx, ty = frame["top"]
            lines.append(f"            MascotFrameSpots(near: {swift_spot(frame['near'])},")
            lines.append(f"                             far: {swift_spot(frame['far'])},")
            lines.append(f"                             headTop: MascotPoint(x: {tx}, y: {ty})),")
        lines.append("        ])")
        lines.append("")
    lines[-1] = "}"
    path = os.path.join(ROOT, "Sources", "SoundControlCore", "MascotSpriteData.swift")
    with open(path, "w") as file:
        file.write("\n".join(lines) + "\n")
    return path


def build_all(names=("Pig", "Panda", "Hippo")):
    builders = {"Pig": build_pig, "Cat": build_cat, "Panda": build_panda, "Hippo": build_hippo}
    results = {}
    for name in names:
        clear_scene()
        rig = builders[name]()
        frames, walk, run = render_sheet(rig)
        out, lid = pack_sheet(name, frames)
        lid = rig.lid or lid
        results[name] = (frames, walk, run, lid, rig.pupil, rig.center * FRAME_PX)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "Art", "mascots", f"{name.lower()}.blend"))
    return write_swift(results), results


if __name__ == "__main__":
    build_all()
