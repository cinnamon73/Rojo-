"""
Builds the real R15 rig in Blender from a Studio rig dump, animates a
two-handed weapon swing by moving the WEAPON and letting IK solve the arms,
then exports Roblox Pose CFrames.

Coordinates: we stay in Roblox space (Y-up) inside Blender. Nothing here
cares which way gravity points, and not converting removes a whole class of
sign bugs.

Frame math (the part that must be exact):
    Roblox:  child_part = parent_part * A0 * T * inv(A1)
    Define a bone frame per part:  F_P = part * A1_P   (the joint pivot)
    Then:    F_child = F_parent * (inv(A1_parent) * A0_child) * T_child
So a bone whose REST offset from its parent is inv(A1_parent)*A0_child has a
local pose delta that IS the Roblox Pose CFrame. Blender bones carry their own
axis convention, so we store C = inv(R_rox) * R_blender per bone and convert:
    T = C * matrix_basis * inv(C)

Run:  blender --background --python blender_rig.py -- [--diag]
"""
import bpy, json, math, os, sys
from mathutils import Matrix, Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, 'rig_dump.json')
OUT_POSES = os.path.join(HERE, 'swing_poses.json')
RENDER_DIR = os.path.join(HERE, 'render')

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
DIAG = '--diag' in argv

FPS = 30
DUR = 1.60

# --------------------------------------------------------------------------
# rig dump -> matrices
# --------------------------------------------------------------------------

def cf(c):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    return Matrix(((r00, r01, r02, x),
                   (r10, r11, r12, y),
                   (r20, r21, r22, z),
                   (0, 0, 0, 1)))


def comps(m):
    t = m.translation
    return [t.x, t.y, t.z,
            m[0][0], m[0][1], m[0][2],
            m[1][0], m[1][1], m[1][2],
            m[2][0], m[2][1], m[2][2]]


data = json.load(open(DUMP))
JOINTS = {j['Child']: j for j in data['Joints']}
PARTS = data['Parts']
ROOT = 'HumanoidRootPart'

# part -> its parent part
PARENT = {j['Child']: j['Parent'] for j in data['Joints']}

# The bone we extend toward, so limb bones point along the limb and IK behaves.
PRIMARY = {
    'HumanoidRootPart': 'LowerTorso', 'LowerTorso': 'UpperTorso', 'UpperTorso': 'Head',
    'RightUpperArm': 'RightLowerArm', 'RightLowerArm': 'RightHand',
    'LeftUpperArm': 'LeftLowerArm', 'LeftLowerArm': 'LeftHand',
    'RightUpperLeg': 'RightLowerLeg', 'RightLowerLeg': 'RightFoot',
    'LeftUpperLeg': 'LeftLowerLeg', 'LeftLowerLeg': 'LeftFoot',
}

# rest world transform of each part, and of each bone frame F_P
rest_part = {ROOT: Matrix.Identity(4)}
order = [ROOT]
changed = True
while changed:
    changed = False
    for child, j in JOINTS.items():
        if child in rest_part or j['Parent'] not in rest_part:
            continue
        rest_part[child] = rest_part[j['Parent']] @ cf(j['A0']) @ cf(j['A1']).inverted()
        order.append(child)
        changed = True

A1 = {ROOT: Matrix.Identity(4)}
for child, j in JOINTS.items():
    A1[child] = cf(j['A1'])

rest_frame = {p: rest_part[p] @ A1[p] for p in rest_part}

# --------------------------------------------------------------------------
# scene
# --------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS
scene.frame_start = 0
scene.frame_end = int(DUR * FPS)

arm_data = bpy.data.armatures.new('R15')
arm_obj = bpy.data.objects.new('R15', arm_data)
scene.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode='EDIT')

