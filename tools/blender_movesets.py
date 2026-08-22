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
#[[ --blend <Weapon> lays that weapon's clips end to end on one timeline with
#   named markers and saves a .blend, so the animation can be scrubbed and
#   edited by hand instead of only judged from a contact sheet. ]]
BLEND = argv[argv.index("--blend") + 1] if "--blend" in argv else None
FRAME_OFFSET = 0
MARKERS = []
SHARED = {}

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


def swing(name, beats, twist=None, lean=None, crouch=None, step=None, left=None, legs=True):
    """One clip.

    beats  (time, wrist_xyz, haft_direction)
    step   (time, weight) where weight runs -1 (rocked back onto the rear
           foot) through 0 (square) to +1 (driven forward onto the front
           foot). This is the footwork: a swing with static legs reads as a
           torso rotating on a pole, because all the force appears from
           nowhere. Real strikes are thrown from the ground up - load back,
           drive forward, plant.
    """
    return dict(Name=name, Beats=beats, Twist=twist or [], Lean=lean or [],
                Crouch=crouch or [], Step=step or [], Left=left or [], Legs=legs)


# ---------------------------------------------------------------------------
# THE MOVESETS - one per class, deliberately different silhouettes
# ---------------------------------------------------------------------------
# Character faces -Z, up is +Y, right is +X. Shoulders sit at (+-0.97, 0.85, 0)
# with 1.73 studs of reach, so every wrist below stays well inside that.

