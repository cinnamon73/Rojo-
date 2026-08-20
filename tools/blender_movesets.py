"""
Authors a UNIQUE moveset per weapon against the real R15 rig, in Blender.

This supersedes blender_rig.py (which only knew the greataxe). The frame maths
is identical and still self-verified every frame; what is new is that swings
are described declaratively, so adding a class's moveset is a table entry
rather than a new script.

HOW A SWING IS DESCRIBED
    swing(name, beats=[(t, wrist, haft_direction), ...], twist=[(t, yaw), ...])
The wrist position is what must stay inside the arm's reach, and the haft
direction is where the blade points - so both things that actually matter are
stated directly and range-checked before anything renders.

WHAT CARRIES OVER FROM THE GREATAXE WORK
  * Roblox: child = parent * A0 * T * inv(A1); a bone whose rest offset is
    inv(A1_parent)*A0_child has a local pose delta that IS the Pose CFrame.
  * Blender bones have their own axis convention, so C = inv(R_rox)*R_blender
    is stored per bone and the export converts with T = C * basis * inv(C).
  * Every frame is replayed through Roblox's own formula and compared; if that
    check ever stops reading ~0 the export is wrong and must not be uploaded.

ONE-HANDED vs TWO-HANDED
    Two-handed weapons IK the off-hand onto the haft. One-handed weapons do
    NOT - the left arm gets FK counterbalance poses instead, because pinning a
    free hand to a sword looks worse than letting it swing.

USAGE
    blender --background --python tools/blender_movesets.py
    blender --background --python tools/blender_movesets.py -- --only Sword
"""
import bpy, json, math, os, sys
from mathutils import Matrix, Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, "rig_standard_r15.json")
OUT_POSES = os.path.join(HERE, "movesets.json")
RENDER_DIR = os.path.join(HERE, "moveset_previews")

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = argv[argv.index("--only") + 1] if "--only" in argv else None

FPS = 30
D = math.radians


def cf(c):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    return Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))


def comps(m):
    t = m.translation
    return [t.x, t.y, t.z, m[0][0], m[0][1], m[0][2],
            m[1][0], m[1][1], m[1][2], m[2][0], m[2][1], m[2][2]]


def angles(rx, ry, rz):
    return Euler((D(rx), D(ry), D(rz)), "XYZ").to_matrix().to_4x4()


# ---------------------------------------------------------------------------
# weapons: grip offsets mirror WeaponModels.GetGripOffset exactly
# ---------------------------------------------------------------------------

WEAPONS = {
    "Sword":        dict(grip=Matrix.Translation((0, -0.7, 0)), two=False, reachMul=1.0),
    "Dagger":       dict(grip=Matrix.Translation((0, -0.7, 0)), two=False, reachMul=0.92),
    "PaladinBlade": dict(grip=Matrix.Translation((0, -0.7, 0)), two=False, reachMul=1.0),
    "RoyalBlade":   dict(grip=Matrix.Translation((0, -0.7, 0)), two=False, reachMul=1.0),
    "Greatsword":   dict(grip=Matrix.Translation((0, -0.9, 0)) @ angles(-8, 0, 0), two=True,
                         spacing=0.9),
    "Greataxe":     dict(grip=Matrix.Translation((0, -0.9, 0)) @ angles(-8, 0, 0), two=True,
                         spacing=0.85),
    "NecroStaff":   dict(grip=Matrix.Translation((0, -0.7, 0)), two=True, spacing=0.8),
    "Bow":          dict(grip=Matrix.Translation((0, -0.6, 0)) @ angles(90, 90, 0), two=False),
    "Musket":       dict(grip=Matrix.Translation((0, -0.5, 0.15)) @ angles(-64, 0, 0), two=True,
                         spacing=0.75),
}


def swing(name, beats, twist=None, lean=None, crouch=None, legs=True):
    """One clip. `beats` are (time, wrist_xyz, haft_direction)."""
    return dict(Name=name, Beats=beats, Twist=twist or [], Lean=lean or [],
                Crouch=crouch or [], Legs=legs)


# ---------------------------------------------------------------------------
# THE MOVESETS - one per class, deliberately different silhouettes
# ---------------------------------------------------------------------------
# Character faces -Z, up is +Y, right is +X. Shoulders sit at (+-0.97, 0.85, 0)
# with 1.73 studs of reach, so every wrist below stays well inside that.