for p in order:
    eb = arm_data.edit_bones.new(p)
    F = rest_frame[p]
    head = F.translation.copy()
    kid = PRIMARY.get(p)
    if kid and kid in rest_frame:
        tail = rest_frame[kid].translation.copy()
        if (tail - head).length < 1e-4:
            tail = head + F.to_3x3() @ Vector((0, 0.3, 0))
    else:
        tail = head + F.to_3x3() @ Vector((0, 0.3, 0))
    eb.head, eb.tail = head, tail
    if p in PARENT:
        eb.parent = arm_data.edit_bones[PARENT[p]]
    eb.use_connect = False

bpy.ops.object.mode_set(mode='OBJECT')

# C = inv(R_rox) * R_blender, per bone
CONV = {}
for p in order:
    R_rox = rest_frame[p].to_3x3()
    R_bl = arm_data.bones[p].matrix_local.to_3x3()
    CONV[p] = R_rox.inverted() @ R_bl

# --------------------------------------------------------------------------
# weapon control + IK targets
# --------------------------------------------------------------------------
grip = data['Grip']
GRIP_REL = cf(grip['C0']) @ cf(grip['C1']).inverted()      # handle relative to RightHand part
rest_weapon = rest_part['RightHand'] @ GRIP_REL
K_RIGHT = GRIP_REL.inverted() @ A1['RightHand']       # right wrist frame, in weapon space

wctl = bpy.data.objects.new('WeaponCtl', None)
wctl.empty_display_size = 0.4
scene.collection.objects.link(wctl)
wctl.matrix_world = rest_weapon

# Right hand target: the bone frame the hand must land in for the weld to put
# the weapon exactly where WeaponCtl is.
#
# The trailing CONV is essential. A bone's WORLD matrix is F_P * C, not F_P,
# so a Copy Rotation handed the bare joint frame twists the wrist by whatever
# C happens to be. Position is unaffected (C carries no translation).
rt = bpy.data.objects.new('RightGripTarget', None)
scene.collection.objects.link(rt)
rt.parent = wctl
rt.matrix_parent_inverse = Matrix.Identity(4)
rt.matrix_basis = GRIP_REL.inverted() @ A1['RightHand'] @ CONV['RightHand'].to_4x4()

# Left hand grips the haft this far up from the grip point (studs).
#
# This rig REACHES ONLY 1.225 STUDS from the shoulder, and the shoulders sit
# 1.5 apart. A two-handed grip therefore has to live near the body's centre
# line: anything held out at arm's length is unreachable, and Blender's IK
# just gives up quietly, which reads in game as the left arm ignoring the
# weapon completely. Every key below is range-checked before the swing runs.
# Measured from the RIGHT WRIST up the haft, not from the weapon's origin.
# The grip weld puts the weapon's origin well above the hand, so spacing the
# off-hand from the origin quietly asked it to reach ~1.6 studs - past the
# 1.225 limit - and IK abandoned the haft every frame.
HAND_SPACING = 0.85
LEFT_OFF = K_RIGHT.translation + Vector((0, HAND_SPACING, 0))
lt = bpy.data.objects.new('LeftGripTarget', None)
scene.collection.objects.link(lt)
lt.parent = wctl
lt.matrix_parent_inverse = Matrix.Identity(4)
lt.matrix_basis = (Matrix.Translation(LEFT_OFF)
                   @ Matrix.Rotation(math.radians(180), 4, 'Y')
                   @ CONV['LeftHand'].to_4x4())

pb = arm_obj.pose.bones


def ik(bone, target, chain):
    c = pb[bone].constraints.new('IK')
    c.target = target
    c.chain_count = chain
    c.use_rotation = False


def copy_rot(bone, target):
    c = pb[bone].constraints.new('COPY_ROTATION')
    c.target = target


ik('RightLowerArm', rt, 2)
copy_rot('RightHand', rt)
ik('LeftLowerArm', lt, 2)
copy_rot('LeftHand', lt)

# --------------------------------------------------------------------------
# animation
# --------------------------------------------------------------------------
D = math.radians


