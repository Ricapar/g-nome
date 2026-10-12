"""Build the main menu machinery frame as a 3D model (Blender 2.91+, run headless).

    blender --factory-startup -b --python remake/art/ui/frame/build_frame.py -- <out.glb>

Target look: remake/art/ui/reference/target_briefing.png (see remake/UI-DESIGN.md). The core
spans a 16:9 view: x -9.6..9.6, z -5.4..5.4 (1 unit = 100 design px at 1080p); machinery past
x = +-9.6 is only seen on wider screens. Front faces point to -Y (glTF +Z, toward the camera).

Godot assigns the real materials by name (ui/frame/menu_frame.gd):
  red_paint, white_paint, steel_dark, steel_brushed, black_coat, hazard, rubber,
  glass_dark, lamp_orange, lamp_red, lamp_yellow, led_0..led_4.
Vertex colours carry masks for the material shader: R = edge wear (convex edges),
G = grime (concave corners).
Empties named anchor_* mark where 2D controls go: location = rect centre on the front face,
scale x/z = rect width/height. Empties named light_* get small lights in Godot.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "menu_frame.glb"

COLOURS = {
    "red_paint": (0.45, 0.05, 0.04), "white_paint": (0.8, 0.8, 0.78), "steel_dark": (0.12, 0.12, 0.12),
    "steel_brushed": (0.55, 0.55, 0.55), "black_coat": (0.02, 0.02, 0.02), "hazard": (0.6, 0.45, 0.05),
    "rubber": (0.03, 0.03, 0.03), "glass_dark": (0.0, 0.02, 0.02), "lamp_orange": (1.0, 0.45, 0.05),
    "lamp_red": (1.0, 0.1, 0.05), "lamp_yellow": (1.0, 0.8, 0.1), "rubber_red": (0.3, 0.03, 0.02),
}
for _i in range(5):
    COLOURS["led_%d" % _i] = (0.02, 0.05, 0.03)


# ---------------------------------------------------------------------------------- helpers
def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*COLOURS.get(name, (0.5, 0.5, 0.5)), 1.0)
    return m


def crect(w, h, tl=0.0, tr=0.0, br=0.0, bl=0.0, cx=0.0, cz=0.0):
    """Rectangle outline (x, z), counter-clockwise, with a chamfer per corner."""
    x, z = w / 2, h / 2
    pts = [(-x + bl, -z), (x - br, -z), (x, -z + br), (x, z - tr), (x - tr, z), (-x + tl, z),
           (-x, z - tl), (-x, -z + bl)]
    out = []
    for p in pts:
        p = (p[0] + cx, p[1] + cz)
        if not out or (abs(p[0] - out[-1][0]) > 1e-4 or abs(p[1] - out[-1][1]) > 1e-4):
            out.append(p)
    if abs(out[0][0] - out[-1][0]) < 1e-4 and abs(out[0][1] - out[-1][1]) < 1e-4:
        out.pop()
    return out


def oct_(w, h, c, cx=0.0, cz=0.0):
    return crect(w, h, c, c, c, c, cx, cz)


def _finish(bm, name, mat, loc, rot, bevel, segments, angle):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
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


def _extrude_back(bm, d):
    for f in bm.faces:
        if f.normal.y > 0:
            f.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    verts = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=verts, vec=(0, d, 0))


def prism(name, pts, d, mat, y, pivot=(0.0, 0.0), rot=(0, 0, 0), bevel=0.04, segments=3, angle=35, curve=None):
    """Outline pts (world x, z) extruded from y back to y + d; rotation rot (deg) about pivot.
    curve = (cx, k) bows the piece around a vertical axis at world x = cx: y += k * (x - cx)^2,
    so plates wrap around a pillar (pieces mounted on a plate use the same curve)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x - pivot[0], 0, z - pivot[1])) for x, z in pts]
    bm.faces.new(vs)
    bm.normal_update()
    _extrude_back(bm, d)
    if curve:
        xs = [v.co.x for v in bm.verts]
        x = min(xs) + 0.12
        while x < max(xs) - 0.05:
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(x, 0, 0), plane_no=(1, 0, 0))
            x += 0.12
        for v in bm.verts:
            dx = v.co.x + pivot[0] - curve[0]
            v.co.y += curve[1] * dx * dx
        bm.normal_update()
    return _finish(bm, name, mat, (pivot[0], y, pivot[1]), rot, bevel, segments, angle)