MOVESETS = {
    # Swordsman: crisp and economical. Diagonal down, rising backhand, thrust.
    "Sword": [
        swing("SwordSlash", [
            (0.00, (0.72, 1.02, -0.30), (0.30, 0.80, 0.52)),
            (0.12, (0.86, 1.24, 0.10), (0.42, 0.76, 0.50)),
            (0.26, (0.16, 0.62, -0.92), (-0.62, -0.42, -0.66)),
            (0.42, (-0.36, 0.40, -0.72), (-0.78, -0.30, -0.55)),
            (0.62, (0.72, 1.02, -0.30), (0.30, 0.80, 0.52)),
        ], twist=[(0.00, -12), (0.12, -26), (0.26, 22), (0.42, 32), (0.62, -12)]),
        swing("SwordBackhand", [
            (0.00, (-0.34, 0.44, -0.70), (-0.76, -0.30, -0.57)),
            (0.12, (-0.48, 0.32, -0.52), (-0.82, -0.34, -0.46)),
            (0.26, (0.44, 1.16, -0.86), (0.46, 0.72, -0.52)),
            (0.42, (0.70, 1.28, -0.52), (0.60, 0.66, -0.45)),
            (0.62, (0.72, 1.02, -0.30), (0.30, 0.80, 0.52)),
        ], twist=[(0.00, 30), (0.12, 36), (0.26, -20), (0.42, -30), (0.62, -12)]),
        swing("SwordThrust", [
            (0.00, (0.78, 0.98, -0.10), (0.10, 0.30, -0.95)),
            (0.14, (0.92, 0.96, 0.34), (0.08, 0.24, -0.97)),
            (0.26, (0.36, 0.94, -1.12), (0.00, 0.05, -1.00)),
            (0.40, (0.44, 0.94, -0.96), (0.00, 0.08, -1.00)),
            (0.62, (0.72, 1.02, -0.30), (0.30, 0.80, 0.52)),
        ], twist=[(0.00, -18), (0.14, -30), (0.26, 16), (0.40, 18), (0.62, -12)],
           lean=[(0.26, 14)]),
    ],

    # Assassin: short, fast, low. Inside stab, cross slash, spinning backhand.
    "Dagger": [
        swing("DaggerStab", [
            (0.00, (0.62, 0.86, -0.26), (0.20, 0.40, -0.89)),
            (0.08, (0.74, 0.78, 0.14), (0.24, 0.32, -0.92)),
            (0.18, (0.30, 0.88, -0.98), (0.02, 0.10, -0.99)),
            (0.30, (0.40, 0.86, -0.80), (0.04, 0.14, -0.99)),
            (0.46, (0.62, 0.86, -0.26), (0.20, 0.40, -0.89)),
        ], twist=[(0.00, -14), (0.08, -26), (0.18, 18), (0.30, 20), (0.46, -14)]),
        swing("DaggerCross", [
            (0.00, (0.66, 1.06, -0.28), (0.44, 0.66, -0.60)),
            (0.08, (0.80, 1.18, 0.06), (0.52, 0.62, -0.58)),
            (0.18, (-0.18, 0.66, -0.86), (-0.70, -0.36, -0.62)),
            (0.30, (-0.42, 0.56, -0.68), (-0.80, -0.28, -0.53)),
            (0.46, (0.62, 0.86, -0.26), (0.20, 0.40, -0.89)),
        ], twist=[(0.00, -16), (0.08, -28), (0.18, 26), (0.30, 34), (0.46, -14)]),
        swing("DaggerSpin", [
            (0.00, (-0.40, 0.60, -0.62), (-0.78, -0.24, -0.58)),
            (0.10, (-0.52, 0.70, -0.20), (-0.86, 0.10, -0.50)),
            (0.22, (0.52, 1.10, -0.84), (0.56, 0.44, -0.70)),
            (0.34, (0.74, 1.14, -0.44), (0.66, 0.42, -0.62)),
            (0.52, (0.62, 0.86, -0.26), (0.20, 0.40, -0.89)),
        ], twist=[(0.00, 34), (0.10, 44), (0.22, -30), (0.34, -38), (0.52, -14)]),
    ],

    # Paladin: grounded and heavy. Overhead chop, then a wide braced sweep.
    "PaladinBlade": [
        swing("PaladinChop", [
            (0.00, (0.66, 1.14, -0.16), (0.18, 0.86, 0.48)),
            (0.18, (0.50, 1.44, 0.28), (0.04, 0.80, 0.60)),
            (0.34, (0.22, 0.80, -0.92), (-0.06, -0.62, -0.78)),
            (0.50, (0.20, 0.70, -0.86), (-0.06, -0.70, -0.71)),
            (0.76, (0.66, 1.14, -0.16), (0.18, 0.86, 0.48)),
        ], twist=[(0.00, -8), (0.18, 12), (0.34, -10), (0.50, -12), (0.76, -8)],
           lean=[(0.18, -14), (0.34, 32), (0.50, 28)], crouch=[(0.34, -0.34), (0.50, -0.28)]),
        swing("PaladinSweep", [
            (0.00, (0.74, 0.98, -0.22), (0.52, 0.44, 0.73)),
            (0.18, (0.90, 0.94, 0.20), (0.66, 0.36, 0.66)),
            (0.36, (-0.10, 0.86, -1.00), (-0.86, -0.10, -0.50)),
            (0.52, (-0.48, 0.82, -0.72), (-0.92, -0.06, -0.38)),
            (0.76, (0.66, 1.14, -0.16), (0.18, 0.86, 0.48)),
        ], twist=[(0.00, -18), (0.18, -34), (0.36, 26), (0.52, 38), (0.76, -8)]),
    ],

    # King: broad and showy. Wide slash, rising cut, overhead finisher.
    "RoyalBlade": [
        swing("RoyalSlash", [
            (0.00, (0.70, 1.10, -0.24), (0.46, 0.62, 0.64)),
            (0.16, (0.88, 1.16, 0.18), (0.60, 0.54, 0.59)),
            (0.32, (-0.06, 0.92, -0.98), (-0.88, 0.02, -0.48)),
            (0.48, (-0.44, 0.88, -0.70), (-0.94, 0.06, -0.34)),
            (0.70, (0.70, 1.10, -0.24), (0.46, 0.62, 0.64)),
        ], twist=[(0.00, -16), (0.16, -32), (0.32, 26), (0.48, 36), (0.70, -16)]),
        swing("RoyalRise", [
            (0.00, (-0.40, 0.72, -0.66), (-0.80, -0.34, -0.50)),
            (0.14, (-0.52, 0.58, -0.44), (-0.84, -0.44, -0.32)),
            (0.30, (0.50, 1.34, -0.80), (0.44, 0.80, -0.42)),
            (0.46, (0.72, 1.40, -0.44), (0.56, 0.76, -0.34)),
            (0.70, (0.70, 1.10, -0.24), (0.46, 0.62, 0.64)),
        ], twist=[(0.00, 32), (0.14, 40), (0.30, -22), (0.46, -32), (0.70, -16)]),
        swing("RoyalCrash", [
            (0.00, (0.60, 1.26, -0.10), (0.12, 0.88, 0.46)),
            (0.20, (0.34, 1.50, 0.32), (-0.04, 0.74, 0.67)),
            (0.36, (0.14, 0.92, -0.94), (-0.06, -0.58, -0.81)),
            (0.52, (0.12, 0.82, -0.88), (-0.06, -0.66, -0.75)),
            (0.78, (0.70, 1.10, -0.24), (0.46, 0.62, 0.64)),
        ], twist=[(0.00, -6), (0.20, 14), (0.36, -8), (0.52, -10), (0.78, -16)],
           lean=[(0.20, -18), (0.36, 36), (0.52, 30)], crouch=[(0.36, -0.38), (0.52, -0.30)]),
    ],

    # Greatsword: only two hits, both enormous.
    "Greatsword": [
        swing("GreatswordCleave", [
            (0.00, (0.58, 1.10, -0.08), (-0.18, 0.80, 0.57)),
            (0.20, (0.66, 1.22, 0.22), (-0.24, 0.78, 0.58)),
            (0.38, (0.06, 0.90, -0.90), (-0.94, 0.04, -0.34)),
            (0.56, (-0.34, 0.84, -0.66), (-0.96, 0.00, -0.28)),
            (0.84, (0.58, 1.10, -0.08), (-0.18, 0.80, 0.57)),
        ], twist=[(0.00, -14), (0.20, -30), (0.38, 28), (0.56, 38), (0.84, -14)]),
        swing("GreatswordCrash", [
            (0.00, (0.42, 1.24, 0.08), (-0.14, 0.82, 0.55)),
            (0.22, (0.24, 1.46, 0.34), (-0.10, 0.70, 0.71)),
            (0.40, (0.10, 0.94, -0.86), (-0.04, -0.60, -0.80)),
            (0.56, (0.08, 0.84, -0.80), (-0.04, -0.68, -0.73)),
            (0.88, (0.58, 1.10, -0.08), (-0.18, 0.80, 0.57)),
        ], twist=[(0.00, -8), (0.22, 10), (0.40, -8), (0.56, -10), (0.88, -14)],
           lean=[(0.22, -18), (0.40, 40), (0.56, 34)], crouch=[(0.40, -0.42), (0.56, -0.34)]),
    ],
}