MOVESETS = {
    # Every clip below follows the same four rules, which came out of the
    # jump-cut fix and the head-clearance measurements:
    #   1. Eight to ten beats, so no single frame carries a huge rotation.
    #   2. The blade always points AWAY from the body; it never routes over
    #      the head, which sits at x=0, y~1.6.
    #   3. Wind up to the side, strike FORWARD (-Z), so facing is unambiguous.
    #   4. Step tracks the weight: load onto the back foot, drive off it,
    #      plant. A swing with static legs reads as a torso on a pole.

    # Swordsman: crisp and economical. Level slash, level backhand, thrust.
    "Sword": [
        swing("SwordSlash", [
            (0.00, (0.70, 1.02, -0.30), (0.52, 0.16, -0.84)),
            (0.14, (0.84, 1.06, 0.02), (0.78, 0.12, -0.61)),
            (0.26, (0.80, 1.04, -0.26), (0.54, 0.08, -0.84)),
            (0.36, (0.56, 1.02, -0.60), (0.14, 0.04, -0.99)),
            (0.46, (0.20, 1.00, -0.76), (-0.38, 0.02, -0.92)),
            (0.56, (-0.18, 0.98, -0.70), (-0.76, 0.00, -0.65)),
            (0.66, (-0.44, 0.96, -0.52), (-0.93, -0.02, -0.36)),
            (0.80, (-0.26, 0.99, -0.38), (-0.58, 0.12, -0.81)),
            (0.96, (0.70, 1.02, -0.30), (0.52, 0.16, -0.84)),
        ], twist=[(0.00, -12), (0.14, -28), (0.36, -8), (0.56, 20), (0.66, 30), (0.96, -12)],
           step=[(0.00, -0.2), (0.14, -0.7), (0.36, 0.2), (0.46, 0.8), (0.66, 0.5), (0.96, -0.2)]),
        swing("SwordBackhand", [
            (0.00, (-0.40, 0.98, -0.50), (-0.90, 0.02, -0.44)),
            (0.14, (-0.54, 0.96, -0.30), (-0.96, 0.00, -0.28)),
            (0.26, (-0.34, 0.98, -0.62), (-0.72, 0.04, -0.69)),
            (0.36, (0.02, 1.02, -0.78), (-0.24, 0.08, -0.97)),
            (0.46, (0.40, 1.06, -0.70), (0.30, 0.10, -0.95)),
            (0.56, (0.72, 1.08, -0.46), (0.72, 0.12, -0.68)),
            (0.66, (0.86, 1.08, -0.16), (0.88, 0.14, -0.45)),
            (0.80, (0.80, 1.05, -0.30), (0.66, 0.16, -0.73)),
            (0.96, (0.70, 1.02, -0.30), (0.52, 0.16, -0.84)),
        ], twist=[(0.00, 30), (0.14, 38), (0.36, 10), (0.56, -18), (0.66, -28), (0.96, -12)],
           step=[(0.00, 0.4), (0.14, -0.5), (0.36, 0.3), (0.46, 0.8), (0.66, 0.4), (0.96, -0.2)]),
        swing("SwordThrust", [
            (0.00, (0.72, 1.02, -0.26), (0.36, 0.14, -0.92)),
            (0.14, (0.86, 1.00, 0.10), (0.30, 0.12, -0.95)),
            (0.24, (0.80, 1.00, -0.20), (0.20, 0.08, -0.98)),
            (0.32, (0.62, 1.00, -0.62), (0.10, 0.04, -0.99)),
            (0.40, (0.42, 1.00, -0.96), (0.02, 0.02, -1.00)),
            (0.50, (0.46, 1.00, -0.88), (0.04, 0.04, -1.00)),
            (0.64, (0.62, 1.01, -0.56), (0.20, 0.10, -0.98)),
            (0.84, (0.70, 1.02, -0.30), (0.52, 0.16, -0.84)),
        ], twist=[(0.00, -14), (0.14, -26), (0.40, 12), (0.50, 14), (0.84, -12)],
           lean=[(0.40, 12), (0.50, 10)],
           step=[(0.00, -0.2), (0.14, -0.8), (0.32, 0.4), (0.40, 0.9), (0.64, 0.4), (0.84, -0.2)]),
    ],

    # Assassin: short, fast, low. Both hands work.
    "Dagger": [
        swing("DaggerStab", [
            (0.00, (0.60, 0.92, -0.34), (0.30, 0.10, -0.95)),
            (0.08, (0.72, 0.90, 0.00), (0.26, 0.08, -0.96)),
            (0.16, (0.62, 0.90, -0.34), (0.16, 0.06, -0.99)),
            (0.24, (0.44, 0.90, -0.72), (0.06, 0.02, -1.00)),
            (0.32, (0.34, 0.90, -0.94), (0.02, 0.00, -1.00)),
            (0.42, (0.40, 0.91, -0.78), (0.08, 0.04, -1.00)),
            (0.58, (0.60, 0.92, -0.34), (0.30, 0.10, -0.95)),
        ], twist=[(0.00, -12), (0.08, -24), (0.32, 14), (0.58, -12)],
           step=[(0.00, -0.2), (0.08, -0.7), (0.24, 0.5), (0.32, 0.9), (0.58, -0.2)]),
        swing("DaggerCross", [
            (0.00, (0.62, 0.96, -0.36), (0.48, 0.10, -0.87)),
            (0.10, (0.78, 0.98, -0.06), (0.72, 0.08, -0.69)),
            (0.20, (0.68, 0.96, -0.42), (0.42, 0.06, -0.90)),
            (0.28, (0.38, 0.94, -0.72), (0.02, 0.04, -1.00)),
            (0.36, (0.02, 0.92, -0.80), (-0.44, 0.02, -0.90)),
            (0.46, (-0.30, 0.92, -0.66), (-0.82, 0.00, -0.57)),
            (0.60, (-0.10, 0.94, -0.48), (-0.44, 0.08, -0.89)),
            (0.74, (0.60, 0.92, -0.34), (0.30, 0.10, -0.95)),
        ], twist=[(0.00, -14), (0.10, -30), (0.28, 4), (0.46, 28), (0.74, -12)],
           step=[(0.00, -0.2), (0.10, -0.7), (0.28, 0.5), (0.36, 0.9), (0.60, 0.3), (0.74, -0.2)]),
        swing("DaggerSpin", [
            (0.00, (-0.28, 0.92, -0.52), (-0.82, 0.06, -0.57)),
            (0.10, (-0.46, 0.94, -0.28), (-0.94, 0.10, -0.32)),
            (0.20, (-0.22, 0.96, -0.62), (-0.66, 0.14, -0.74)),
            (0.28, (0.14, 1.00, -0.80), (-0.18, 0.18, -0.97)),
            (0.36, (0.50, 1.04, -0.72), (0.36, 0.22, -0.91)),
            (0.46, (0.76, 1.06, -0.44), (0.74, 0.24, -0.63)),
            (0.60, (0.70, 1.00, -0.40), (0.52, 0.16, -0.84)),
            (0.76, (0.60, 0.92, -0.34), (0.30, 0.10, -0.95)),
        ], twist=[(0.00, 30), (0.10, 40), (0.28, 6), (0.46, -26), (0.76, -12)],
           step=[(0.00, 0.3), (0.10, -0.6), (0.28, 0.4), (0.36, 0.9), (0.60, 0.3), (0.76, -0.2)]),
    ],

    # Paladin: grounded and heavy, always braced behind the shield.
    "PaladinBlade": [
        swing("PaladinChop", [
            (0.00, (0.68, 1.08, -0.22), (0.42, 0.42, -0.80)),
            (0.16, (0.84, 1.30, 0.06), (0.52, 0.62, -0.59)),
            (0.28, (0.80, 1.34, -0.10), (0.42, 0.66, -0.62)),
            (0.38, (0.66, 1.22, -0.48), (0.24, 0.34, -0.91)),
            (0.48, (0.44, 1.02, -0.76), (0.10, -0.24, -0.97)),
            (0.58, (0.30, 0.90, -0.86), (0.02, -0.56, -0.83)),
            (0.70, (0.28, 0.86, -0.84), (0.00, -0.62, -0.78)),
            (0.88, (0.50, 0.98, -0.50), (0.20, 0.06, -0.98)),
            (1.06, (0.68, 1.08, -0.22), (0.42, 0.42, -0.80)),
        ], twist=[(0.00, -8), (0.16, -18), (0.48, 4), (0.70, 8), (1.06, -8)],
           lean=[(0.16, -12), (0.58, 24), (0.70, 22)], crouch=[(0.58, -0.26), (0.70, -0.22)],
           step=[(0.00, -0.2), (0.16, -0.8), (0.38, 0.3), (0.58, 0.9), (0.88, 0.4), (1.06, -0.2)]),
        swing("PaladinSweep", [
            (0.00, (0.74, 1.00, -0.24), (0.60, 0.10, -0.79)),
            (0.16, (0.88, 1.00, 0.08), (0.84, 0.08, -0.54)),
            (0.28, (0.82, 1.00, -0.24), (0.58, 0.06, -0.81)),
            (0.38, (0.58, 0.98, -0.62), (0.16, 0.04, -0.99)),
            (0.48, (0.20, 0.96, -0.80), (-0.36, 0.02, -0.93)),
            (0.58, (-0.20, 0.96, -0.74), (-0.76, 0.00, -0.65)),
            (0.70, (-0.50, 0.96, -0.54), (-0.94, -0.02, -0.34)),
            (0.86, (-0.28, 0.98, -0.40), (-0.56, 0.08, -0.82)),
            (1.04, (0.74, 1.00, -0.24), (0.60, 0.10, -0.79)),
        ], twist=[(0.00, -16), (0.16, -32), (0.38, -6), (0.58, 22), (0.70, 32), (1.04, -16)],
           step=[(0.00, -0.2), (0.16, -0.8), (0.38, 0.3), (0.48, 0.9), (0.70, 0.4), (1.04, -0.2)]),
    ],

    # King: broad and showy, but never wild.
    "RoyalBlade": [
        swing("RoyalSlash", [
            (0.00, (0.72, 1.06, -0.28), (0.56, 0.18, -0.81)),
            (0.14, (0.88, 1.10, 0.04), (0.80, 0.16, -0.58)),
            (0.26, (0.82, 1.08, -0.26), (0.56, 0.12, -0.82)),
            (0.36, (0.58, 1.04, -0.62), (0.14, 0.08, -0.99)),
            (0.46, (0.20, 1.02, -0.78), (-0.38, 0.06, -0.92)),
            (0.56, (-0.20, 1.00, -0.72), (-0.78, 0.04, -0.62)),
            (0.68, (-0.48, 0.98, -0.52), (-0.94, 0.00, -0.34)),
            (0.84, (-0.26, 1.02, -0.38), (-0.56, 0.14, -0.82)),
            (1.00, (0.72, 1.06, -0.28), (0.56, 0.18, -0.81)),
        ], twist=[(0.00, -14), (0.14, -30), (0.36, -6), (0.56, 22), (0.68, 32), (1.00, -14)],
           step=[(0.00, -0.2), (0.14, -0.7), (0.36, 0.3), (0.46, 0.9), (0.68, 0.4), (1.00, -0.2)]),
        swing("RoyalRise", [
            (0.00, (-0.42, 0.92, -0.48), (-0.90, -0.10, -0.43)),
            (0.14, (-0.56, 0.86, -0.28), (-0.94, -0.20, -0.28)),
            (0.26, (-0.34, 0.92, -0.60), (-0.70, 0.04, -0.71)),
            (0.36, (0.02, 1.02, -0.78), (-0.22, 0.24, -0.95)),
            (0.46, (0.42, 1.16, -0.72), (0.30, 0.44, -0.85)),
            (0.56, (0.74, 1.28, -0.46), (0.68, 0.52, -0.52)),
            (0.68, (0.88, 1.32, -0.18), (0.82, 0.50, -0.28)),
            (0.84, (0.80, 1.16, -0.28), (0.66, 0.30, -0.69)),
            (1.00, (0.72, 1.06, -0.28), (0.56, 0.18, -0.81)),
        ], twist=[(0.00, 30), (0.14, 38), (0.36, 8), (0.56, -22), (0.68, -30), (1.00, -14)],
           step=[(0.00, 0.3), (0.14, -0.6), (0.36, 0.4), (0.46, 0.9), (0.68, 0.4), (1.00, -0.2)]),
        swing("RoyalCrash", [
            (0.00, (0.66, 1.10, -0.26), (0.38, 0.46, -0.80)),
            (0.16, (0.80, 1.34, 0.02), (0.44, 0.68, -0.59)),
            (0.30, (0.74, 1.40, -0.14), (0.32, 0.74, -0.59)),
            (0.40, (0.62, 1.28, -0.50), (0.18, 0.40, -0.90)),
            (0.50, (0.42, 1.06, -0.78), (0.06, -0.20, -0.98)),
            (0.60, (0.26, 0.92, -0.88), (0.00, -0.54, -0.84)),
            (0.72, (0.22, 0.88, -0.86), (-0.02, -0.62, -0.78)),
            (0.90, (0.48, 1.00, -0.52), (0.18, 0.10, -0.98)),
            (1.08, (0.72, 1.06, -0.28), (0.56, 0.18, -0.81)),
        ], twist=[(0.00, -8), (0.16, -16), (0.50, 2), (0.72, 8), (1.08, -14)],
           lean=[(0.16, -14), (0.60, 26), (0.72, 24)], crouch=[(0.60, -0.28), (0.72, -0.24)],
           step=[(0.00, -0.2), (0.16, -0.8), (0.40, 0.3), (0.60, 0.9), (0.90, 0.4), (1.08, -0.2)]),
    ],

    # Berserker: level cleave, then the overhead crash. Both stay forward.
    "Greataxe": [
        swing("BerserkerCleave", [
            (0.00, (0.72, 0.92, -0.30), (0.55, 0.10, -0.83)),
            (0.18, (0.86, 0.94, 0.02), (0.80, 0.06, -0.60)),
            (0.32, (0.80, 0.94, -0.30), (0.55, 0.04, -0.84)),
            (0.42, (0.55, 0.94, -0.62), (0.12, 0.02, -0.99)),
            (0.52, (0.18, 0.94, -0.76), (-0.40, 0.00, -0.92)),
            (0.62, (-0.22, 0.92, -0.72), (-0.78, -0.02, -0.63)),
            (0.72, (-0.50, 0.90, -0.52), (-0.94, -0.04, -0.34)),
            (0.88, (-0.30, 0.92, -0.38), (-0.60, 0.10, -0.79)),
            (1.04, (0.72, 0.92, -0.30), (0.55, 0.10, -0.83)),
        ], twist=[(0.00, -14), (0.18, -30), (0.32, -18), (0.52, 14), (0.72, 32), (0.88, 20), (1.04, -14)],
           step=[(0.00, -0.2), (0.18, -0.8), (0.42, 0.3), (0.52, 0.9), (0.72, 0.5), (1.04, -0.2)]),
        swing("BerserkerCrash", [
            (0.00, (0.68, 1.00, -0.22), (0.40, 0.42, -0.81)),
            (0.18, (0.84, 1.26, 0.04), (0.50, 0.64, -0.58)),
            (0.32, (0.78, 1.34, -0.12), (0.38, 0.70, -0.60)),
            (0.42, (0.64, 1.20, -0.52), (0.20, 0.34, -0.92)),
            (0.52, (0.44, 1.00, -0.80), (0.08, -0.26, -0.96)),
            (0.62, (0.28, 0.88, -0.90), (0.02, -0.58, -0.81)),
            (0.74, (0.24, 0.84, -0.88), (0.00, -0.66, -0.75)),
            (0.92, (0.48, 0.96, -0.52), (0.18, 0.08, -0.98)),
            (1.12, (0.68, 1.00, -0.22), (0.40, 0.42, -0.81)),
        ], twist=[(0.00, -8), (0.18, -18), (0.52, 2), (0.74, 8), (1.12, -8)],
           lean=[(0.18, -14), (0.62, 28), (0.74, 26)], crouch=[(0.62, -0.30), (0.74, -0.26)],
           step=[(0.00, -0.2), (0.18, -0.8), (0.42, 0.3), (0.62, 0.95), (0.92, 0.4), (1.12, -0.2)]),
    ],


    # ------------------------------------------------------------------
    # RANGED. A slash animation on a musket reads as nonsense, so these are
    # authored as what they actually are: a draw, a shot and a cast. Each is
    # a single clip, because a bow has no combo - it has a rhythm.
    # ------------------------------------------------------------------

    # Archer: raise, draw to the cheek, hold, loose, recover. The bow hand is
    # steady; the STRING hand does the work, so it gets an explicit track.
    "Bow": [
        swing("BowDraw", [
            (0.00, (0.55, 0.88, -0.42), (0.24, 0.92, -0.30)),
            (0.16, (0.44, 1.16, -0.78), (0.06, 0.99, -0.12)),
            (0.34, (0.42, 1.18, -0.82), (0.04, 1.00, -0.08)),
            (0.52, (0.42, 1.18, -0.82), (0.04, 1.00, -0.08)),
            (0.62, (0.46, 1.16, -0.76), (0.06, 0.99, -0.14)),
            (0.86, (0.55, 0.88, -0.42), (0.24, 0.92, -0.30)),
        ], twist=[(0.00, -6), (0.16, -16), (0.52, -20), (0.62, -12), (0.86, -6)],
           step=[(0.00, -0.1), (0.16, 0.2), (0.52, 0.3), (0.62, 0.1), (0.86, -0.1)],
           left=[(0.00, (-20, 0, 18), (-30, 0, 0)),
                 (0.16, (-52, -6, 12), (-46, 0, 0)),
                 (0.34, (-58, -18, 8), (-96, 0, 0)),
                 (0.52, (-60, -22, 6), (-108, 0, 0)),
                 (0.62, (-42, -8, 10), (-52, 0, 0)),
                 (0.86, (-20, 0, 18), (-30, 0, 0))]),
    ],

    # Musketeer: shoulder it, settle, fire, ride the kick. The recoil IS the
    # animation - a musket that fires without moving reads as a toy.
    "Musket": [
        swing("MusketFire", [
            # Held further outboard than feels natural on paper: a 4.4 stud
            # barrel carried on the centre line passes straight through the
            # head, which the clearance check catches and the eye does not.
            (0.00, (0.90,0.90, -0.26), (0.34, 0.52, -0.78)),
            (0.20, (0.88,1.12, -0.34), (0.22, 0.20, -0.95)),
            (0.34, (0.86,1.15, -0.38), (0.18, 0.14, -0.97)),
            (0.42, (0.86,1.15, -0.39), (0.18, 0.13, -0.97)),
            (0.46, (0.88,1.17, -0.32), (0.19, 0.20, -0.96)),
            (0.50, (0.92,1.20, -0.22), (0.20, 0.29, -0.94)),
            (0.56, (0.90,1.18, -0.28), (0.19, 0.24, -0.95)),
            (0.64, (0.88,1.16, -0.33), (0.18, 0.18, -0.97)),
            (0.76, (0.87,1.13, -0.35), (0.19, 0.16, -0.97)),
            (0.96, (0.90,0.90, -0.26), (0.34, 0.52, -0.78)),
        ], twist=[(0.00, -8), (0.20, -18), (0.42, -20), (0.50, -10), (0.96, -8)],
           lean=[(0.42, 6), (0.50, -10), (0.64, -3)],
           step=[(0.00, -0.1), (0.20, 0.3), (0.42, 0.4), (0.50, -0.35), (0.76, 0.1), (0.96, -0.1)]),
    ],

    # Necromancer: plant, raise, drive the staff forward and pulse. Slower
    # than everything else - nothing about him is hurried.
    "NecroStaff": [
        swing("StaffCast", [
            (0.00, (0.78, 0.86, -0.06), (0.10, 0.98, 0.17)),
            (0.22, (0.74, 1.26, -0.16), (0.08, 0.99, 0.11)),
            (0.34, (0.72, 1.30, -0.22), (0.09, 0.98, 0.00)),
            (0.46, (0.68, 1.16, -0.56), (0.11, 0.80, -0.59)),
            (0.56, (0.66, 1.10, -0.68), (0.12, 0.71, -0.69)),
            (0.68, (0.68, 1.12, -0.62), (0.11, 0.75, -0.65)),
            (0.94, (0.78, 0.86, -0.06), (0.10, 0.98, 0.17)),
        ], twist=[(0.00, 6), (0.22, 10), (0.46, -8), (0.56, -12), (0.94, 6)],
           lean=[(0.22, -8), (0.56, 14), (0.68, 10)],
           step=[(0.00, -0.1), (0.22, -0.4), (0.46, 0.5), (0.56, 0.7), (0.94, -0.1)]),
    ],

    # Greatsword: two hits, both enormous, both in front.
    "Greatsword": [
        swing("GreatswordCleave", [
            (0.00, (0.66, 1.04, -0.24), (0.50, 0.20, -0.84)),
            (0.18, (0.84, 1.08, 0.08), (0.78, 0.16, -0.60)),
            (0.32, (0.78, 1.06, -0.26), (0.54, 0.12, -0.83)),
            (0.42, (0.54, 1.02, -0.64), (0.12, 0.08, -0.99)),
            (0.52, (0.16, 1.00, -0.80), (-0.40, 0.04, -0.92)),
            (0.62, (-0.24, 0.98, -0.74), (-0.80, 0.02, -0.60)),
            (0.74, (-0.52, 0.96, -0.52), (-0.95, 0.00, -0.32)),
            (0.90, (-0.30, 1.00, -0.38), (-0.58, 0.14, -0.80)),
            (1.08, (0.66, 1.04, -0.24), (0.50, 0.20, -0.84)),
        ], twist=[(0.00, -14), (0.18, -30), (0.42, -6), (0.62, 22), (0.74, 34), (1.08, -14)],
           step=[(0.00, -0.2), (0.18, -0.85), (0.42, 0.3), (0.52, 0.95), (0.74, 0.5), (1.08, -0.2)]),
        swing("GreatswordCrash", [
            (0.00, (0.62, 1.08, -0.20), (0.36, 0.48, -0.80)),
            (0.18, (0.80, 1.34, 0.06), (0.44, 0.70, -0.56)),
            (0.34, (0.74, 1.42, -0.12), (0.32, 0.76, -0.56)),
            (0.44, (0.60, 1.26, -0.54), (0.18, 0.36, -0.91)),
            (0.54, (0.40, 1.04, -0.82), (0.06, -0.24, -0.97)),
            (0.64, (0.24, 0.90, -0.92), (0.00, -0.58, -0.82)),
            (0.76, (0.20, 0.86, -0.90), (-0.02, -0.66, -0.75)),
            (0.94, (0.46, 1.00, -0.52), (0.16, 0.10, -0.98)),
            (1.14, (0.62, 1.08, -0.20), (0.36, 0.48, -0.80)),
        ], twist=[(0.00, -8), (0.18, -18), (0.54, 2), (0.76, 8), (1.14, -8)],
           lean=[(0.18, -16), (0.64, 30), (0.76, 28)], crouch=[(0.64, -0.32), (0.76, -0.28)],
           step=[(0.00, -0.2), (0.18, -0.85), (0.44, 0.3), (0.64, 0.95), (0.94, 0.4), (1.14, -0.2)]),
    ],
}