def ring(name, outer, inner, d, mat, y, slope=0.0, bevel=0.04, segments=3, angle=35):
    """A frame between two outlines with the same vertex count; the inner edge sits `slope`
    deeper (toward +Y) than the outer edge, making a sloped bevel."""
    assert len(outer) == len(inner)
    bm = bmesh.new()
    o = [bm.verts.new((x, 0, z)) for x, z in outer]
    i = [bm.verts.new((x, slope, z)) for x, z in inner]
    for k in range(len(o)):
        j = (k + 1) % len(o)
        bm.faces.new([o[k], o[j], i[j], i[k]])
    bm.normal_update()
    _extrude_back(bm, d)
    return _finish(bm, name, mat, (0, y, 0), (0, 0, 0), bevel, segments, angle)


def profile(name, pts_yz, x0, width, mat, bevel=0.05, segments=3, angle=35):
    """Side profile (y, z) extruded along +X from x0 by width."""
    bm = bmesh.new()
    vs = [bm.verts.new((0, y, z)) for y, z in pts_yz]
    f = bm.faces.new(vs)
    bm.normal_update()
    if f.normal.x > 0:
        f.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    verts = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=verts, vec=(width, 0, 0))
    return _finish(bm, name, mat, (x0, 0, 0), (0, 0, 0), bevel, segments, angle)


def cylinder(name, r, length, mat, loc, axis="Z", bevel=0.02, segments=40):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          diameter1=1.0, diameter2=1.0, depth=1.0)
    xs = [v.co.x for v in bm.verts]
    s = r / (max(xs) - min(xs)) * 2.0 # Blender versions disagree on diameter vs radius
    bmesh.ops.scale(bm, vec=(s, s, length), verts=bm.verts)
    rot = {"Z": (0, 0, 0), "X": (0, 90, 0), "Y": (90, 0, 0)}[axis]
    return _finish(bm, name, mat, loc, rot, bevel, 2, 50)


def cable(name, points, radius, mat="rubber"):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 4
    cu.resolution_u = 16
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    tmp = bpy.data.objects.new(name + "_curve", cu)
    bpy.context.collection.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp, do_unlink=True)
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(material(mat))
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def empty(name, loc, scale=(1, 1, 1)):
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    e.location = loc
    e.scale = scale
    return e


def anchor(name, cx, cz, w, h, y):
    return empty("anchor_" + name, (cx, y, cz), (w, 1.0, h))


def light(name, x, z, y):
    return empty("light_" + name, (x, y, z))


def lamp(name, x, z, w, h, y, mat="lamp_orange", with_light=True):
    prism("lamp_" + name, oct_(w, h, min(w, h) * 0.3, x, z), 0.04, mat, y, bevel=0.0)
    if with_light:
        light(name, x, z, y - 0.25)


# ---------------------------------------------------------------------------------- layout
EDGE = 9.6                       # outer edge of the 16:9 core
PW = 2.3                         # pillar width
SLOT_Z = [1.75, 0.85, -0.05, -0.95]
SLOT_W, SLOT_H = 1.72, 0.64
SCREEN_W, SCREEN_H, SCREEN_CZ = 13.2, 7.2, 1.3
KEY_X = [-5.2, -2.6, 0.0, 2.6, 5.2]
KEY_W, KEY_H, KEY_CZ = 2.36, 1.12, -4.66


