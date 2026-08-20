"""
Procedural weapon meshes for every class, built in Blender.

WHY BLENDER AND NOT THE OBJ SWEEPER
-----------------------------------
tools/GenerateWeaponMesh.py writes OBJ vertex arithmetic by hand. That gets
tapered blades, but it cannot bevel, solidify or smooth-shade. Blender gives
those as modifiers, which is most of the difference between "a shape" and
something that reads as a weapon.

CONVENTIONS THAT MATTER
-----------------------
* Origin at the GRIP, weapon running up +Z (Blender). The OBJ exporter's
  default axes (forward -Z, up +Y) turn that into +Y in Roblox, which is what
  WeaponModels and Tool.Grip already assume - so GetGripOffset carries over
  untouched and none of the animation work has to change.
* Dimensions are copied from WeaponModels.luau. Reach is a GAMEPLAY number: a
  prettier greataxe that is 20% shorter silently changes how the class plays,
  and every swing animation was authored against these lengths.

USAGE
    blender --background --python tools/blender_weapons.py
writes tools/meshes/<name>.obj and tools/meshes/preview.png
"""
import bpy, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "meshes")
os.makedirs(OUT, exist_ok=True)

TAU = math.pi * 2

STEEL = (0.78, 0.80, 0.85, 1)
DARK = (0.20, 0.20, 0.24, 1)
WOOD = (0.42, 0.28, 0.16, 1)
GOLD = (0.92, 0.76, 0.32, 1)


# ---------------------------------------------------------------------------
# mesh helpers
# ---------------------------------------------------------------------------

def circle(r, n=16):
    return [(r * math.cos(i * TAU / n), r * math.sin(i * TAU / n)) for i in range(n)]


def diamond(w, t):
    """Blade section: wide edge-to-edge, thin flat-to-flat, with a raised spine."""
    return [(w, 0), (w * 0.45, t), (0, t * 0.78), (-w * 0.45, t),
            (-w, 0), (-w * 0.45, -t), (0, -t * 0.78), (w * 0.45, -t)]


def ring(profile, z, sx=1.0, sy=1.0, dy=0.0):
    return [(x * sx, y * sy + dy, z) for (x, y) in profile]


def loft(name, rings, cap_a=True, cap_b=True):
    """Skin a stack of equal-length rings. Every blade and shaft is one of these."""
    n = len(rings[0])
    verts, faces = [], []
    for r in rings:
        verts.extend(r)
    for i in range(len(rings) - 1):
        a, b = i * n, (i + 1) * n
        for j in range(n):
            k = (j + 1) % n
            faces.append((a + j, a + k, b + k, b + j))
    if cap_a:
        faces.append(tuple(range(n - 1, -1, -1)))
    if cap_b:
        base = len(verts) - n
        faces.append(tuple(base + j for j in range(n)))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def plate(name, pts_yz, thickness, x=0.0):
    """A flat outline in the YZ plane, given real thickness.

    Axe heads, shield faces and bow limbs are silhouettes; drawing the outline
    and solidifying it beats trying to loft a crescent.
    """
    verts = [(x, p[0], p[1]) for p in pts_yz]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], [tuple(range(len(verts)))])
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    m = ob.modifiers.new("sol", "SOLIDIFY")
    m.thickness = thickness
    m.offset = 0
    return ob


def bevel(ob, width=0.012, segments=2, angle=48):
    m = ob.modifiers.new("bev", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    return ob


def box(name, sx, sy, sz, z, y=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, y, z))
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (sx, sy, sz)
    return ob


def orb(name, z, r, y=0.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=r, location=(0, y, z))
    ob = bpy.context.active_object
    ob.name = name
    return ob


def finish(name, objs, color):
    """Apply modifiers, join, smooth-shade and colour."""
    for o in objs:
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception:
                o.modifiers.remove(m)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    ob.color = color
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(38))
    except Exception:
        bpy.ops.object.shade_smooth()
    return ob


# ---------------------------------------------------------------------------
# shared components
# ---------------------------------------------------------------------------

def grip(length=1.2, r=0.15, wraps=4):
    """Handle with a slight hourglass and wrap ridges, centred on the origin."""
    prof = circle(1.0, 14)
    z0, z1 = -length / 2, length / 2
    stations = []
    steps = 18
    for i in range(steps + 1):
        t = i / steps
        waist = 1.0 - 0.13 * math.sin(t * math.pi)
        ridge = 1.0 + 0.06 * (1 if int(t * wraps * 2) % 2 else 0)
        s = r * waist * ridge
        stations.append(ring(prof, z0 + (z1 - z0) * t, s, s))
    return bevel(loft("Grip", stations), 0.006)