if ONLY:
    MOVESETS = {k: v for k, v in MOVESETS.items() if k == ONLY}




# ---------------------------------------------------------------------------
# STANCES AND WALK CYCLES  (docs/STANCES_AND_CARRY.md)
# ---------------------------------------------------------------------------
# A stance says what someone is holding before they ever attack. A walk cycle
# says how much it weighs. Both LOOP, so the first and last pose must be
# identical or the cycle pops once per revolution.
#
#   carry   (wrist, blade direction) - the held pose
#   stride  degrees the legs swing; heavy carries take fewer, longer steps
#   bob     studs the hips drop at contact (weight landing)
#   lean    forward pitch; a drag leans into the weight it is hauling
#   sway    how much the weapon rocks with the stride

STANCES = {
    # Berserker: the axe is too heavy to carry, so he doesn't. It hangs from
    # the right hand with the head dragging on the ground behind him.
    "Greataxe": dict(
        carry=((0.66, 0.42, 0.46), (0.06, -0.72, 0.69)),
        idle=dict(lean=8, twist=-10, settle=0.05),
        walk=dict(stride=26, bob=0.16, lean=17, sway=0.09, period=1.10),
    ),
    # Assassin: both blades held, low and compact. Nothing is heavy.
    "Dagger": dict(
        carry=((0.58, 0.82, -0.44), (0.34, 0.30, -0.89)),
        idle=dict(lean=4, twist=-14, settle=0.03),
        walk=dict(stride=34, bob=0.09, lean=6, sway=0.05, period=0.78),
    ),
    # Swordsman: balanced middle guard - the readable baseline.
    "Sword": dict(
        carry=((0.68, 0.96, -0.34), (0.26, 0.74, -0.62)),
        idle=dict(lean=3, twist=-10, settle=0.035),
        walk=dict(stride=30, bob=0.11, lean=8, sway=0.06, period=0.88),
    ),
    # Paladin: walks behind the shield, weight on the back foot.
    "PaladinBlade": dict(
        carry=((0.72, 0.74, 0.30), (0.42, 0.34, 0.84)),
        idle=dict(lean=5, twist=18, settle=0.03),
        walk=dict(stride=24, bob=0.12, lean=10, sway=0.04, period=1.00),
    ),
    # King: blade on the shoulder, unhurried. Arrogance is the read.
    "RoyalBlade": dict(
        carry=((0.74, 1.16, 0.26), (0.34, 0.62, 0.71)),
        idle=dict(lean=-2, twist=-8, settle=0.04),
        walk=dict(stride=28, bob=0.10, lean=2, sway=0.05, period=0.94),
    ),

    # Archer: bow carried across the body, never drawn until it is needed.
    "Bow": dict(
        carry=((0.54, 0.88, -0.40), (0.26, 0.90, -0.34)),
        left=((-22, 0, 20), (-34, 0, 0)),
        idle=dict(lean=2, twist=-8, settle=0.03),
        walk=dict(stride=32, bob=0.10, lean=5, sway=0.05, period=0.86),
    ),
    # Musketeer: cradled in both arms, muzzle up and away from everyone.
    "Musket": dict(
        carry=((0.90, 0.92, -0.24), (0.30, 0.56, -0.77)),
        idle=dict(lean=3, twist=-10, settle=0.03),
        walk=dict(stride=28, bob=0.11, lean=7, sway=0.05, period=0.92),
    ),
    # Necromancer: staff planted like a walking stick. The only class whose
    # walk should look AIDED rather than encumbered.
    "NecroStaff": dict(
        carry=((0.78, 0.86, -0.06), (0.10, 0.98, 0.14)),
        idle=dict(lean=2, twist=6, settle=0.035),
        walk=dict(stride=26, bob=0.10, lean=4, sway=0.07, period=0.98),
    ),
    "Greatsword": dict(
        carry=((0.62, 1.14, 0.22), (-0.10, 0.70, 0.71)),
        idle=dict(lean=6, twist=-8, settle=0.04),
        walk=dict(stride=25, bob=0.14, lean=13, sway=0.07, period=1.05),
    ),
}