def build_pillar(s):
    """s = -1 left pillar, +1 right pillar. u = distance from the outer edge (0..PW)."""
    tag = "L" if s < 0 else "R"

    def X(u):
        return s * (EDGE - u)

    def P(pts):  # (u, z) -> (x, z)
        return [(X(u), z) for u, z in pts] if s < 0 else [(X(u), z) for u, z in reversed(pts)]

    yaw = -s * 9.0
    piv = (X(PW), 0.0)
    C = (X(PW / 2), 0.2)  # armour wraps around the pillar axis
    # core column
    prism("core_" + tag, P([(0.1, -5.6), (2.2, -5.6), (2.2, 5.6), (0.1, 5.6)]), 1.4, "steel_dark", -0.45)
    # ---- top armour: main plate with a cut corner, a layered plate, chevrons, lights, vents
    prism("armour_top_" + tag, P([(0.0, 2.38), (PW, 2.38), (PW, 4.35), (1.55, 5.6), (0.0, 5.6)]),
          0.55, "red_paint", -1.1, piv, (0, 0, yaw), curve=C, bevel=0.07)
    prism("armour_top_b_" + tag, P([(0.22, 3.25), (1.95, 3.25), (1.95, 4.15), (1.35, 4.95), (0.22, 4.95)]),
          0.3, "red_paint", -1.32, piv, (0, 0, yaw), curve=C, bevel=0.05)
    for k in range(3 if s < 0 else 0):  # chevrons on the left, the emblem decal on the right
        u0 = 0.45 + 0.42 * k
        prism("chevron_%s%d" % (tag, k), P([(u0, 3.45), (u0 + 0.2, 3.45), (u0 + 0.62, 3.95), (u0 + 0.62, 4.2), (u0, 3.6)]),
              0.03, "white_paint", -1.345, piv, (0, 0, yaw), curve=C, bevel=0.008, segments=1)
    for k in range(3):
        prism("ind_%s%d" % (tag, k), P([(0.3, 2.6 + 0.17 * k), (0.62, 2.6 + 0.17 * k), (0.62, 2.7 + 0.17 * k), (0.3, 2.7 + 0.17 * k)]),
              0.03, "lamp_yellow" if k else "lamp_orange", -1.13, piv, (0, 0, yaw), curve=C, bevel=0.0)
    light("ind_" + tag, X(0.5), 2.8, -1.5)
    if s > 0:
        empty("decal_emblem_R", (X(1.08), -1.33, 4.0), (1.95, 1.0, 1.22))
    empty("text_" + tag, (X(1.25), -1.16, -4.38))
    prism("vent_frame_" + tag, P([(1.1, 2.55), (2.05, 2.55), (2.05, 3.05), (1.1, 3.05)]), 0.06, "steel_dark", -1.15, piv, (0, 0, yaw), curve=C, bevel=0.02)
    for k in range(4):
        prism("vent_slat_%s%d" % (tag, k), P([(1.17, 2.62 + 0.11 * k), (1.98, 2.62 + 0.11 * k), (1.98, 2.67 + 0.11 * k), (1.17, 2.67 + 0.11 * k)]),
              0.03, "black_coat", -1.17, piv, (0, 0, yaw), curve=C, bevel=0.0)
    # rams and hoses on the outer side
    for k, z0 in enumerate((4.75, 3.05)):
        cylinder("ram_sleeve_%s%d" % (tag, k), 0.17, 1.0, "black_coat", (X(0.15), -0.75, z0), axis="X")
        cylinder("ram_rod_%s%d" % (tag, k), 0.085, 1.5, "steel_brushed", (X(-0.75), -0.75, z0), axis="X")
        cylinder("ram_collar_%s%d" % (tag, k), 0.2, 0.12, "steel_brushed", (X(0.62), -0.75, z0), axis="X")
    cable("hose_%s0" % tag, [(X(0.25), -0.9, 5.5), (X(-0.15), -1.2, 4.0), (X(0.1), -1.1, 2.5), (X(0.35), -0.8, 2.25)], 0.07)
    cable("hose_%s1" % tag, [(X(0.5), -0.7, 5.5), (X(0.05), -0.95, 3.9), (X(0.3), -0.9, 2.3)], 0.05)
    # ---- collar stack: steel drums with a framed opening for each glass button
    cx = X(PW / 2)
    cylinder("collar_cap_top_" + tag, 1.2, 0.14, "steel_brushed", (cx, 0.0, 2.27))
    for i, z in enumerate(SLOT_Z):
        cylinder("drum_%s%d" % (tag, i), 1.1, 0.8, "steel_dark", (cx, 0.0, z), bevel=0.06)
        ring("drum_bezel_%s%d" % (tag, i), oct_(2.0, 0.8, 0.12, cx, z), oct_(SLOT_W + 0.06, SLOT_H + 0.06, 0.08, cx, z),
             0.25, "steel_dark", -1.2, slope=0.06, bevel=0.03)
        prism("drum_back_%s%d" % (tag, i), oct_(SLOT_W + 0.1, SLOT_H + 0.1, 0.08, cx, z), 0.1, "black_coat", -1.05, bevel=0.0)
        cylinder("drum_sep_%s%d" % (tag, i), 1.16, 0.1, "steel_brushed", (cx, 0.0, z - 0.45), bevel=0.02)
        lamp("slot_%s%d" % (tag, i), cx, z - 0.45, 0.22, 0.06, -1.18)
        anchor("slot_%s%d" % (tag, i), cx, z, SLOT_W, SLOT_H, -1.22)
    # ---- lower armour with a foot that reaches in under the key bar
    prism("armour_low_" + tag, P([(0.0, -1.5), (PW, -1.5), (PW, -3.85), (3.15, -4.45), (3.15, -5.6), (0.0, -5.6)]),
          0.55, "red_paint", -1.1, piv, (0, 0, yaw * 0.5), curve=C, bevel=0.07)
    prism("hazard_" + tag, P([(0.08, -1.6), (2.22, -1.6), (2.22, -1.95), (0.08, -1.95)]), 0.04, "hazard", -1.14, piv, (0, 0, yaw * 0.5), curve=C, bevel=0.01)
    prism("grille_frame_" + tag, P([(0.45, -2.25), (1.95, -2.25), (1.95, -3.45), (0.45, -3.45)]), 0.08, "steel_dark", -1.16, piv, (0, 0, yaw * 0.5), curve=C, bevel=0.03)
    for k in range(9):
        prism("grille_slat_%s%d" % (tag, k), P([(0.55, -2.37 - 0.12 * k), (1.85, -2.37 - 0.12 * k), (1.85, -2.42 - 0.12 * k), (0.55, -2.42 - 0.12 * k)]),
              0.03, "black_coat", -1.18, piv, (0, 0, yaw * 0.5), curve=C, bevel=0.0)
    for k in range(2):
        u0 = 1.45 + 0.55 * k
        prism("foot_chevron_%s%d" % (tag, k), P([(u0, -5.15), (u0 + 0.28, -5.15), (u0 + 0.6, -4.85), (u0 + 0.32, -4.85)]),
              0.03, "white_paint", -1.14, piv, (0, 0, yaw * 0.5), curve=C, bevel=0.008, segments=1)
    for k, z0 in enumerate((-2.45, -3.75)):
        cylinder("piston_%s%d" % (tag, k), 0.13, 1.1, "steel_brushed", (X(-0.2), -0.85, z0), axis="X")
        cylinder("piston_cap_%s%d" % (tag, k), 0.2, 0.25, "black_coat", (X(0.25), -0.85, z0), axis="X")
    # cables from the pillar into the machinery under the screen
    cable("cable_%s0" % tag, [(X(2.0), -1.0, -1.45), (X(2.6), -1.05, -2.2), (X(3.1), -0.95, -2.75)], 0.07)
    cable("cable_%s1" % tag, [(X(2.1), -0.8, -1.4), (X(2.9), -0.85, -2.0), (X(3.6), -0.8, -2.62)], 0.05)
    # cable runs in the gap between pillar and bezel, and a bundle into the key bar
    cable("run_%s0" % tag, [(X(2.33), -0.75, 5.4), (X(2.4), -0.8, 2.0), (X(2.36), -0.8, -1.3)], 0.06)
    cable("run_%s1" % tag, [(X(2.45), -0.7, 5.4), (X(2.5), -0.72, 1.0), (X(2.42), -0.7, -1.4)], 0.045, "rubber_red")
    cable("bundle_%s0" % tag, [(X(2.7), -0.95, -2.6), (X(2.95), -1.15, -3.3), (X(3.05), -1.1, -3.95), (X(3.3), -0.75, -4.2)], 0.075)
    cable("bundle_%s1" % tag, [(X(2.85), -0.9, -2.62), (X(3.15), -1.08, -3.25), (X(3.2), -1.05, -3.9), (X(3.45), -0.7, -4.15)], 0.055, "rubber_red")
    cable("bundle_%s2" % tag, [(X(2.6), -0.85, -2.58), (X(2.8), -1.0, -3.4), (X(2.95), -0.95, -4.0), (X(3.2), -0.7, -4.25)], 0.04)