if ONLY:
    MOVESETS = {k: v for k, v in MOVESETS.items() if k == ONLY}


# ---------------------------------------------------------------------------
# rig  (identical construction to blender_rig.py, which this replaces)
# ---------------------------------------------------------------------------
data = json.load(open(DUMP))
JOINTS = {j["Child"]: j for j in data["Joints"]}
PARTS = data["Parts"]
ROOT = "HumanoidRootPart"
PARENT = {j["Child"]: j["Parent"] for j in data["Joints"]}

PRIMARY = {
    "HumanoidRootPart": "LowerTorso", "LowerTorso": "UpperTorso", "UpperTorso": "Head",
    "RightUpperArm": "RightLowerArm", "RightLowerArm": "RightHand",
    "LeftUpperArm": "LeftLowerArm", "LeftLowerArm": "LeftHand",
    "RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot",
    "LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot",
}

rest_part = {ROOT: Matrix.Identity(4)}
order = [ROOT]
changed = True
while changed:
    changed = False
    for child, j in JOINTS.items():
        if child in rest_part or j["Parent"] not in rest_part:
            continue
        rest_part[child] = rest_part[j["Parent"]] @ cf(j["A0"]) @ cf(j["A1"]).inverted()
        order.append(child)
        changed = True

A1 = {ROOT: Matrix.Identity(4)}
for child, j in JOINTS.items():
    A1[child] = cf(j["A1"])