def haft(t, wrist, direction, roll=0.0):
    """Weapon pose stated as: RIGHT WRIST position, haft direction, twist.

    Authoring by wrist rather than by the weapon's own origin is what makes
    this tunable: the wrist is the thing that has to stay inside the arm's
    1.225 stud reach, so the number being typed is the number being
    constrained. The weapon origin is solved backwards from it.
    """
    Y = Vector(direction).normalized()
    ref = Vector((0, 0, -1)) if abs(Y.z) < 0.9 else Vector((1, 0, 0))
    X = Y.cross(ref).normalized()
    Z = X.cross(Y)
    R = Matrix(((X.x, Y.x, Z.x, 0),
                (X.y, Y.y, Z.y, 0),
                (X.z, Y.z, Z.z, 0),
                (0, 0, 0, 1))) @ Matrix.Rotation(D(roll), 4, 'Y')
    origin = Vector(wrist) - R.to_3x3() @ K_RIGHT.translation
    return (t, Matrix.Translation(origin) @ R)


# Character faces -Z, up is +Y, right is +X. Haft runs along the weapon's +Y,
# axe head 3.6 studs along it, so the head is a long lever: small changes in
# direction move it a long way.
WEAPON_KEYS = [
    # ============ PART 1: HORIZONTAL CLEAVE ============
    # ready: two-handed at the right hip, blade cocked back and right
    # Loaded like a bat: hands at the right shoulder, blade up and BACK over
    # the head. Pointing the haft away to the right instead puts the off-hand
    # 2.2 studs from the left shoulder - unreachable, so the grip breaks.
    haft(0.00, (0.55, 0.70, -0.10), (-0.20, 0.78, 0.59)),
    # wind: coil further right, weapon drawn behind the shoulder
    haft(0.18, (0.62, 0.75, 0.15), (-0.25, 0.80, 0.55)),
    # CLEAVE: flat sweep across the body at chest height, head whipping left
    haft(0.34, (0.10, 0.75, -0.75), (-0.92, 0.10, -0.38)),
    # follow-through: momentum carries the blade out to the left
    haft(0.48, (-0.35, 0.70, -0.55), (-0.80, -0.05, 0.60)),
    haft(0.62, (-0.30, 0.60, -0.35), (-0.72, 0.20, 0.66)),

    # ============ PART 2: OVERHEAD CRASH ============
    # lift: haul the weapon up and back over the head
    haft(0.86, (0.05, 1.10, 0.20), (-0.15, 0.70, 0.70)),
    # apex hold - the beat that sells the weight
    haft(1.02, (0.05, 1.30, 0.35), (-0.10, 0.66, 0.74)),
    # SLAM: straight down the centre line
    haft(1.16, (0.05, 0.95, -0.55), (-0.05, -0.60, -0.80)),
    # settle, blade buried
    haft(1.30, (0.02, 0.85, -0.60), (-0.05, -0.66, -0.75)),
    # recover to ready
    haft(1.60, (0.55, 0.70, -0.10), (-0.20, 0.78, 0.59)),
]

# Measured from the rig, never hardcoded: swapping the source avatar changes
# this by 70% and every pose budget with it.
REACH = ((rest_frame['RightUpperArm'].translation - rest_frame['RightLowerArm'].translation).length
         + (rest_frame['RightLowerArm'].translation - rest_frame['RightHand'].translation).length)
print('measured arm reach = %.3f studs' % REACH)
_rs = rest_frame['RightUpperArm'].translation
_ls = rest_frame['LeftUpperArm'].translation
print('--- reach preflight (rest shoulders; torso lean buys a little more) ---')
for _t, _M in WEAPON_KEYS:
    _r = (_M @ GRIP_REL.inverted() @ A1['RightHand']).translation
    _l = (_M @ Matrix.Translation(LEFT_OFF)).translation
    _dr, _dl = (_r - _rs).length, (_l - _ls).length
    _head = (_M @ Matrix.Translation(Vector((0, 3.6, 0)))).translation
    print('  t=%.2f  right=%.2f%s  left=%.2f%s   axehead=(%.1f,%.1f,%.1f)'
          % (_t, _dr, '' if _dr <= REACH else ' OVER', _dl,
             '' if _dl <= REACH else ' OVER', _head.x, _head.y, _head.z))