def pommel(z, r=0.2):
    prof = circle(1.0, 14)
    stations = []
    steps = 10
    for i in range(steps + 1):
        t = i / steps
        s = max(r * math.sin(max(t, 0.001) * math.pi) ** 0.55, 0.02)
        stations.append(ring(prof, z - r + 2 * r * t, s, s))
    return bevel(loft("Pommel", stations), 0.008)


def blade(name, z0, length, half_w, half_t, tip_len, taper=0.72):
    """Tapered diamond-section blade ending in a real point."""
    stations = []
    body = length - tip_len
    steps = 8
    for i in range(steps + 1):
        t = i / steps
        w = half_w * (1.0 - (1.0 - taper) * t)
        th = half_t * (1.0 - 0.32 * t)
        stations.append(ring(diamond(w, th), z0 + body * t))
    for i in range(1, 6):
        t = i / 5
        w = max(half_w * taper * (1 - t) ** 0.75, 0.004)
        th = max(half_t * 0.62 * (1 - t) ** 0.75, 0.003)
        stations.append(ring(diamond(w, th), z0 + body + tip_len * t))
    return bevel(loft(name, stations), 0.005)


def crossguard(name, z, span, thick, deep, droop=0.0):
    """Guard swept along Y, tapering to the tips."""
    stations = []
    steps = 12
    for i in range(steps + 1):
        t = -1 + 2 * i / steps
        y = span * t
        w = thick * (1.0 - 0.42 * abs(t))
        d = deep * (1.0 - 0.28 * abs(t))
        stations.append([(px * w, y, pz * d + z + droop * t * t)
                         for (px, pz) in [(1, 1), (-1, 1), (-1, -1), (1, -1)]])
    n = 4
    verts, faces = [], []
    for s in stations:
        verts.extend(s)
    for i in range(len(stations) - 1):
        a, b = i * n, (i + 1) * n
        for j in range(n):
            k = (j + 1) % n
            faces.append((a + j, a + k, b + k, b + j))
    faces.append(tuple(range(n - 1, -1, -1)))
    faces.append(tuple(len(verts) - n + j for j in range(n)))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return bevel(ob, 0.016)


def shaft(name, z0, length, r, taper=0.88):
    prof = circle(1.0, 12)
    stations = []
    steps = 10
    for i in range(steps + 1):
        t = i / steps
        s = r * (1.0 - (1.0 - taper) * t)
        stations.append(ring(prof, z0 + length * t, s, s))
    return bevel(loft(name, stations), 0.006)


# ---------------------------------------------------------------------------
# weapons  (dimensions mirror WeaponModels.luau)
# ---------------------------------------------------------------------------

def w_sword():
    parts = [grip(1.0, 0.13), pommel(-0.56, 0.19),
             crossguard("Guard", 0.55, 0.85, 0.14, 0.12, droop=-0.10),
             blade("Blade", 0.62, 4.2, 0.35, 0.11, 1.05, taper=0.52)]
    return finish("Sword", parts, STEEL)


def w_greatsword():
    parts = [grip(1.5, 0.16, 5), pommel(-0.84, 0.25),
             crossguard("Guard", 0.80, 1.30, 0.20, 0.16, droop=-0.16),
             blade("Blade", 0.90, 6.3, 0.62, 0.15, 1.55, taper=0.54)]
    return finish("Greatsword", parts, STEEL)


def w_dagger():
    parts = [grip(0.62, 0.10, 3), pommel(-0.36, 0.12),
             crossguard("Guard", 0.34, 0.42, 0.09, 0.08),
             blade("Blade", 0.40, 1.86, 0.21, 0.065, 0.60, taper=0.56)]
    return finish("Dagger", parts, STEEL)


def w_paladinblade():
    parts = [grip(1.05, 0.135), pommel(-0.58, 0.21)]
    # Winged guard: two swept plates instead of a bar.
    for s in (1, -1):
        wing = plate("Wing", [(0.05 * s, 0.44), (0.42 * s, 0.60), (0.46 * s, 0.86),
                              (0.16 * s, 0.78), (0.05 * s, 0.62)], 0.16)
        parts.append(bevel(wing, 0.02))
    parts.append(crossguard("Guard", 0.56, 0.50, 0.15, 0.13))
    parts.append(blade("Blade", 0.64, 4.3, 0.42, 0.115, 1.15, taper=0.50))
    return finish("PaladinBlade", parts, GOLD)