def build_bezel():
    W, H = 14.3, 8.1
    ow, oh = SCREEN_W + 0.3, SCREEN_H + 0.26
    ring("bezel_outer", oct_(W, H, 0.65, 0, SCREEN_CZ - 0.02), oct_(ow, oh, 0.45, 0, SCREEN_CZ), 0.5, "steel_dark", -0.9, bevel=0.08)
    ring("bezel_trim", oct_(W - 0.3, H - 0.3, 0.55, 0, SCREEN_CZ - 0.02), oct_(W - 0.42, H - 0.42, 0.5, 0, SCREEN_CZ - 0.02),
         0.04, "steel_brushed", -0.93, bevel=0.01, segments=1)
    ring("bezel_slope", oct_(ow, oh, 0.45, 0, SCREEN_CZ), oct_(SCREEN_W, SCREEN_H, 0.38, 0, SCREEN_CZ), 0.3, "steel_dark", -0.9,
         slope=0.45, bevel=0.02)
    prism("screen_glass", oct_(SCREEN_W + 0.04, SCREEN_H + 0.04, 0.38, 0, SCREEN_CZ), 0.05, "glass_dark", -0.44, bevel=0.0)
    anchor("screen", 0, SCREEN_CZ, SCREEN_W, SCREEN_H, -0.46)
    for x in (-6.85, -3.4, 0.0, 3.4, 6.85):
        for z in (SCREEN_CZ + 3.88, SCREEN_CZ - 3.88):
            cylinder("bolt_%.2f_%.2f" % (x, z), 0.065, 0.08, "steel_brushed", (x, -0.94, z), axis="Y", bevel=0.015, segments=16)
    for z in (SCREEN_CZ + 2.0, SCREEN_CZ - 2.0):
        for x in (-7.0, 7.0):
            cylinder("bolt_side_%.1f_%.1f" % (x, z), 0.065, 0.08, "steel_brushed", (x, -0.94, z), axis="Y", bevel=0.015, segments=16)
    # clips on top of the bezel with hazard bands (as in the original)
    for x in (-4.6, 4.6):
        prism("clip_%.1f" % x, oct_(1.5, 0.42, 0.1, x, 5.33), 0.45, "red_paint", -1.0, bevel=0.04)
        prism("clip_hz_%.1f" % x, oct_(1.3, 0.16, 0.03, x, 5.33), 0.03, "hazard", -1.02, bevel=0.0)
    # header housing with lamps
    prism("header", crect(6.2, 0.62, 0.0, 0.0, 0.22, 0.22, 0, 5.2), 0.7, "steel_dark", -1.0, bevel=0.05)
    for x in (-2.4, -0.8, 0.8, 2.4):
        lamp("header_%.1f" % x, x, 5.18, 0.5, 0.13, -1.02, "lamp_red" if abs(x) > 2 else "lamp_orange")
    # machinery strip under the screen: housing, light bar, lamp pods, pipes
    prism("under_strip", crect(13.8, 0.5, 0.1, 0.1, 0.1, 0.1, 0, -2.98), 0.6, "steel_dark", -0.85, bevel=0.04)
    lamp("under_bar", 0.0, -2.98, 1.8, 0.09, -0.87)
    for x in (-5.8, -4.0, -2.2, 2.2, 4.0, 5.8):
        cylinder("pod_%.1f" % x, 0.11, 0.08, "steel_brushed", (x, -0.9, -2.98), axis="Y", bevel=0.01, segments=20)
        lamp("pod_%.1f" % x, x, -2.98, 0.11, 0.11, -0.95, with_light=abs(x) > 5)
    for z, r in ((-2.76, 0.045), (-3.2, 0.055)):
        cylinder("under_pipe_%.2f" % z, r, 13.6, "rubber" if r > 0.05 else "steel_brushed", (0, -0.92, z), axis="X", bevel=0.0)
    # status housing with a recessed channel
    ring("status_housing", oct_(13.0, 0.66, 0.14, 0, -3.55), oct_(12.45, 0.44, 0.07, 0, -3.55), 0.5, "steel_dark", -0.85,
         slope=0.12, bevel=0.03)
    prism("status_channel", oct_(12.6, 0.5, 0.07, 0, -3.55), 0.05, "black_coat", -0.6, bevel=0.0)
    anchor("status", 0, -3.55, 12.45, 0.44, -0.86)