# Torso and legs stay FK: these carry the weight of the swing.
BODY_KEYS = {
    # Yaw sign: positive twist carries the LEFT shoulder back, negative carries
    # the RIGHT shoulder back. The cleave is driven by unwinding from -yaw
    # (coiled right) through to +yaw, so the hips lead and the arms follow.
    'LowerTorso': [
        (0.00, (0, -10, 0), (0, -0.10, 0)),
        (0.18, (4, -22, 0), (0, -0.30, 0)),
        (0.34, (2, 20, 0), (0, -0.22, 0)),
        (0.48, (0, 30, 0), (0, -0.16, 0)),
        (0.62, (0, 22, 0), (0, -0.12, 0)),
        (0.86, (-6, 10, 0), (0, -0.10, 0)),
        (1.02, (-10, 6, 0), (0, -0.08, 0)),
        (1.16, (28, -6, 0), (0, -0.45, 0)),
        (1.30, (24, -8, 0), (0, -0.38, 0)),
        (1.60, (0, -10, 0), (0, -0.10, 0)),
    ],
    'UpperTorso': [
        (0.00, (4, -16, 0), None),
        (0.18, (8, -34, 4), None),
        (0.34, (6, 30, -6), None),
        (0.48, (2, 44, -8), None),
        (0.62, (2, 34, -6), None),
        (0.86, (-14, 16, -4), None),
        (1.02, (-20, 10, -3), None),
        (1.16, (40, -10, 3), None),
        (1.30, (34, -12, 2), None),
        (1.60, (4, -16, 0), None),
    ],
    'Head': [
        (0.00, (0, 12, 0), None),
        (0.34, (0, -18, 0), None),
        (0.62, (0, -22, 0), None),
        (1.02, (14, -6, 0), None),
        (1.16, (-16, 4, 0), None),
        (1.60, (0, 12, 0), None),
    ],
    'RightUpperLeg': [
        (0.00, (-8, 0, 0), None), (0.18, (-20, 0, 0), None), (0.34, (-6, 0, 0), None),
        (0.62, (-4, 0, 0), None), (1.02, (-12, 0, 0), None), (1.16, (-38, 0, 0), None),
        (1.30, (-32, 0, 0), None), (1.60, (-8, 0, 0), None),
    ],
    'RightLowerLeg': [
        (0.00, (10, 0, 0), None), (0.18, (26, 0, 0), None), (0.34, (8, 0, 0), None),
        (0.62, (6, 0, 0), None), (1.02, (16, 0, 0), None), (1.16, (46, 0, 0), None),
        (1.30, (40, 0, 0), None), (1.60, (10, 0, 0), None),
    ],
    'LeftUpperLeg': [
        (0.00, (-4, 0, 0), None), (0.18, (-8, 0, 0), None), (0.34, (-18, 0, 0), None),
        (0.62, (-14, 0, 0), None), (1.02, (-6, 0, 0), None), (1.16, (-28, 0, 0), None),
        (1.30, (-24, 0, 0), None), (1.60, (-4, 0, 0), None),
    ],
    'LeftLowerLeg': [
        (0.00, (6, 0, 0), None), (0.18, (12, 0, 0), None), (0.34, (24, 0, 0), None),
        (0.62, (18, 0, 0), None), (1.02, (10, 0, 0), None), (1.16, (36, 0, 0), None),
        (1.30, (32, 0, 0), None), (1.60, (6, 0, 0), None),
    ],
}

# The combo is authored as ONE continuous timeline so the hand-off from cleave
# to overhead is a real motion rather than two clips jammed together, then cut
# into the two clips the game plays per combo step.
CLIPS = {'Cleave': (0.00, 0.66), 'Crash': (0.70, 1.60)}