def w_royalblade():
    parts = [grip(1.05, 0.135), pommel(-0.58, 0.22),
             crossguard("Guard", 0.58, 0.95, 0.16, 0.13, droop=0.12),
             blade("Blade", 0.66, 4.6, 0.40, 0.12, 1.20, taper=0.52),
             orb("Gem", 0.50, 0.15)]
    # Crown points along the guard, the King's silhouette read.
    for i, y in enumerate((-0.62, -0.21, 0.21, 0.62)):
        parts.append(bevel(box("Crown%d" % i, 0.06, 0.07, 0.13, 0.70, y), 0.02))
    return finish("RoyalBlade", parts, GOLD)


def w_greataxe():
    parts = [shaft("Haft", -0.6, 4.9, 0.13, 0.92), grip(1.1, 0.15, 4)]
    # Twin crescent heads, mirrored across the haft.
    for s in (1, -1):
        # An axe bit attaches NARROW at the haft and flares outward to a
        # convex cutting edge. Both earlier versions flared the other way,
        # which is why they read as arrow fletching rather than an axe.
        head = plate("Head", [(0.14 * s, 4.16), (0.68 * s, 4.42), (1.20 * s, 4.54),
                              (1.58 * s, 4.12), (1.68 * s, 3.66), (1.56 * s, 3.20),
                              (1.16 * s, 2.82), (0.66 * s, 2.94), (0.14 * s, 3.22)], 0.26)
        parts.append(bevel(head, 0.035, 2))
    parts.append(bevel(box("Collar", 0.11, 0.11, 0.16, 3.05), 0.03))
    # Spike on top, so the overhead slam has a point leading it.
    spike = loft("Spike", [ring(circle(1.0, 8), 4.24, 0.09, 0.09),
                           ring(circle(1.0, 8), 4.62, 0.06, 0.06),
                           ring(circle(1.0, 8), 4.92, 0.012, 0.012)])
    parts.append(bevel(spike, 0.006))
    return finish("Greataxe", parts, STEEL)


def w_bow():
    parts = []
    # Recurve limbs: a swept plate per side, curving back at the tips.
    for s in (1, -1):
        pts = []
        for i in range(9):
            t = i / 8
            z = s * (0.10 + 2.9 * t)
            y = 0.42 * math.sin(t * math.pi * 0.92) - 0.30 * t * t
            pts.append((y, z))
        for i in range(8, -1, -1):
            t = i / 8
            z = s * (0.10 + 2.9 * t)
            y = 0.42 * math.sin(t * math.pi * 0.92) - 0.30 * t * t
            w = 0.22 * (1 - 0.68 * t)
            pts.append((y - w, z))
        parts.append(bevel(plate("Limb", pts, 0.22), 0.02))
    parts.append(grip(1.0, 0.12, 3))
    # String, tip to tip.
    string = loft("String", [ring(circle(1.0, 6), -3.0, 0.03, 0.03, -0.30),
                             ring(circle(1.0, 6), 0.0, 0.03, 0.03, -0.30),
                             ring(circle(1.0, 6), 3.0, 0.03, 0.03, -0.30)])
    parts.append(string)
    return finish("Bow", parts, WOOD)


def w_musket():
    # Shouldered stock: comb rising to the breech, angled butt plate.
    stock = plate("Stock", [(0.10, 0.34), (0.38, -0.12), (0.44, -0.88), (0.30, -1.30),
                            (-0.20, -1.18), (-0.24, -0.46), (-0.13, 0.24)], 0.34)
    parts = [bevel(stock, 0.05),
             shaft("Barrel", 0.60, 3.5, 0.10, 0.90),
             bevel(box("Lock", 0.13, 0.16, 0.30, 0.55), 0.03),
             bevel(box("Band", 0.13, 0.13, 0.10, 2.20), 0.03)]
    muzzle = loft("Muzzle", [ring(circle(1.0, 12), 4.05, 0.11, 0.11),
                             ring(circle(1.0, 12), 4.22, 0.13, 0.13),
                             ring(circle(1.0, 12), 4.30, 0.12, 0.12)])
    parts.append(bevel(muzzle, 0.01))
    # Ramrod tucked under the barrel.
    parts.append(shaft("Ramrod", 0.90, 2.6, 0.03, 1.0))
    return finish("Musket", parts, DARK)