def build_keys():
    prism("key_base", crect(13.9, 1.6, 0.2, 0.2, 0.0, 0.0, 0, -4.72), 0.8, "steel_dark", -0.6, bevel=0.05)
    tilt = 7.0
    for i, x in enumerate(KEY_X):
        # side profile: the face leans back toward the top
        profile("key_body_%d" % i, [(-1.18, -5.24), (-0.6, -5.24), (-0.6, -4.08), (-1.04, -4.08)], x - KEY_W / 2, KEY_W,
                "steel_brushed", bevel=0.07)
        zc = KEY_CZ - 0.1
        yc = -1.18 + 0.14 * ((zc - (-5.24)) / 1.16) - 0.015
        prism("key_plate_%d" % i, oct_(KEY_W - 0.36, 0.6, 0.08, x, zc), 0.04, "steel_dark", yc, (x, zc), (-tilt, 0, 0), bevel=0.012)
        prism("key_led_%d" % i, oct_(0.5, 0.075, 0.03, x, KEY_CZ + 0.38), 0.03, "led_%d" % i, -1.08, bevel=0.0)
        anchor("key_%d" % i, x, zc, KEY_W - 0.36, 0.6, yc - 0.02)
    for x in (-6.55, -3.9, -1.3, 1.3, 3.9, 6.55):
        lamp("gap_%.2f" % x, x, KEY_CZ, 0.07, 0.6, -1.0, with_light=abs(x) in (1.3, 6.55))