def stance_legs(weight, sink):
    """Leg angles for a weight shift: back foot drives, front foot plants.

    Returns (rightUpper, rightLower, leftUpper, leftLower).
    """
    # Left leads, right drives - the swing is thrown off the back foot.
    lu = -6 + 26 * weight + sink * 24
    ll = 10 + 16 * abs(weight) - sink * 30
    ru = -8 - 24 * weight + sink * 32
    rl = 12 + 20 * abs(weight) - sink * 38
    return ru, rl, lu, ll


def leg_cycle(phase, stride, bob):
    """Contact, passing, contact, passing - with real weight transfer.

    Returns (rightUpper, rightLower, leftUpper, leftLower, hipDrop). Feet that
    do not push off read as sliding no matter how good the upper body is.
    """
    import math as _m
    a = phase * 2 * _m.pi
    swing_r = _m.sin(a)
    swing_l = _m.sin(a + _m.pi)
    # Knees bend on the passing pose and straighten at contact.
    bend_r = max(0.0, -_m.cos(a))
    bend_l = max(0.0, -_m.cos(a + _m.pi))
    # Hips drop twice per stride, once per foot landing.
    drop = -bob * (0.5 + 0.5 * _m.cos(2 * a))
    return (-stride * swing_r, stride * 0.9 * bend_r,
            -stride * swing_l, stride * 0.9 * bend_l, drop)


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
        "(reach=%.3f expected ~1.73, shoulderY=%.2f expected ~0.85). "
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
    _QPREV.clear()
    if BLEND:
        return
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