def key_weapon():
    # Quaternion, not euler: the windup-to-slam key pair is close to a 180
    # degree flip, and euler channels interpolate that through whatever
    # gimbal path they like instead of the short arc.
    wctl.rotation_mode = 'QUATERNION'
    for t, M in WEAPON_KEYS:
        f = round(t * FPS)
        wctl.matrix_basis = M
        wctl.keyframe_insert('location', frame=f)
        wctl.keyframe_insert('rotation_quaternion', frame=f)


def key_body():
    for bone, keys in BODY_KEYS.items():
        p = pb[bone]
        p.rotation_mode = 'QUATERNION'
        C = CONV[bone]
        for t, rot, loc in keys:
            f = round(t * FPS)
            T = Euler((D(rot[0]), D(rot[1]), D(rot[2])), 'XYZ').to_matrix().to_4x4()
            if loc:
                T = Matrix.Translation(Vector(loc)) @ T
            basis = (C.inverted().to_4x4() @ T @ C.to_4x4())
            p.matrix_basis = basis
            p.keyframe_insert('rotation_quaternion', frame=f)
            p.keyframe_insert('location', frame=f)


key_weapon()
key_body()

# --------------------------------------------------------------------------
# preview meshes (so renders are readable)
#
# Bone matrices are in BLENDER convention (Y runs along the bone). Anything
# placed in the world must be converted back through C first, or every part
# comes out rotated - which is exactly what the first render looked like.
# --------------------------------------------------------------------------
def box(name, size, color=(0.7, 0.7, 0.72, 1)):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object
    o.name = name
    o.scale = Vector(size)
    o.color = color
    return o


RIGHT_ARM = (0.20, 0.45, 0.95, 1)     # blue  = weapon hand
LEFT_ARM = (0.20, 0.80, 0.35, 1)      # green = off hand
BODY = (0.62, 0.63, 0.68, 1)
LEG = (0.45, 0.46, 0.52, 1)
WEAP = (0.80, 0.45, 0.15, 1)

# Real part boxes, not bone sticks: a stick figure gave no way to tell which
# arm was which or which way the body faced, which is most of what needs
# judging here.
def tone(p):
    if p.startswith('Right') and 'Leg' not in p and 'Foot' not in p:
        return RIGHT_ARM
    if p.startswith('Left') and 'Leg' not in p and 'Foot' not in p:
        return LEFT_ARM
    if 'Leg' in p or 'Foot' in p:
        return LEG
    return BODY


# True part sizes. The slimming that made the bear avatar readable makes a
# standard R15 look like it is falling apart, because the gaps between shrunk
# boxes read as detached limbs.
SLIM = {p: 1.0 for p in order}
part_objs = {p: box('m_' + p, [d * SLIM[p] for d in PARTS[p]['Size']], tone(p)) for p in order}

WEAPON = data['Weapon']
weapon_objs = [(box('w_' + w['Name'], w['Size'], WEAP), cf(w['RelHandle'])) for w in WEAPON]

GROUND_Y = rest_part['RightFoot'].translation.y - PARTS['RightFoot']['Size'][1] / 2
ground = box('ground', (8, 0.08, 8), (0.80, 0.81, 0.83, 1))
ground.location = Vector((0, GROUND_Y, 0))