rest_frame = {p: rest_part[p] @ A1[p] for p in rest_part}

REACH = ((rest_frame["RightUpperArm"].translation - rest_frame["RightLowerArm"].translation).length
         + (rest_frame["RightLowerArm"].translation - rest_frame["RightHand"].translation).length)

#[[ GUARD. Animations must be authored against a DEFAULT R15, never against
#   whatever avatar happened to be standing in a test session. A player's own
#   body can have shoulders at hip height and half the arm reach, and poses
#   tuned to it look broken on everyone else.
#
#   This exists because a live rig dump silently overwrote the standard one and
#   a whole moveset got authored against the wrong skeleton before anyone
#   noticed. Failing loudly is cheap; re-authoring is not. ]]
SHOULDER_Y = rest_frame["RightUpperArm"].translation.y
if REACH < 1.5 or SHOULDER_Y < 0.5:
    raise SystemExit(
        "REFUSING TO AUTHOR: %s is not a default R15 rig "
        "(reach=%.3f expected ~1.73, shoulderY=%.2f expected ~0.85).
"
        "Re-dump a standard rig before running this."
        % (os.path.basename(DUMP), REACH, SHOULDER_Y))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS

arm_data = bpy.data.armatures.new("R15")
arm_obj = bpy.data.objects.new("R15", arm_data)
scene.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode="EDIT")
for p in order:
    eb = arm_data.edit_bones.new(p)
    F = rest_frame[p]
    head = F.translation.copy()
    kid = PRIMARY.get(p)
    tail = rest_frame[kid].translation.copy() if (kid and kid in rest_frame) else None
    if tail is None or (tail - head).length < 1e-4:
        tail = head + F.to_3x3() @ Vector((0, 0.3, 0))
    eb.head, eb.tail = head, tail
    if p in PARENT:
        eb.parent = arm_data.edit_bones[PARENT[p]]
    eb.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