# QUATERNION CONTINUITY.
#
#   A quaternion and its negation describe the SAME orientation, so nothing
#   about a pose is wrong if consecutive keys land in opposite hemispheres -
#   but the F-curve interpolates componentwise, and between q and -q that is
#   the long way round: an almost full revolution between two keys.
#
#   That is what "massive jumps between frames" and the blade passing through
#   his own head actually were. Not too few keys - the wrong ARC between them.
#   Adding beats could never have fixed it.
#
#   Fix: before keying, flip the sign if it opposes the previous key on that
#   same channel, so successive keys always take the short path.
_QPREV = {}


def key_quat(target, channel_key, frame):
    q = target.rotation_quaternion
    prev = _QPREV.get(channel_key)
    if prev and (q.w * prev[0] + q.x * prev[1] + q.y * prev[2] + q.z * prev[3]) < 0:
        target.rotation_quaternion = (-q.w, -q.x, -q.y, -q.z)
        q = target.rotation_quaternion
    _QPREV[channel_key] = (q.w, q.x, q.y, q.z)
    target.keyframe_insert("rotation_quaternion", frame=frame)


def key_pose(bone, T, frame):
    p = pb[bone]
    p.rotation_mode = "QUATERNION"
    C = CONV[bone].to_4x4()
    p.matrix_basis = C.inverted() @ T @ C
    key_quat(p, "bone:" + bone, frame + FRAME_OFFSET)
    p.keyframe_insert("location", frame=frame + FRAME_OFFSET)


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


def box(name, size, color):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.color = color
    return o


BODY = (0.62, 0.63, 0.68, 1)
RIGHT = (0.20, 0.45, 0.95, 1)
LEFT = (0.20, 0.80, 0.35, 1)
LEG = (0.45, 0.46, 0.52, 1)