cam_data = bpy.data.cameras.new('cam')
cam = bpy.data.objects.new('cam', cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
# Orthographic: predictable framing that cannot creep as the weapon swings
# through a 7 stud arc, and no perspective foreshortening to misread.
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 9.5


def look_at(loc, target, up=Vector((0, 1, 0))):
    """Camera matrix with an explicit up axis.

    mathutils' to_track_quat resolves "up" against Blender's world +Z. This
    scene is deliberately Y-up (Roblox space), so that helper rolls the camera
    90 degrees - which is why the floor kept rendering as a wall behind the
    character.
    """
    f = (Vector(target) - Vector(loc)).normalized()
    r = f.cross(up).normalized()
    u = r.cross(f)
    return Matrix(((r.x, u.x, -f.x, loc[0]),
                   (r.y, u.y, -f.y, loc[1]),
                   (r.z, u.z, -f.z, loc[2]),
                   (0, 0, 0, 1)))


cam.matrix_world = look_at(Vector((6.5, 2.2, -6.5)), Vector((0, -0.35, -0.2)))

scene.render.engine = 'BLENDER_WORKBENCH'
shading = scene.display.shading
shading.light = 'STUDIO'
shading.color_type = 'OBJECT'
shading.show_shadows = False
scene.render.resolution_x = 520
scene.render.resolution_y = 520
scene.render.film_transparent = False

# --------------------------------------------------------------------------
# evaluate, export, render
# --------------------------------------------------------------------------
dg = bpy.context.evaluated_depsgraph_get()
os.makedirs(RENDER_DIR, exist_ok=True)

frames = list(range(scene.frame_start, scene.frame_end + 1))
out = {'Fps': FPS, 'Duration': DUR, 'Parent': PARENT, 'Clips': CLIPS, 'Frames': []}
checks = []

RENDER_AT = [0.00, 0.18, 0.28, 0.34, 0.48, 0.62, 0.86, 1.02, 1.10, 1.16, 1.30] if not DIAG else [0.0]

for f in frames:
    scene.frame_set(f)
    dg.update()

    pose_world = {}
    basis = {}
    for p in order:
        b = pb[p]
        pose_world[p] = b.matrix.copy()
    for p in order:
        parent = PARENT.get(p)
        rest_local = (arm_data.bones[p].matrix_local if parent is None else
                      arm_data.bones[parent].matrix_local.inverted() @ arm_data.bones[p].matrix_local)
        parent_pose = pose_world[parent] if parent else Matrix.Identity(4)
        basis[p] = rest_local.inverted() @ parent_pose.inverted() @ pose_world[p]

    rec = {'T': round(f / FPS, 4), 'Joints': {}}
    T_by_part = {}
    for p in order:
        if p == ROOT:
            continue
        C = CONV[p].to_4x4()
        T = C @ basis[p] @ C.inverted()
        T_by_part[p] = T
        rec['Joints'][p] = [round(v, 5) for v in comps(T)]
    out['Frames'].append(rec)

    # --- verification -----------------------------------------------------
    # 1. Replay the exported poses through Roblox's OWN formula
    #    (child = parent * A0 * T * inv(A1)) and confirm the rig lands where
    #    Blender put it. This validates the whole frame-math chain offline,
    #    before anything is uploaded.
    replay = {ROOT: Matrix.Identity(4)}
    for p in order:
        if p == ROOT:
            continue
        j = JOINTS[p]
        replay[p] = replay[j['Parent']] @ cf(j['A0']) @ T_by_part[p] @ cf(j['A1']).inverted()

    F = {p: pose_world[p] @ CONV[p].inverted().to_4x4() for p in order}
    part_world = {p: F[p] @ A1[p].inverted() for p in order}

    err = max((replay[p].translation - part_world[p].translation).length for p in order)
    # 2. Did IK actually keep both hands on the weapon?
    weapon_from_hand = part_world['RightHand'] @ GRIP_REL
    grip_err = (weapon_from_hand.translation - wctl.matrix_world.translation).length
    haft_pt = wctl.matrix_world @ LEFT_OFF
    left_err = (part_world['LeftHand'].translation - haft_pt).length
    checks.append((round(f / FPS, 3), err, grip_err, left_err))

    t = round(f / FPS, 4)
    if any(abs(t - r) < 0.6 / FPS for r in RENDER_AT):
        for p, o in part_objs.items():
            o.matrix_world = part_world[p]
            o.scale = Vector([d * SLIM[p] for d in PARTS[p]['Size']])
        wm = wctl.matrix_world.copy()
        sizes = {'w_' + w['Name']: w['Size'] for w in WEAPON}
        for o, rel in weapon_objs:
            o.matrix_world = wm @ rel
            o.scale = Vector(sizes[o.name])
        ground.matrix_world = Matrix.Translation(Vector((0, GROUND_Y, 0)))
        ground.scale = Vector((8, 0.08, 8))
        scene.render.filepath = os.path.join(RENDER_DIR, 'f_%03d.png' % round(t * 100))
        bpy.ops.render.render(write_still=True)

json.dump(out, open(OUT_POSES, 'w'))

# ---------------------------------------------------------------------------
# Hand off a scrubbable .blend.
#
# Child Of constraints rather than baked mesh keyframes: the meshes then track
# whatever the rig does, so editing the swing in Blender updates the preview
# live instead of showing a stale bake.
# ---------------------------------------------------------------------------
for p, o in part_objs.items():
    o.animation_data_clear()
    c = o.constraints.new('CHILD_OF')
    c.target = arm_obj
    c.subtarget = p
    c.inverse_matrix = arm_data.bones[p].matrix_local.inverted()
    o.matrix_basis = rest_part[p] @ Matrix.Diagonal(
        Vector([d * SLIM[p] for d in PARTS[p]['Size']]).to_4d())

for o, rel in weapon_objs:
    o.parent = wctl
    o.matrix_parent_inverse = Matrix.Identity(4)
    sz = next(w['Size'] for w in WEAPON if 'w_' + w['Name'] == o.name)
    o.matrix_basis = rel @ Matrix.Diagonal(Vector(sz).to_4d())

ground.matrix_basis = (Matrix.Translation(Vector((0, GROUND_Y, 0)))
                       @ Matrix.Diagonal(Vector((8, 0.08, 8)).to_4d()))

# Present the scene Z-up so Blender's navigation behaves normally for a human.
# Everything is parented under one rotated empty, which leaves pose_bone.matrix
# (read in ARMATURE space) untouched - so this is purely cosmetic and the
# exported poses are bit-identical either way.
root = bpy.data.objects.new('RIG_ROOT', None)
root.empty_display_size = 0.6
scene.collection.objects.link(root)
root.rotation_euler = (math.radians(90), 0, 0)
for obj in (arm_obj, wctl, ground, cam):
    obj.parent = root
    obj.matrix_parent_inverse = Matrix.Identity(4)

scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'berserker.blend'))
print('SAVED berserker.blend')

