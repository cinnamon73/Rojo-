"""Procedural weapon meshes as OBJ, importable straight into Studio.

WHY THIS EXISTS
---------------
WeaponModels.luau assembles each weapon from shaped Parts. That reads well but
costs several parts per weapon and cannot do bevels, tapers or curved edges.
ItemConfig.Appearance.MeshId is already the hook for real meshes — this fills it
without commissioning art.

OBJ is a plain-text format (vertex lines, face lines), so a mesh is just
arithmetic. Everything here is a SWEEP: a 2D cross-section profile moved along
an axis, scaled per station, with the quads between consecutive rings emitted as
faces. Blades, grips and pommels are all the same operation with different
profiles.

WHAT THIS IS AND IS NOT
-----------------------
It produces clean, faceted, low-poly geometry — bevelled blades with real
diamond cross-sections and tapers. It is NOT sculpted or organic; it will never
look hand-modelled. For a stylised Roblox game that is arguably the correct
look, and it is a large step up from box assemblies.

USAGE
    python tools/GenerateWeaponMesh.py
Writes tools/meshes/*.obj plus a preview PNG.

IMPORTING
    Studio > Asset Manager > Import > select the .obj (set the file filter to
    Images/3D as needed), then put the resulting mesh id in the item template's
    Appearance.MeshId. The jointing and swing animation in WeaponModels do not
    care what shape they are moving.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw

OUT_DIR = os.path.join(os.path.dirname(__file__), "meshes")


# ---------------------------------------------------------------- geometry

def diamond_profile(width, thickness, edge_sharpness=0.18):
    """Cross-section of a blade: wide and flat with a sharpened spine.

    Six points rather than four so the blade has real bevels — a plain
    rectangle reads as a plank from every angle.
    """
    w, t = width / 2.0, thickness / 2.0
    return [
        (-w, 0.0),                      # cutting edge, left
        (-w * (1 - edge_sharpness), t),  # bevel up
        (w * (1 - edge_sharpness), t),   # spine, top
        (w, 0.0),                        # cutting edge, right
        (w * (1 - edge_sharpness), -t),  # bevel down
        (-w * (1 - edge_sharpness), -t),
    ]


def circle_profile(radius, segments=10):
    return [
        (radius * math.cos(2 * math.pi * i / segments),
         radius * math.sin(2 * math.pi * i / segments))
        for i in range(segments)
    ]


def sweep(profile, stations):
    """Sweep a profile along Y.

    `stations` is a list of (y, scale) pairs. A scale of 0 collapses the ring to
    a point, which is what makes a blade tip converge instead of ending in a
    blunt face.
    """
    verts, faces = [], []
    rings = []

    for y, scale in stations:
        ring = []
        for px, pz in profile:
            verts.append((px * scale, y, pz * scale))
            ring.append(len(verts) - 1)
        rings.append(ring)

    n = len(profile)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            # Quad between consecutive rings. Emitted as two triangles because
            # Roblox's importer is happier with them and non-planar quads
            # shade unpredictably.
            faces.append((a[i], a[j], b[j]))
            faces.append((a[i], b[j], b[i]))

    # Cap both ends with a fan, skipped where the ring already collapsed.
    for ring, flip in ((rings[0], True), (rings[-1], False)):
        pts = {verts[i] for i in ring}
        if len(pts) <= 1:
            continue
        for i in range(1, len(ring) - 1):
            tri = (ring[0], ring[i], ring[i + 1])
            faces.append(tri[::-1] if flip else tri)

    return verts, faces


def merge(*parts):
    """Concatenates (verts, faces) pairs, re-basing face indices."""
    verts, faces = [], []
    for v, f in parts:
        offset = len(verts)
        verts.extend(v)
        faces.extend((a + offset, b + offset, c + offset) for a, b, c in f)
    return verts, faces


def translate(part, dy):
    verts, faces = part
    return [(x, y + dy, z) for x, y, z in verts], faces


def rotate_z(part, degrees):
    verts, faces = part
    r = math.radians(degrees)
    c, s = math.cos(r), math.sin(r)
    return [(x * c - y * s, x * s + y * c, z) for x, y, z in verts], faces


# ---------------------------------------------------------------- weapons

def build_blade_weapon(blade_len, blade_width, blade_thick, guard_width,
                       grip_len, grip_radius, pommel_radius):
    """A sword family member. Every archetype here is this with new numbers."""
    prof = diamond_profile(blade_width, blade_thick)

    # Slight taper along the blade, converging to a point over the last 12%.
    blade = sweep(prof, [
        (0.00, 1.00),
        (blade_len * 0.55, 0.94),
        (blade_len * 0.88, 0.72),
        (blade_len * 1.00, 0.00),
    ])

    guard = rotate_z(
        sweep(diamond_profile(guard_width * 0.22, blade_thick * 2.2), [
            (-guard_width / 2, 0.75),
            (-guard_width * 0.22, 1.00),
            (guard_width * 0.22, 1.00),
            (guard_width / 2, 0.75),
        ]),
        90,
    )

    grip = translate(
        sweep(circle_profile(grip_radius), [
            (0.0, 1.00), (grip_len * 0.5, 0.88), (grip_len, 1.02),
        ]),
        -grip_len,
    )

    # Lathed pommel: a squashed sphere reads as turned metal.
    steps = 7
    pommel = translate(
        sweep(circle_profile(pommel_radius), [
            (pommel_radius * 2 * (i / steps - 0.5),
             math.sin(math.pi * i / steps))
            for i in range(steps + 1)
        ]),
        -grip_len - pommel_radius,
    )

    return merge(blade, guard, grip, pommel)


ARCHETYPES = {
    # name            blade  width  thick  guard  grip  gripR  pommelR
    "dagger":        (1.30, 0.26, 0.075, 0.52, 0.42, 0.075, 0.100),
    "sword":         (3.20, 0.40, 0.090, 1.05, 0.72, 0.085, 0.125),
    "greatsword":    (5.00, 0.62, 0.120, 1.65, 1.35, 0.100, 0.165),
}


# ---------------------------------------------------------------- output

def write_obj(path, verts, faces, name):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(f"# {name} - generated by tools/GenerateWeaponMesh.py\n")
        fh.write(f"o {name}\n")
        for x, y, z in verts:
            fh.write(f"v {x:.5f} {y:.5f} {z:.5f}\n")
        for a, b, c in faces:
            fh.write(f"f {a + 1} {b + 1} {c + 1}\n")


def render(parts, path, size=(960, 520)):
    """Flat-shaded painter's-algorithm preview, so quality is judgeable here."""
    img = Image.new("RGB", size, (22, 24, 32))
    draw = ImageDraw.Draw(img)

    yaw, pitch = math.radians(28), math.radians(-16)
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    light = np.array([0.45, 0.7, 0.55])
    light = light / np.linalg.norm(light)

    slot_w = size[0] / len(parts)

    # ONE scale for every weapon, derived from the tallest. Normalising each
    # independently would draw a dagger and a greatsword the same size, hiding
    # the only thing a comparison render is for.
    tallest = max(
        float(np.ptp(np.array(v, dtype=float)[:, 1])) for _, (v, _) in parts
    )
    shared = (size[1] * 0.80) / tallest

    for index, (name, (verts, faces)) in enumerate(parts):
        v = np.array(verts, dtype=float)
        v -= v.mean(axis=0)
        v *= shared

        x, y, z = v[:, 0], v[:, 1], v[:, 2]
        xr, zr = x * cy - z * sy, x * sy + z * cy
        yr, zr = y * cp - zr * sp, y * sp + zr * cp

        ox = slot_w * (index + 0.5)
        oy = size[1] * 0.5
        pts2d = np.stack([ox + xr, oy - yr], axis=1)

        tris = [(f, zr[list(f)].mean()) for f in faces]
        tris.sort(key=lambda t: t[1])

        for f, _ in tris:
            p = v[list(f)]
            n = np.cross(p[1] - p[0], p[2] - p[0])
            norm = np.linalg.norm(n)
            if norm == 0:
                continue
            n = n / norm
            shade = 0.28 + 0.72 * max(0.0, float(np.dot(n, light)))
            col = (int(120 * shade + 30), int(132 * shade + 32), int(150 * shade + 38))
            draw.polygon([tuple(pts2d[i]) for i in f], fill=col)

        draw.text((ox - 34, size[1] - 26), name, fill=(190, 200, 220))

    img.save(path)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    built = []

    for name, args in ARCHETYPES.items():
        verts, faces = build_blade_weapon(*args)
        write_obj(os.path.join(OUT_DIR, f"{name}.obj"), verts, faces, name)
        built.append((name, (verts, faces)))
        print(f"{name:12} {len(verts):5d} verts  {len(faces):5d} tris")

    preview = os.path.join(OUT_DIR, "preview.png")
    render(built, preview)
    print("preview ->", preview)


if __name__ == "__main__":
    main()