def tone(p):
    if "Leg" in p or "Foot" in p:
        return LEG
    if p.startswith("Right") and ("Arm" in p or "Hand" in p):
        return RIGHT
    if p.startswith("Left") and ("Arm" in p or "Hand" in p):
        return LEFT
    return BODY


preview_parts = {p: box("m_" + p, PARTS[p]["Size"], tone(p)) for p in order}
# Weapon proxy: a rod along the haft plus a stub guard, enough to read which
# way the blade is pointing at any frame.
blade_proxy = box("w_blade", (0.14, 4.4, 0.5), (0.85, 0.45, 0.15, 1))
guard_proxy = box("w_guard", (0.16, 0.16, 1.1), (0.55, 0.35, 0.15, 1))

GROUND_Y = rest_part["RightFoot"].translation.y - PARTS["RightFoot"]["Size"][1] / 2
ground = box("ground", (9, 0.08, 9), (0.80, 0.81, 0.83, 1))
ground.matrix_basis = (Matrix.Translation((0, GROUND_Y, 0))
                       @ Matrix.Diagonal(Vector((9, 0.08, 9)).to_4d()))

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 11.0
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam


def look_at(loc, target, up=Vector((0, 1, 0))):
    """Explicit up axis: this scene is Y-up (Roblox), and to_track_quat
    resolves against Blender's world +Z, which rolls the camera 90 degrees."""
    f = (Vector(target) - Vector(loc)).normalized()
    r = f.cross(up).normalized()
    u = r.cross(f)
    return Matrix(((r.x, u.x, -f.x, loc[0]), (r.y, u.y, -f.y, loc[1]),
                   (r.z, u.z, -f.z, loc[2]), (0, 0, 0, 1)))


cam.matrix_world = look_at(Vector((6.5, 2.2, -6.5)), Vector((0, 0.2, -0.2)))
scene.render.engine = "BLENDER_WORKBENCH"
sh = scene.display.shading
sh.light, sh.color_type, sh.show_shadows = "STUDIO", "OBJECT", False
scene.render.resolution_x = scene.render.resolution_y = 420