CONV = {p: rest_frame[p].to_3x3().inverted() @ arm_data.bones[p].matrix_local.to_3x3()
        for p in order}

RGA = cf(data["Grip"]["C0"])          # RightGripAttachment on the hand
pb = arm_obj.pose.bones


def clear_pose():
    for b in pb:
        b.matrix_basis = Matrix.Identity(4)
        b.rotation_mode = "QUATERNION"
    for b in pb:
        for c in list(b.constraints):
            b.constraints.remove(c)
    if arm_obj.animation_data:
        arm_obj.animation_data_clear()


def build_targets(spec, wctl):
    grip_rel = RGA @ spec["grip"].inverted()
    k_right = grip_rel.inverted() @ A1["RightHand"]

    rt = bpy.data.objects.new("RT", None)
    scene.collection.objects.link(rt)
    rt.parent = wctl
    rt.matrix_parent_inverse = Matrix.Identity(4)
    rt.matrix_basis = k_right @ CONV["RightHand"].to_4x4()

    c = pb["RightLowerArm"].constraints.new("IK")
    c.target, c.chain_count, c.use_rotation = rt, 2, False
    cr = pb["RightHand"].constraints.new("COPY_ROTATION")
    cr.target = rt

    lt = None
    if spec.get("two"):
        left_off = k_right.translation + Vector((0, spec.get("spacing", 0.85), 0))
        lt = bpy.data.objects.new("LT", None)
        scene.collection.objects.link(lt)
        lt.parent = wctl
        lt.matrix_parent_inverse = Matrix.Identity(4)
        lt.matrix_basis = (Matrix.Translation(left_off)
                           @ Matrix.Rotation(math.pi, 4, "Y") @ CONV["LeftHand"].to_4x4())
        c2 = pb["LeftLowerArm"].constraints.new("IK")
        c2.target, c2.chain_count, c2.use_rotation = lt, 2, False
        cr2 = pb["LeftHand"].constraints.new("COPY_ROTATION")
        cr2.target = lt
    return grip_rel, k_right, rt, lt


def weapon_matrix(wrist, direction, k_right):
    Y = Vector(direction).normalized()
    ref = Vector((0, 0, -1)) if abs(Y.z) < 0.9 else Vector((1, 0, 0))
    X = Y.cross(ref).normalized()
    Z = X.cross(Y)
    R = Matrix(((X.x, Y.x, Z.x, 0), (X.y, Y.y, Z.y, 0), (X.z, Y.z, Z.z, 0), (0, 0, 0, 1)))
    origin = Vector(wrist) - R.to_3x3() @ k_right.translation
    return Matrix.Translation(origin) @ R


def key_pose(bone, T, frame):
    p = pb[bone]
    p.rotation_mode = "QUATERNION"
    C = CONV[bone].to_4x4()
    p.matrix_basis = C.inverted() @ T @ C
    p.keyframe_insert("rotation_quaternion", frame=frame)
    p.keyframe_insert("location", frame=frame)


def lerp_at(keys, t, default=0.0):
    if not keys:
        return default
    if t <= keys[0][0]:
        return keys[0][1]
    if t >= keys[-1][0]:
        return keys[-1][1]
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a[0] <= t <= b[0]:
            f = (t - a[0]) / max(b[0] - a[0], 1e-6)
            return a[1] + (b[1] - a[1]) * f
    return default


# ---------------------------------------------------------------------------
# build every clip
# ---------------------------------------------------------------------------
os.makedirs(RENDER_DIR, exist_ok=True)
out = {"Fps": FPS, "Movesets": {}}
report = []