# A Pose CFrame is meant to be a ROTATION at the joint. Any translation that
# leaks in (from IK, or a constraint introducing scale) physically separates
# the limb from its socket in game - which reads as a "malformed" character.
drift = {}
for rec in out['Frames']:
    for name, c in rec['Joints'].items():
        d = (c[0] ** 2 + c[1] ** 2 + c[2] ** 2) ** 0.5
        drift[name] = max(drift.get(name, 0.0), d)
print('--- joint translation leak (studs) ---')
for name, d in sorted(drift.items(), key=lambda kv: -kv[1])[:8]:
    print('   %-16s %.4f%s' % (name, d, '   <-- pulls the rig apart' if d > 0.05 else ''))

worst_math = max(c[1] for c in checks)
worst_grip = max(c[2] for c in checks)
worst_left = max(c[3] for c in checks)

print('EXPORT_OK frames=%d joints=%d' % (len(out['Frames']), len(out['Frames'][0]['Joints'])))
print('CHECK roblox-replay max error   = %.6f studs  %s'
      % (worst_math, 'OK' if worst_math < 1e-4 else 'BAD - frame math is wrong'))
print('CHECK right hand grip max error = %.4f studs  %s'
      % (worst_grip, 'OK' if worst_grip < 0.02 else 'IK could not reach'))
print('CHECK left hand on haft max err = %.4f studs  %s'
      % (worst_left, 'OK' if worst_left < 0.35 else 'left hand slipping off haft'))
for t, e, g, l in checks:
    if l > 0.25 or g > 0.05:
        print('   t=%.2f  grip=%.3f  left=%.3f' % (t, g, l))
print('GROUND y=%.2f   head y=%.2f' % (GROUND_Y, rest_part['Head'].translation.y))
print('REST weapon handle pos=%s' % [round(v, 2) for v in rest_weapon.translation])