for wname, clips in MOVESETS.items():
    spec = WEAPONS[wname]
    out["Movesets"][wname] = {}

    for clip in clips:
        clear_pose()
        if BLEND and SHARED.get("ctl"):
            wctl, k_right = SHARED["ctl"], SHARED["k_right"]
        else:
            wctl = bpy.data.objects.new("WeaponCtl", None)
            scene.collection.objects.link(wctl)
            grip_rel, k_right, rt, lt = build_targets(spec, wctl)
            SHARED["ctl"], SHARED["k_right"] = wctl, k_right

        beats = clip["Beats"]
        dur = beats[-1][0]
        scene.frame_start, scene.frame_end = 0, round(dur * FPS)

        wctl.rotation_mode = "QUATERNION"
        over = []
        for (t, wrist, direction) in beats:
            f = round(t * FPS)
            wctl.matrix_basis = weapon_matrix(wrist, direction, k_right)
            wctl.keyframe_insert("location", frame=f + FRAME_OFFSET)
            key_quat(wctl, "wctl", f + FRAME_OFFSET)
            d = (Vector(wrist) - rest_frame["RightUpperArm"].translation).length
            if d > REACH * spec.get("reachMul", 1.0):
                over.append("t=%.2f right=%.2f" % (t, d))

        # Torso, hips and legs carry the swing; keyed from the twist/lean track.
        for (t, _w, _d) in beats:
            f = round(t * FPS)
            yaw = lerp_at(clip["Twist"], t)
            lean = lerp_at(clip["Lean"], t)
            sink = lerp_at(clip["Crouch"], t)
            weight = lerp_at(clip["Step"], t)
            key_pose("LowerTorso", Matrix.Translation((0, sink, 0)) @ angles(lean * 0.3, yaw * 0.45, 0), f)
            key_pose("UpperTorso", angles(lean * 0.7, yaw * 0.85, -yaw * 0.12), f)
            key_pose("Head", angles(0, -yaw * 0.35, 0), f)
            if clip["Legs"]:
                ru, rl, lu, ll = stance_legs(weight, sink)
                key_pose("RightUpperLeg", angles(ru, 0, 0), f)
                key_pose("RightLowerLeg", angles(rl, 0, 0), f)
                key_pose("LeftUpperLeg", angles(lu, 0, 0), f)
                key_pose("LeftLowerLeg", angles(ll, 0, 0), f)
            if clip["Left"]:
                #[ An explicit off-hand track. A bow DRAW is not a
                #  counterbalance - the free hand is doing the work and has to
                #  be keyed as deliberately as the weapon itself. ]
                lua = [lerp_at([(k[0], k[1][i]) for k in clip["Left"]], t) for i in range(3)]
                lla = [lerp_at([(k[0], k[2][i]) for k in clip["Left"]], t) for i in range(3)]
                key_pose("LeftUpperArm", angles(lua[0], lua[1], lua[2]), f)
                key_pose("LeftLowerArm", angles(lla[0], lla[1], lla[2]), f)
            elif not spec.get("two"):
                # Free hand counterbalances the swing instead of gripping.
                key_pose("LeftUpperArm", angles(-18 - yaw * 0.9, 0, 22 + yaw * 0.5), f)
                key_pose("LeftLowerArm", angles(-26 - abs(yaw) * 0.5, 0, 0), f)

        # ---- evaluate, verify, export ----
        dg = bpy.context.evaluated_depsgraph_get()
        frames = []
        worst = 0.0
        #[[ Two things a contact sheet cannot show, both reported by feedback:
        #
        #   step  - how far the blade tip travels in ONE frame. A big number is
        #           the "massive jump" you see when a huge rotation is spread
        #           over three or four frames; the eye reads it as a cut.
        #   head  - closest the weapon SEGMENT (grip to tip) comes to the head.
        #           Specifying only endpoints lets the interpolated arc pass
        #           straight through the skull, which no pose check catches.
        #
        #   Measure them, do not hope. ]]
        prev_tip = None
        steps = []
        min_head = 9e9
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

            wm = wctl.matrix_world
            grip_pt = wm.translation
            tip_pt = (wm @ Matrix.Translation((0, 4.4, 0))).translation
            if prev_tip is not None:
                steps.append((tip_pt - prev_tip).length)
            prev_tip = tip_pt

            head_pt = pw["Head"].translation
            seg = tip_pt - grip_pt
            L2 = seg.dot(seg)
            t = 0.0 if L2 < 1e-9 else max(0.0, min(1.0, (head_pt - grip_pt).dot(seg) / L2))
            min_head = min(min_head, (head_pt - (grip_pt + seg * t)).length)

        # Render this clip's beats so the swing can be judged before upload.
        for idx, (t, _w, _d) in enumerate(beats):
            scene.frame_set(round(t * FPS))
            dg.update()
            F = {p: pb[p].matrix.copy() @ CONV[p].inverted().to_4x4() for p in order}
            for p, o in preview_parts.items():
                o.matrix_world = F[p] @ A1[p].inverted()
                o.scale = Vector(PARTS[p]["Size"])
            wm = wctl.matrix_world.copy()
            blade_proxy.matrix_world = wm @ Matrix.Translation((0, 2.2, 0))
            blade_proxy.scale = Vector((0.14, 4.4, 0.5))
            guard_proxy.matrix_world = wm @ Matrix.Translation((0, 0.05, 0))
            guard_proxy.scale = Vector((0.16, 0.16, 1.1))
            scene.render.filepath = os.path.join(
                RENDER_DIR, "%s_%s_%d.png" % (wname, clip["Name"], idx))
            bpy.ops.render.render(write_still=True)

        out["Movesets"][wname][clip["Name"]] = {"Duration": dur, "Frames": frames}
        #[[ A fast swing SHOULD move fast; what reads as a jump is a
        #   DISCONTINUITY - one frame stepping far further than its
        #   neighbours. So compare the worst step against the typical one
        #   rather than against an absolute speed. ]]
        ordered = sorted(steps)
        median = ordered[len(ordered) // 2] if ordered else 0.0
        max_step = max(steps) if steps else 0.0
        ratio = (max_step / median) if median > 1e-6 else 0.0
        report.append((wname, clip["Name"], dur, len(frames), worst, over,
                       max_step, min_head, ratio))
        if BLEND:
            MARKERS.append((FRAME_OFFSET, clip["Name"]))
            FRAME_OFFSET += round(dur * FPS) + 8

        if not BLEND:
            bpy.data.objects.remove(wctl, do_unlink=True)

stance_report = []

# ---------------------------------------------------------------------------
# build the looping stances and walks
# ---------------------------------------------------------------------------
STANCE_FPS = FPS
out["Stances"] = {}

for wname, spec in STANCES.items():
    if ONLY and wname != ONLY:
        continue
    wspec = WEAPONS[wname]
    (wrist, wdir) = spec["carry"]
    out["Stances"][wname] = {}

    for kind in ("Idle", "Walk"):
        clear_pose()
        if BLEND and SHARED.get("ctl"):
            wctl, k_right = SHARED["ctl"], SHARED["k_right"]
        else:
            wctl = bpy.data.objects.new("WeaponCtl", None)
            scene.collection.objects.link(wctl)
            grip_rel, k_right, rt, lt = build_targets(wspec, wctl)
            SHARED["ctl"], SHARED["k_right"] = wctl, k_right

        if kind == "Idle":
            cfg = spec["idle"]
            dur = 2.4                       # slow breathing loop
            phases = [0.0, 0.5, 1.0]
        else:
            cfg = spec["walk"]
            dur = cfg["period"]
            phases = [0.0, 0.25, 0.5, 0.75, 1.0]

        scene.frame_start, scene.frame_end = 0, round(dur * STANCE_FPS)
        wctl.rotation_mode = "QUATERNION"

        for ph in phases:
            f = round(ph * dur * STANCE_FPS)
            if kind == "Idle":
                # Breathe: the whole carry rises and settles a few centimetres.
                rise = cfg["settle"] * math.sin(ph * 2 * math.pi)
                w = (wrist[0], wrist[1] + rise, wrist[2])
                lean, twist = cfg["lean"], cfg["twist"]
                ru, rl, lu, ll, drop = -6, 8, -4, 6, rise * 0.5
            else:
                sway = cfg["sway"] * math.sin(ph * 2 * math.pi)
                w = (wrist[0] + sway * 0.5, wrist[1] + sway, wrist[2] - sway * 0.4)
                lean = cfg["lean"]
                twist = -10 * math.sin(ph * 2 * math.pi)
                ru, rl, lu, ll, drop = leg_cycle(ph, cfg["stride"], cfg["bob"])

            wctl.matrix_basis = weapon_matrix(w, wdir, k_right)
            wctl.keyframe_insert("location", frame=f + FRAME_OFFSET)
            key_quat(wctl, "wctl", f + FRAME_OFFSET)

            key_pose("LowerTorso", Matrix.Translation((0, drop, 0))
                     @ angles(lean * 0.3, twist * 0.4, 0), f)
            key_pose("UpperTorso", angles(lean * 0.7, twist * 0.8, 0), f)
            key_pose("Head", angles(-lean * 0.4, -twist * 0.3, 0), f)
            key_pose("RightUpperLeg", angles(ru, 0, 0), f)
            key_pose("RightLowerLeg", angles(rl, 0, 0), f)
            key_pose("LeftUpperLeg", angles(lu, 0, 0), f)
            key_pose("LeftLowerLeg", angles(ll, 0, 0), f)
            if spec.get("left"):
                #[ A held off-hand pose: the archer's string hand at the hip,
                #  not a swinging counterbalance. ]
                lua, lla = spec["left"]
                key_pose("LeftUpperArm", angles(lua[0], lua[1], lua[2]), f)
                key_pose("LeftLowerArm", angles(lla[0], lla[1], lla[2]), f)
            elif not wspec.get("two"):
                # Free hand: relaxed and counterbalancing, or holding the
                # second dagger in a low icepick guard.
                if wname == "Dagger":
                    key_pose("LeftUpperArm", angles(-34, 0, 16), f)
                    key_pose("LeftLowerArm", angles(-52, 0, 0), f)
                else:
                    key_pose("LeftUpperArm", angles(-12 - abs(twist) * 0.4, 0, 18), f)
                    key_pose("LeftLowerArm", angles(-24, 0, 0), f)

        dg = bpy.context.evaluated_depsgraph_get()
        frames, worst, ground_lo = [], 0.0, 9e9
        for fnum in range(scene.frame_start, scene.frame_end + 1):
            scene.frame_set(fnum)
            dg.update()
            pose_world = {p: pb[p].matrix.copy() for p in order}
            basis = {}
            for p in order:
                par = PARENT.get(p)
                rest_local = (arm_data.bones[p].matrix_local if par is None else
                              arm_data.bones[par].matrix_local.inverted() @ arm_data.bones[p].matrix_local)
                pp = pose_world[par] if par else Matrix.Identity(4)
                basis[p] = rest_local.inverted() @ pp.inverted() @ pose_world[p]

            rec = {"T": round(fnum / STANCE_FPS, 4), "Joints": {}}
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
            # Where does the weapon tip sit? The drag only reads if the axe
            # head is actually ON the floor.
            tip = (wctl.matrix_world @ Matrix.Translation((0, 4.4, 0))).translation
            ground_lo = min(ground_lo, tip.y)

        for idx, ph in enumerate(phases[:-1]):
            scene.frame_set(round(ph * dur * STANCE_FPS))
            dg.update()
            Fp = {p: pb[p].matrix.copy() @ CONV[p].inverted().to_4x4() for p in order}
            for p, o in preview_parts.items():
                o.matrix_world = Fp[p] @ A1[p].inverted()
                o.scale = Vector(PARTS[p]["Size"])
            wm = wctl.matrix_world.copy()
            blade_proxy.matrix_world = wm @ Matrix.Translation((0, 2.2, 0))
            blade_proxy.scale = Vector((0.14, 4.4, 0.5))
            guard_proxy.matrix_world = wm @ Matrix.Translation((0, 0.05, 0))
            guard_proxy.scale = Vector((0.16, 0.16, 1.1))
            scene.render.filepath = os.path.join(
                RENDER_DIR, "STANCE_%s_%s_%d.png" % (wname, kind, idx))
            bpy.ops.render.render(write_still=True)

        out["Stances"][wname][kind] = {"Duration": dur, "Frames": frames}
        stance_report.append((wname, kind, dur, len(frames), worst, ground_lo))
        if BLEND:
            MARKERS.append((FRAME_OFFSET, wname + "_" + kind))
            FRAME_OFFSET += round(dur * STANCE_FPS) + 8
        if not BLEND:
            bpy.data.objects.remove(wctl, do_unlink=True)

GROUND = rest_part["RightFoot"].translation.y - PARTS["RightFoot"]["Size"][1] / 2
print("")
print("%-13s %-6s %5s %6s %11s %s" % ("WEAPON", "KIND", "DUR", "FRAMES", "REPLAY-ERR", "TIP-vs-GROUND"))
for wname, kind, dur, n, worst, lo in stance_report:
    gap = lo - GROUND
    note = ""
    if wname == "Greataxe" and kind == "Walk":
        note = "DRAGGING" if abs(gap) < 0.45 else ("floating %.2f" % gap if gap > 0 else "through floor %.2f" % gap)
    print("%-13s %-6s %5.2f %6d %11.6f  %+.2f %s"
          % (wname, kind, dur, n, worst, gap, note))


#[[ A --blend run is filtered to ONE weapon. Writing the shared export from
#   it would silently replace all eighteen clips with that weapon's two or
#   three - which is exactly what happened, and the upload step found a
#   three-clip file where it expected eighteen. Blend runs are for viewing;
#   only a full run publishes. ]]
if not BLEND:
    json.dump(out, open(OUT_POSES, "w"))

print("\n%-13s %-20s %5s %6s %11s %s" % ("WEAPON", "CLIP", "DUR", "FRAMES", "REPLAY-ERR", "REACH"))
bad = 0
HEAD_R = PARTS["Head"]["Size"][1] / 2 + 0.15
for wname, cname, dur, n, worst, over, step, head, ratio in report:
    if worst >= 1e-3:
        bad += 1
    notes = []
    if worst >= 1e-3:
        notes.append("BAD MATHS")
    #[ A swing has anticipation, a fast strike and a slow recovery, so its
    #  peak frame is naturally ~3x the median. Only a genuine discontinuity
    #  runs far past that; the broken clips measured x5 to x12.5. ]
    if ratio > 4.5:
        notes.append("JUMPY(x%.1f)" % ratio)
    if head < HEAD_R:
        notes.append("THROUGH HEAD")
    if over:
        notes.append("OVER-REACH")
    print("%-13s %-18s %5.2f %9.2f %6.1f %7.2f %s"
          % (wname, cname, dur, step, ratio, head, " ".join(notes)))
print("\nARM REACH %.3f studs   clips=%d   maths-failures=%d" % (REACH, len(report), bad))
print("WROTE %s" % OUT_POSES)

if BLEND:
    #[[ Hand over something editable, not just renders.
    #
    #   Preview meshes track the rig with Child Of constraints rather than
    #   baked keyframes, so editing a pose updates the body live.
    #
    #   Everything hangs off one root rotated 90 degrees about X: the scene is
    #   authored Y-up (Roblox), and Blender navigates Z-up, so without this the
    #   whole rig lies on its side and orbiting feels wrong. It is purely
    #   cosmetic - pose_bone.matrix is read in ARMATURE space, so the exported
    #   animation is identical either way. ]]
    for p, o in preview_parts.items():
        o.animation_data_clear()
        c = o.constraints.new("CHILD_OF")
        c.target = arm_obj
        c.subtarget = p
        c.inverse_matrix = arm_data.bones[p].matrix_local.inverted()
        o.matrix_basis = rest_part[p] @ Matrix.Diagonal(Vector(PARTS[p]["Size"]).to_4d())

    for proxy, off, size in ((blade_proxy, 2.2, (0.14, 4.4, 0.5)),
                             (guard_proxy, 0.05, (0.16, 0.16, 1.1))):
        proxy.animation_data_clear()
        proxy.parent = wctl
        proxy.matrix_parent_inverse = Matrix.Identity(4)
        proxy.matrix_basis = (Matrix.Translation((0, off, 0))
                              @ Matrix.Diagonal(Vector(size).to_4d()))

    for frame, name in MARKERS:
        scene.timeline_markers.new(name, frame=frame)

    root = bpy.data.objects.new("RIG_ROOT", None)
    root.empty_display_size = 0.6
    scene.collection.objects.link(root)
    root.rotation_euler = (math.radians(90), 0, 0)
    for obj in (arm_obj, wctl, ground, cam):
        obj.parent = root
        obj.matrix_parent_inverse = Matrix.Identity(4)

    scene.frame_start, scene.frame_end = 0, max(FRAME_OFFSET - 8, 1)
    scene.frame_set(0)
    path = os.path.join(HERE, "blend", BLEND + ".blend")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print("SAVED %s  (%d frames, %d markers)" % (path, scene.frame_end, len(MARKERS)))
    for frame, name in MARKERS:
        print("    frame %4d  %s" % (frame, name))