def w_necrostaff():
    parts = [shaft("Shaft", -0.7, 4.5, 0.11, 0.92), grip(1.0, 0.13, 4)]
    # Claw prongs cradling the orb.
    for i in range(3):
        a = i * TAU / 3
        prong = plate("Prong", [(0.14, 3.58), (0.46, 3.92), (0.40, 4.36), (0.20, 4.28),
                                (0.22, 3.96)], 0.10)
        prong.rotation_euler = (0, 0, a)
        parts.append(bevel(prong, 0.015))
    parts.append(orb("Orb", 4.08, 0.36))
    parts.append(bevel(box("Collar", 0.13, 0.13, 0.14, 3.55), 0.03))
    return finish("NecroStaff", parts, DARK)


def w_staff():
    parts = [shaft("Shaft", -0.7, 4.9, 0.12, 0.90), grip(1.0, 0.14, 4),
             orb("Orb", 4.45, 0.34),
             bevel(box("Collar", 0.14, 0.14, 0.16, 4.02), 0.03)]
    return finish("Staff", parts, WOOD)


def w_shield():
    # Offhand: a heater face, domed slightly, with a boss.
    pts = []
    for i in range(11):
        t = i / 10
        z = 1.05 - 2.15 * t
        y = 1.05 * (1 - t * t * 0.72) if t < 0.75 else 1.05 * (1 - t) * 2.2
        pts.append((y, z))
    for i in range(10, -1, -1):
        t = i / 10
        z = 1.05 - 2.15 * t
        y = 1.05 * (1 - t * t * 0.72) if t < 0.75 else 1.05 * (1 - t) * 2.2
        pts.append((-y, z))
    parts = [bevel(plate("Face", pts, 0.14), 0.03),
             orb("Boss", 0.0, 0.24)]
    return finish("Shield", parts, STEEL)


WEAPONS = [
    ("Sword", w_sword, 90), ("Greatsword", w_greatsword, 90), ("Dagger", w_dagger, 90),
    ("PaladinBlade", w_paladinblade, 90), ("RoyalBlade", w_royalblade, 90),
    ("Greataxe", w_greataxe, 0), ("Bow", w_bow, 0), ("Musket", w_musket, 0),
    ("NecroStaff", w_necrostaff, 0), ("Staff", w_staff, 0), ("Shield", w_shield, 0),
]


# ---------------------------------------------------------------------------
# build / export / preview
# ---------------------------------------------------------------------------

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    built = []
    for name, fn, _face in WEAPONS:
        ob = fn()
        ob.name = name
        built.append(ob)
        # Export each on its own, at the origin, before it gets laid out.
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        path = os.path.join(OUT, name + ".obj")
        bpy.ops.wm.obj_export(filepath=path, export_selected_objects=True,
                              forward_axis="NEGATIVE_Z", up_axis="Y",
                              export_materials=False, apply_modifiers=True)
        #[[ Roblox re-centres imported meshes on their bounding box, discarding
        #   the origin-at-the-grip authoring. Half the height is what
        #   WeaponConfig.Appearance.GripLift has to add back, so print it here
        #   and the two never drift apart. ]]
        zs = [(ob.matrix_world @ v.co).z for v in ob.data.vertices]
        lift = (min(zs) + max(zs)) / 2
        print("EXPORT %-14s %5d tris  GripLift=%.3f  -> %s"
              % (name, len(ob.data.loop_triangles) or len(ob.data.polygons),
                 lift, path))

    # Lay them out in a row for one preview sheet.
    for i, ob in enumerate(built):
        ob.location = (0, (i - (len(built) - 1) / 2) * 2.5, 0)
        ob.rotation_euler = (0, 0, math.radians(WEAPONS[i][2]))

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = len(built) * 2.6
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (14, 0, 2.0)
    cam.rotation_euler = (math.radians(90), 0, math.radians(90))

    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "OBJECT"
    sh.show_cavity = True
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 620
    scene.render.filepath = os.path.join(OUT, "preview.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW %s" % scene.render.filepath)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "weapons.blend"))
    print("BUILT %d weapons" % len(built))


main()