for wname, clips in MOVESETS.items():
    spec = WEAPONS[wname]
    out["Movesets"][wname] = {}

    for clip in clips:
        clear_pose()
        wctl = bpy.data.objects.new("WeaponCtl", None)
        scene.collection.objects.link(wctl)
        grip_rel, k_right, rt, lt = build_targets(spec, wctl)

        beats = clip["Beats"]
        dur = beats[-1][0]
        scene.frame_start, scene.frame_end = 0, round(dur * FPS)

        wctl.rotation_mode = "QUATERNION"
        over = []
        for (t, wrist, direction) in beats:
            f = round(t * FPS)
            wctl.matrix_basis = weapon_matrix(wrist, direction, k_right)
            wctl.keyframe_insert("location", frame=f)
            wctl.keyframe_insert("rotation_quaternion", frame=f)
            d = (Vector(wrist) - rest_frame["RightUpperArm"].translation).length
            if d > REACH * spec.get("reachMul", 1.0):
                over.append("t=%.2f right=%.2f" % (t, d))

        # Torso, hips and legs carry the swing; keyed from the twist/lean track.
        for (t, _w, _d) in beats:
            f = round(t * FPS)
            yaw = lerp_at(clip["Twist"], t)
            lean = lerp_at(clip["Lean"], t)
            sink = lerp_at(clip["Crouch"], t)
            key_pose("LowerTorso", Matrix.Translation((0, sink, 0)) @ angles(lean * 0.3, yaw * 0.45, 0), f)
            key_pose("UpperTorso", angles(lean * 0.7, yaw * 0.85, -yaw * 0.12), f)
            key_pose("Head", angles(0, -yaw * 0.35, 0), f)
            if clip["Legs"]:
                key_pose("RightUpperLeg", angles(-6 + sink * 34, 0, 0), f)
                key_pose("RightLowerLeg", angles(8 - sink * 42, 0, 0), f)
                key_pose("LeftUpperLeg", angles(-4 + sink * 26, 0, 0), f)
                key_pose("LeftLowerLeg", angles(6 - sink * 32, 0, 0), f)
            if not spec.get("two"):
                # Free hand counterbalances the swing instead of gripping.
                key_pose("LeftUpperArm", angles(-18 - yaw * 0.9, 0, 22 + yaw * 0.5), f)
                key_pose("LeftLowerArm", angles(-26 - abs(yaw) * 0.5, 0, 0), f)

        # ---- evaluate, verify, export ----
        dg = bpy.context.evaluated_depsgraph_get()
        frames = []
        worst = 0.0
        for fnum in range(scene.frame_start, scene.frame_end + 1):
            scene.frame_set(fnum)
            dg.update()
            pose_world = {p: pb[p].matrix.copy() for p in order}
            basis = {}
            for p in order:
                par = PARENT.get(p)
                rest_local = (arm_data.bones[p].matrix_local if par is None else
                              arm_data.bones[par].matrix_local.inverted() @ arm_data.bones[p].matrix_local)
                parent_pose = pose_world[par] if par else Matrix.Identity(4)
                basis[p] = rest_local.inverted() @ parent_pose.inverted() @ pose_world[p]

            rec = {"T": round(fnum / FPS, 4), "Joints": {}}
            T_by = {}
            for p in order:
                if p == ROOT:
                    continue
                C = CONV[p].to_4x4()
                T = C @ basis[p] @ C.inverted()
                T_by[p] = T
                rec["Joints"][p] = [round(v, 5) for v in comps(T)]
            frames.append(rec)

            replay = {ROOT: Matrix.Identity(4)}
            for p in order:
                if p == ROOT:
                    continue
                j = JOINTS[p]
                replay[p] = replay[j["Parent"]] @ cf(j["A0"]) @ T_by[p] @ cf(j["A1"]).inverted()
            F = {p: pose_world[p] @ CONV[p].inverted().to_4x4() for p in order}
            pw = {p: F[p] @ A1[p].inverted() for p in order}
            worst = max(worst, max((replay[p].translation - pw[p].translation).length for p in order))

        out["Movesets"][wname][clip["Name"]] = {"Duration": dur, "Frames": frames}
        report.append((wname, clip["Name"], dur, len(frames), worst, over))

        bpy.data.objects.remove(wctl, do_unlink=True)

json.dump(out, open(OUT_POSES, "w"))

print("\n%-13s %-20s %5s %6s %11s %s" % ("WEAPON", "CLIP", "DUR", "FRAMES", "REPLAY-ERR", "REACH"))
bad = 0
for wname, cname, dur, n, worst, over in report:
    flag = "OK" if worst < 1e-3 else "BAD MATHS"
    if worst >= 1e-3:
        bad += 1
    print("%-13s %-20s %5.2f %6d %11.6f %s  %s"
          % (wname, cname, dur, n, worst, flag, ("OVER-REACH " + "; ".join(over)) if over else ""))
print("\nARM REACH %.3f studs   clips=%d   maths-failures=%d" % (REACH, len(report), bad))
print("WROTE %s" % OUT_POSES)
