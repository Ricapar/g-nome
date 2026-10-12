"""Build the main menu machinery frame as a 3D model (Blender 2.91+, run headless).

    blender --factory-startup -b --python remake/art/ui/frame/build_frame.py -- <out.glb>

Layout follows remake/art/ui/reference/target_briefing.png (target look, see
remake/UI-DESIGN.md). Units: 1 = 100 design pixels at 1080p; the frame core spans
x -7.2..7.2 and z -5.4..5.4. Front faces point to -Y (glTF +Z, toward the Godot camera).

Godot assigns the real (PBR, triplanar) materials by material name:
  red_paint, white_paint, steel_dark, steel_brushed, black_coat, hazard, rubber,
  glass_dark, lamp_orange, lamp_red, led_0..led_4.
Empties named anchor_* mark where 2D controls go: location = rect centre on the front face,
scale x/z = rect width/height. Empties named light_* get small lights in Godot.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "menu_frame.glb"

COLOURS = {
    "red_paint": (0.45, 0.05, 0.04), "white_paint": (0.8, 0.8, 0.78), "steel_dark": (0.12, 0.12, 0.12),
    "steel_brushed": (0.55, 0.55, 0.55), "black_coat": (0.02, 0.02, 0.02), "hazard": (0.6, 0.45, 0.05),
    "rubber": (0.03, 0.03, 0.03), "glass_dark": (0.0, 0.02, 0.02), "lamp_orange": (1.0, 0.45, 0.05),
    "lamp_red": (1.0, 0.1, 0.05),
}
for i in range(5):
    COLOURS["led_%d" % i] = (0.02, 0.05, 0.03)


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        c = COLOURS.get(name, (0.5, 0.5, 0.5))
        m.diffuse_color = (*c, 1.0)
    return m


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def octagon(w, h, c):
    """Outline of a w x h rectangle with corners chamfered by c (counter-clockwise, XZ plane)."""
    x, z = w / 2, h / 2
    c = max(min(c, x, z), 0.001)
    return [(-x + c, -z), (x - c, -z), (x, -z + c), (x, z - c), (x - c, z), (-x + c, z), (-x, z - c), (-x, -z + c)]


def finish(obj, mat, bevel=0.04, segments=3, angle=35):
    obj.data.materials.append(material(mat))
    for p in obj.data.polygons:
        p.use_smooth = True
    obj.data.use_auto_smooth = True
    obj.data.auto_smooth_angle = math.radians(angle)
    if bevel > 0:
        b = obj.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = segments
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(angle)
        b.harden_normals = True
        b.miter_outer = "MITER_ARC"
    return obj


def new_object(name, bm, loc=(0, 0, 0), rot_z=0.0):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (0, 0, math.radians(rot_z))
    return obj


def plate(name, w, h, d, mat, loc, chamfer=0.0, bevel=0.04, rot_z=0.0, hole=None):
    """A chamfered slab d deep whose front face sits at loc.y (extends toward +Y).
    hole = (w, h, chamfer) cuts a centred opening, making a frame."""
    bm = bmesh.new()
    outer = [bm.verts.new((x, 0, z)) for x, z in octagon(w, h, chamfer)]
    if hole:
        inner = [bm.verts.new((x, 0, z)) for x, z in octagon(*hole)]
        for i in range(8):
            j = (i + 1) % 8
            bm.faces.new([outer[i], outer[j], inner[j], inner[i]])
    else:
        bm.faces.new(outer)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:  # face the front (-Y)
        if f.normal.y > 0:
            f.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    verts = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=verts, vec=(0, d, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm, loc, rot_z), mat, bevel)


def cylinder(name, r, length, mat, loc, axis="Z", bevel=0.02, segments=32):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          diameter1=1.0, diameter2=1.0, depth=1.0)
    # normalise: Blender versions disagree on diameter vs radius, so scale from measured bounds
    xs = [v.co.x for v in bm.verts]
    s = r / (max(xs) - min(xs)) * 2.0
    bmesh.ops.scale(bm, vec=(s, s, length), verts=bm.verts)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    return finish(new_object(name, bm, loc), mat, bevel, segments=2, angle=50)


def cable(name, points, radius, mat="rubber"):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 4
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name + "_curve", cu)
    bpy.context.collection.objects.link(obj)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj, do_unlink=True)
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(material(mat))
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def anchor(name, cx, cz, w, h, y):
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    e.location = (cx, y, cz)
    e.scale = (w, 1.0, h)
    return e


def light(name, x, z, y=-0.9):
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    e.location = (x, y, z)
    return e


# --------------------------------------------------------------------------------------------
# Layout constants (design px / 100, measured from the target image)
SLOT_Z = [1.72, 0.82, -0.08, -0.99]
SLOT_W, SLOT_H = 1.52, 0.62
PILLAR_X = -6.26          # centre of the slot column (left pillar)
SCREEN = (9.86, 7.22, 0.32)  # inner opening w, h, chamfer
SCREEN_CZ = 1.27
KEY_X = [-3.72, -1.86, 0.0, 1.86, 3.72]
KEY_W, KEY_H = 1.66, 1.12
KEY_CZ = -4.68


def build_pillar(side):
    """side = -1 for the left pillar, +1 for the right (mirrored)."""
    s = side
    px = PILLAR_X * -s if s > 0 else PILLAR_X
    tag = "L" if s < 0 else "R"
    out = px - 0.95 * (1 if s < 0 else -1)  # outer edge x
    # core column and back structure
    plate("pillar_core_" + tag, 2.1, 10.8, 1.2, "steel_dark", (px, 0.0, 0.0), chamfer=0.1)
    # top armour: big red plate angled toward the screen, white chevron, vents
    rz = 12 * (1 if s < 0 else -1)
    plate("armour_top_" + tag, 2.05, 3.0, 0.5, "red_paint", (px - 0.02 * s, -1.05, 3.92), chamfer=0.35, bevel=0.06, rot_z=rz)
    plate("armour_top_lip_" + tag, 1.7, 0.5, 0.3, "steel_dark", (px, -0.9, 2.2), chamfer=0.1)
    for k in range(3):
        plate("chevron_%s%d" % (tag, k), 0.18, 0.95, 0.04, "white_paint",
              (px + (0.25 + 0.3 * k) * -s, -1.1, 4.55 - 0.05 * k), chamfer=0.05, bevel=0.01, rot_z=rz)
    plate("vents_top_" + tag, 0.6, 0.55, 0.06, "black_coat", (px + 0.35 * s, -1.1, 3.35), chamfer=0.04, bevel=0.01, rot_z=rz)
    for k in range(4):
        plate("vent_slat_%s%d" % (tag, k), 0.5, 0.05, 0.03, "lamp_orange" if k == 0 else "steel_dark",
              (px + 0.35 * s, -1.14, 3.52 - 0.12 * k), bevel=0.0, rot_z=rz)
    # hydraulic rams on the outer side, into the armour
    for k, z0 in enumerate((4.8, 3.2)):
        cylinder("ram_sleeve_%s%d" % (tag, k), 0.16, 0.9, "black_coat", (out - 0.05 * s, -0.7, z0), axis="X")
        cylinder("ram_rod_%s%d" % (tag, k), 0.08, 1.2, "steel_brushed", (out - 0.65 * s, -0.7, z0), axis="X")
    # slot collars: a steel drum per slot with a dark recess for the glass button
    for i, z in enumerate(SLOT_Z):
        plate("collar_%s%d" % (tag, i), 1.86, 0.84, 0.75, "steel_dark", (px, -1.0, z), chamfer=0.12, bevel=0.07,
              hole=(SLOT_W + 0.08, SLOT_H + 0.08, 0.08))
        plate("collar_back_%s%d" % (tag, i), 1.7, 0.7, 0.1, "black_coat", (px, -0.3, z), bevel=0.0)
        plate("collar_ring_%s%d" % (tag, i), 2.0, 0.1, 0.8, "steel_brushed", (px, -0.95, z - 0.46), chamfer=0.03, bevel=0.02)
        plate("slot_lamp_%s%d" % (tag, i), 0.16, 0.05, 0.05, "lamp_orange", (px, -1.02, z - 0.46), bevel=0.0)
        light("light_slot_%s%d" % (tag, i), px, z - 0.46, -1.15)
        anchor("anchor_slot_%s%d" % (tag, i), px, z, SLOT_W, SLOT_H, -1.0)
    plate("collar_cap_" + tag, 2.0, 0.12, 0.85, "steel_brushed", (px, -0.98, 2.2), chamfer=0.03, bevel=0.02)
    # lower armour: hazard band, grille, pistons, angled foot
    plate("armour_low_" + tag, 2.05, 3.9, 0.5, "red_paint", (px, -1.05, -3.45), chamfer=0.3, bevel=0.06, rot_z=rz * 0.6)
    plate("hazard_" + tag, 1.9, 0.32, 0.05, "hazard", (px, -1.08, -1.82), chamfer=0.04, bevel=0.01, rot_z=rz * 0.6)
    plate("grille_frame_" + tag, 0.9, 1.0, 0.08, "steel_dark", (px + 0.25 * s, -1.1, -2.7), chamfer=0.08, bevel=0.02, rot_z=rz * 0.6)
    for k in range(7):
        plate("grille_slat_%s%d" % (tag, k), 0.72, 0.05, 0.04, "black_coat", (px + 0.25 * s, -1.14, -2.35 - 0.12 * k), bevel=0.0, rot_z=rz * 0.6)
    plate("chevron_low_" + tag, 1.5, 0.22, 0.04, "white_paint", (px, -1.1, -4.6), chamfer=0.11, bevel=0.01, rot_z=rz * 0.6)
    for k, z0 in enumerate((-2.2, -3.6)):
        cylinder("piston_%s%d" % (tag, k), 0.13, 0.7, "steel_brushed", (out - 0.15 * s, -0.8, z0), axis="X")
        cylinder("piston_cap_%s%d" % (tag, k), 0.18, 0.18, "black_coat", (out + 0.15 * s, -0.8, z0), axis="X")
    # cables from the pillar into the bezel side
    cable("cable_%s0" % tag, [(out, -0.4, 2.4), (px + 0.4 * -s, -0.9, 1.0), (px + 1.2 * -s, -0.5, -1.6), (px + 1.3 * -s, -0.3, -2.6)], 0.06)
    cable("cable_%s1" % tag, [(out, -0.3, -1.4), (px + 0.9 * -s, -0.6, -2.6), (px + 1.4 * -s, -0.4, -3.0)], 0.05)


def build_bezel():
    w, h = 10.36, 7.92
    plate("bezel_outer", w, h, 0.55, "steel_dark", (0, -0.55, SCREEN_CZ - 0.01), chamfer=0.5, bevel=0.07,
          hole=(SCREEN[0] + 0.3, SCREEN[1] + 0.3, SCREEN[2] + 0.12))
    plate("bezel_lip", SCREEN[0] + 0.32, SCREEN[1] + 0.32, 0.25, "steel_brushed", (0, -0.3, SCREEN_CZ),
          chamfer=SCREEN[2] + 0.12, bevel=0.03, hole=SCREEN)
    plate("screen_glass", SCREEN[0] + 0.1, SCREEN[1] + 0.1, 0.05, "glass_dark", (0, -0.08, SCREEN_CZ), chamfer=SCREEN[2], bevel=0.0)
    anchor("anchor_screen", 0, SCREEN_CZ, SCREEN[0], SCREEN[1], -0.1)
    # bolts on the bezel
    for x in (-4.9, -1.7, 1.7, 4.9):
        for z in (SCREEN_CZ + 3.78, SCREEN_CZ - 3.78):
            cylinder("bolt_%.1f_%.1f" % (x, z), 0.06, 0.06, "steel_brushed", (x, -0.58, z), axis="Y", bevel=0.01, segments=12)
    # header on top with lamps
    plate("header", 7.4, 0.5, 0.7, "steel_dark", (0, -0.7, 5.3), chamfer=0.15, bevel=0.05)
    for x in (-3.0, -1.3, 1.3, 3.0):
        plate("header_lamp_%.1f" % x, 0.42, 0.12, 0.05, "lamp_red" if abs(x) > 2 else "lamp_orange", (x, -0.72, 5.3), bevel=0.0)
        light("light_header_%.1f" % x, x, 5.3, -1.0)
    # machinery strip under the screen: housing, light bar, lamps
    plate("under_strip", 10.0, 0.5, 0.6, "steel_dark", (0, -0.65, -2.92), chamfer=0.1, bevel=0.04)
    plate("under_lightbar", 1.6, 0.08, 0.04, "lamp_orange", (0, -0.67, -2.92), bevel=0.0)
    light("light_under_0", 0.0, -2.92, -1.0)
    for x in (-3.9, -2.3, 2.3, 3.9):
        plate("under_lamp_%.1f" % x, 0.14, 0.14, 0.04, "lamp_orange", (x, -0.67, -2.92), chamfer=0.04, bevel=0.0)
    # status housing with a recessed channel
    plate("status_housing", 9.7, 0.66, 0.5, "steel_dark", (0, -0.6, -3.55), chamfer=0.12, bevel=0.04,
          hole=(9.2, 0.42, 0.06))
    plate("status_channel", 9.3, 0.5, 0.05, "black_coat", (0, -0.25, -3.55), bevel=0.0)
    anchor("anchor_status", 0, -3.55, 9.2, 0.42, -0.6)


def build_keys():
    plate("key_base", 10.2, 1.5, 0.9, "steel_dark", (0, -0.5, -4.68), chamfer=0.2, bevel=0.05)
    for i, x in enumerate(KEY_X):
        plate("key_body_%d" % i, KEY_W, KEY_H, 0.55, "steel_brushed", (x, -1.0, KEY_CZ), chamfer=0.1, bevel=0.06)
        plate("key_face_%d" % i, KEY_W - 0.2, KEY_H - 0.3, 0.05, "steel_dark", (x, -1.03, KEY_CZ - 0.08), chamfer=0.06, bevel=0.015)
        plate("key_led_%d" % i, 0.42, 0.07, 0.04, "led_%d" % i, (x, -1.035, KEY_CZ + 0.4), bevel=0.0)
        anchor("anchor_key_%d" % i, x, KEY_CZ - 0.08, KEY_W - 0.2, KEY_H - 0.3, -1.05)
    for x in [(-0.93 + k * 1.86) for k in range(-1, 3)] + [-4.65, 4.65]:
        plate("key_gap_lamp_%.2f" % x, 0.06, 0.5, 0.04, "lamp_orange", (x, -0.95, KEY_CZ), bevel=0.0)
    light("light_keys_0", -2.79, KEY_CZ, -1.2)
    light("light_keys_1", 2.79, KEY_CZ, -1.2)
    # red armour at the bottom corners
    for s in (-1, 1):
        plate("armour_corner_%d" % s, 1.6, 1.4, 0.45, "red_paint", (s * 5.6, -0.9, -4.75), chamfer=0.35, bevel=0.06, rot_z=-s * 18)


def build_wings():
    """Machinery that only wide screens see (beyond x = +-7.2)."""
    plate("back_wall", 40.0, 12.0, 0.2, "black_coat", (0, 0.6, 0), bevel=0.0)
    for s in (-1, 1):
        for k, x in enumerate((8.4, 10.9, 13.4, 15.9)):
            plate("beam_%d_%d" % (s, k), 0.7, 11.0, 0.5, "steel_dark", (s * x, -0.3, 0), chamfer=0.05, bevel=0.03)
            plate("beam_web_%d_%d" % (s, k), 0.2, 11.0, 0.3, "steel_brushed", (s * x, -0.5, 0), bevel=0.02)
        for k, z in enumerate((3.6, 0.9, -2.1, -4.4)):
            cylinder("wing_pipe_%d_%d" % (s, k), 0.18 if k % 2 else 0.12, 12.0, "steel_brushed" if k % 2 else "rubber",
                     (s * 13.2, -0.15, z), axis="X", bevel=0.01)
        plate("wing_box_%d" % s, 1.6, 1.1, 0.5, "red_paint", (s * 9.65, -0.6, -3.2), chamfer=0.2, bevel=0.05)
        plate("wing_box_hz_%d" % s, 1.4, 0.18, 0.04, "hazard", (s * 9.65, -0.62, -2.82), bevel=0.0)


clear_scene()
build_pillar(-1)
build_pillar(1)
build_bezel()
build_keys()
build_wings()
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True)
print("wrote", OUT)