def build_wings():
    """Machinery seen only on screens wider than 16:9 (x beyond +-9.6)."""
    prism("back_wall", crect(60.0, 14.0), 0.2, "black_coat", 0.9, bevel=0.0)
    for s in (-1, 1):
        for k, x in enumerate((10.6, 13.4, 16.2, 19.0)):
            prism("beam_%d_%d" % (s, k), oct_(0.8, 12.0, 0.05, s * x, 0), 0.5, "steel_dark", -0.3, bevel=0.04)
            prism("beam_web_%d_%d" % (s, k), oct_(0.24, 12.0, 0.0, s * x, 0), 0.3, "steel_brushed", -0.42, bevel=0.02)
        for k, z in enumerate((3.9, 1.2, -2.0, -4.4)):
            cylinder("wing_pipe_%d_%d" % (s, k), 0.2 if k % 2 else 0.13, 14.0, "steel_brushed" if k % 2 else "rubber",
                     (s * 16.6, -0.1, z), axis="X", bevel=0.01)
        prism("wing_box_%d" % s, oct_(1.8, 1.2, 0.2, s * 12.0, -3.2), 0.5, "red_paint", -0.62, bevel=0.05)
        prism("wing_box_hz_%d" % s, oct_(1.6, 0.18, 0.0, s * 12.0, -2.78), 0.04, "hazard", -0.64, bevel=0.0)
        lamp("wing_%d" % s, s * 12.0, -3.4, 0.4, 0.1, -0.64)


# ---------------------------------------------------------------------------------- masks
def bake_masks():
    """Apply modifiers, then store per-vertex convexity (R = edge wear) and concavity
    (G = grime) as vertex colours for the material shader."""
    dg = bpy.context.evaluated_depsgraph_get()
    for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
        me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
        old = obj.data
        obj.modifiers.clear()
        obj.data = me
        bpy.data.meshes.remove(old)
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        conv = []
        for v in bm.verts:
            n = v.normal
            vals = [n.dot((e.other_vert(v).co - v.co).normalized()) for e in v.link_edges if e.calc_length() > 1e-6]
            conv.append(sum(vals) / len(vals) if vals else 0.0)
        bm.free()
        layer = me.vertex_colors.new(name="Col")
        for poly in me.polygons:
            for li, vi in zip(poly.loop_indices, poly.vertices):
                c = conv[vi]
                wear = min(max((-c - 0.12) * 3.0, 0.0), 1.0)
                grime = min(max((c - 0.05) * 3.0, 0.0), 1.0)
                layer.data[li].color = (wear, grime, 0.0, 1.0)


for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
build_pillar(-1)
build_pillar(1)
build_bezel()
build_keys()
build_wings()
bake_masks()
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True)
print("wrote", OUT)
