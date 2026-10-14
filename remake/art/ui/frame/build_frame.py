"""Build the main menu machinery frame as a 3D model (Blender 2.91+, run headless).

    blender --factory-startup -b --python remake/art/ui/frame/build_frame.py -- <out.glb>

Target look: remake/art/ui/reference/target_briefing.png (see remake/UI-DESIGN.md). The core
spans a 16:9 view: x -9.6..9.6, z -5.4..5.4 (1 unit = 100 design px at 1080p); machinery past
x = +-9.6 is only seen on wider screens. Front faces point to -Y (glTF +Z, toward the camera).

Godot assigns the real materials by name (ui/frame/menu_frame.gd):
  red_paint, white_paint, steel_dark, steel_bezel, steel_drum, steel_brushed, steel_face,
  black_coat, hazard, rubber, rubber_red, glass_dark, recess, lamp_orange, lamp_red,
  lamp_yellow, lamp_white, led_0..led_4.
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
    "steel_bezel": (0.3, 0.3, 0.32), "steel_drum": (0.18, 0.18, 0.18),
    "steel_brushed": (0.55, 0.55, 0.55), "steel_face": (0.25, 0.25, 0.26), "black_coat": (0.02, 0.02, 0.02), "hazard": (0.6, 0.45, 0.05),
    "rubber": (0.03, 0.03, 0.03), "glass_dark": (0.0, 0.02, 0.02), "recess": (0.01, 0.01, 0.01), "lamp_orange": (1.0, 0.45, 0.05),
    "lamp_red": (1.0, 0.1, 0.05), "lamp_yellow": (1.0, 0.8, 0.1), "lamp_white": (1.0, 0.95, 0.85), "rubber_red": (0.3, 0.03, 0.02),
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


def ring(name, outer, inner, d, mat, y, slope=0.0, bevel=0.04, segments=3, angle=35, pivot=(0.0, 0.0), rot=(0, 0, 0)):
    """A frame between two outlines with the same vertex count; the inner edge sits `slope`
    deeper (toward +Y) than the outer edge, making a sloped bevel. rot (deg) about pivot."""
    assert len(outer) == len(inner)
    bm = bmesh.new()
    o = [bm.verts.new((x - pivot[0], 0, z - pivot[1])) for x, z in outer]
    i = [bm.verts.new((x - pivot[0], slope, z - pivot[1])) for x, z in inner]
    for k in range(len(o)):
        j = (k + 1) % len(o)
        bm.faces.new([o[k], o[j], i[j], i[k]])
    bm.normal_update()
    _extrude_back(bm, d)
    return _finish(bm, name, mat, (pivot[0], y, pivot[1]), rot, bevel, segments, angle)


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


def lamp(name, x, z, w, h, y, mat="lamp_orange", with_light=True, **plate):
    """plate = pivot/rot/curve keywords when the lamp sits on a curved armour plate."""
    prism("lamp_" + name, oct_(w, h, min(w, h) * 0.3, x, z), 0.04, mat, y, bevel=0.0, **plate)
    if with_light:
        light(name, x, z, y - 0.25)


def expand(pts, d):
    """Offset a convex outline outward by d (mitred corners), e.g. for a rim behind a plate."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    sgn = 1.0 if area > 0 else -1.0
    normals = []
    for i in range(n):
        e = Vector(pts[(i + 1) % n]) - Vector(pts[i])
        normals.append(Vector((e.y, -e.x)).normalized() * sgn)  # outward for a CCW outline
    out = []
    for i in range(n):
        n1, n2 = normals[i - 1], normals[i]
        m = (n1 + n2) * (d / max(1.0 + n1.dot(n2), 0.2))
        out.append((pts[i][0] + m.x, pts[i][1] + m.y))
    return out


# ---------------------------------------------------------------------------------- layout
EDGE = 9.6                       # outer edge of the 16:9 core
PW = 2.3                         # pillar width
SLOT_Z = [1.75, 0.85, -0.05, -0.95]
SLOT_W, SLOT_H = 1.72, 0.64
SCREEN_W, SCREEN_H, SCREEN_CZ = 13.2, 6.9, 1.15
SCREEN_CUT = (0.6, 0.3)          # glass corner chamfers (top, bottom); the 2D screen cuts the same
KEY_X = [-5.2, -2.6, 0.0, 2.6, 5.2]
KEY_W, KEY_H, KEY_CZ = 2.4, 1.12, -4.66  # narrower than the pitch (2.6): the turned keys need the gap
KEY_ARC_R = 22.0                 # the key bank bows toward the viewer: keys sit on this arc and turn with it


def screen_outline(w, h, ct, cb, cz=SCREEN_CZ):
    """Screen-shaped octagon: big chamfers at the top corners, smaller at the bottom."""
    return crect(w, h, ct, ct, cb, cb, 0, cz)


def build_pillar(s):
    """s = -1 left pillar, +1 right pillar. u = distance from the outer edge (0..PW)."""
    tag = "L" if s < 0 else "R"

    def X(u):
        return s * (EDGE - u)

    def P(pts):  # (u, z) -> (x, z)
        return [(X(u), z) for u, z in pts] if s < 0 else [(X(u), z) for u, z in reversed(pts)]

    yaw = -s * 9.0
    piv = (X(PW), 0.0)
    C = (X(PW / 2), 0.3)  # armour wraps around the pillar axis (the target's plates shade like drums)
    top = dict(pivot=piv, rot=(0, 0, yaw), curve=C)          # mounted on the top plate
    low = dict(pivot=piv, rot=(0, 0, yaw * 0.5), curve=C)    # mounted on the lower plate
    # core column
    prism("core_" + tag, P([(0.1, -5.6), (2.2, -5.6), (2.2, 5.9), (0.1, 5.9)]), 1.4, "steel_dark", -0.45)

    def on_plate(u, z, y_front, mount):
        """World position of the plate face at (u, z) for a plate mounted with `mount` (its yaw
        about the pivot and its curve), for cylinders that prism-style mounting cannot place."""
        x = X(u)
        cx, kk = mount["curve"]
        ry = kk * (x - cx) ** 2
        a = math.radians(mount["rot"][2])
        px = mount["pivot"][0]
        rx = x - px
        return (px + rx * math.cos(a) - ry * math.sin(a), y_front + rx * math.sin(a) + ry * math.cos(a), z)

    def rivets(name, uz, y, mount):
        for k, (u, z) in enumerate(uz):
            prism("bolt_%s_%s%d" % (name, tag, k), oct_(0.06, 0.06, 0.018, X(u), z), 0.035, "steel_brushed", y, bevel=0.006, segments=1, **mount)

    def row(a, b, n):
        return [(a[0] + (b[0] - a[0]) * t / (n - 1), a[1] + (b[1] - a[1]) * t / (n - 1)) for t in range(n)]

    def seam(name, a, b, y, mount, w=0.025):
        (u0, z0), (u1, z1) = a, b
        if abs(z1 - z0) < 1e-6:
            pts = [(u0, z0 - w / 2), (u1, z0 - w / 2), (u1, z0 + w / 2), (u0, z0 + w / 2)]
        else:
            pts = [(u0 - w / 2, z0), (u0 + w / 2, z0), (u1 + w / 2, z1), (u1 - w / 2, z1)]
        prism("seam_%s_%s" % (name, tag), P(pts), 0.02, "black_coat", y, bevel=0.0, **mount)

    def sub_plate(name, outline, y, mount, rim=0.05):
        """A raised armour layer with a steel rim showing around it."""
        prism(name + "_rim_" + tag, P(expand(outline, rim)), 0.22, "steel_dark", y + 0.04, bevel=0.03, **mount)
        prism(name + "_" + tag, P(outline), 0.25, "red_paint", y, bevel=0.05, **mount)

    def ram(name, u_socket, z0, y_front, mount, r_rod, r_socket, length):
        """A chrome rod running into a black socket on a bolted steel plate."""
        prism("%s_plate_%s_%.1f" % (name, tag, z0), oct_(0.64, 0.64, 0.15, X(u_socket), z0), 0.05, "steel_bezel", y_front - 0.04, bevel=0.01, **mount)
        rivets("%s_plate_%.1f" % (name, z0), [(u_socket + du, z0 + dz) for du in (-0.22, 0.22) for dz in (-0.22, 0.22)], y_front - 0.08, mount)
        a = math.radians(mount["rot"][2])
        sock = cylinder("%s_socket_%s_%.1f" % (name, tag, z0), r_socket, 0.34, "black_coat", on_plate(u_socket, z0, y_front - 0.12, mount), axis="X")
        rod = cylinder("%s_rod_%s_%.1f" % (name, tag, z0), r_rod, length, "steel_brushed", on_plate(u_socket - 0.8, z0, y_front - 0.12, mount), axis="X")
        nut = cylinder("%s_nut_%s_%.1f" % (name, tag, z0), r_socket * 0.95, 0.16, "steel_brushed", on_plate(u_socket - 0.3, z0, y_front - 0.12, mount), axis="X", segments=6, bevel=0.01)
        for o in (sock, rod, nut):
            o.rotation_euler.z += a

    # ---- top armour: a steel rim behind the main plate, a layered inner plate, a big white wedge
    # at the outer corner, a raised panel at the bottom with orange indicators and a vent, an
    # orange lamp strip on the inner edge, rams on bolted socket plates, hoses over the outer edge
    top_outline = [(0.0, 2.38), (PW, 2.38), (PW, 4.35), (1.55, 5.75), (0.0, 5.75)]
    prism("armour_top_rim_" + tag, P(expand(top_outline, 0.07)), 0.5, "steel_dark", -1.03, bevel=0.05, **top)
    prism("armour_top_" + tag, P(top_outline), 0.55, "red_paint", -1.1, bevel=0.07, **top)
    prism("armour_top_b_" + tag, P([(0.75, 3.3), (1.95, 3.3), (1.95, 4.15), (1.45, 4.75), (0.75, 4.75)]),
          0.3, "red_paint", -1.32, bevel=0.05, **top)
    prism("wedge_" + tag, P([(0.0, 5.65), (0.75, 5.65), (0.0, 3.95)]), 0.03, "white_paint", -1.13, bevel=0.008, segments=1, **top)
    prism("wedge_b_" + tag, P([(0.0, 3.75), (0.42, 3.75), (0.0, 3.2)]), 0.03, "white_paint", -1.13, bevel=0.008, segments=1, **top)
    for k in range(2 if s < 0 else 0):  # slashes on the left inner plate, the emblem decal on the right
        u0 = 0.95 + 0.42 * k
        prism("chevron_%s%d" % (tag, k), P([(u0, 3.45), (u0 + 0.2, 3.45), (u0 + 0.55, 3.95), (u0 + 0.55, 4.2), (u0, 3.6)]),
              0.03, "white_paint", -1.345, bevel=0.008, segments=1, **top)
    if s > 0:
        empty("decal_emblem_R", (X(1.35), -1.33, 4.02), (1.15, 1.0, 0.85))
    sub_plate("panel_top", [(0.15, 2.45), (2.2, 2.45), (2.2, 3.12), (0.15, 3.12)], -1.3, top)
    for k in range(3):
        prism("ind_%s%d" % (tag, k), P([(0.3, 2.56 + 0.17 * k), (0.7, 2.56 + 0.17 * k), (0.7, 2.66 + 0.17 * k), (0.3, 2.66 + 0.17 * k)]),
              0.03, "lamp_orange", -1.33, bevel=0.0, **top)
    light("ind_" + tag, X(0.5), 2.8, -1.65)
    prism("vent_frame_" + tag, P([(1.1, 2.52), (2.05, 2.52), (2.05, 3.05), (1.1, 3.05)]), 0.06, "steel_dark", -1.35, bevel=0.02, **top)
    for k in range(4):
        prism("vent_slat_%s%d" % (tag, k), P([(1.17, 2.59 + 0.11 * k), (1.98, 2.59 + 0.11 * k), (1.98, 2.64 + 0.11 * k), (1.17, 2.64 + 0.11 * k)]),
              0.03, "black_coat", -1.37, bevel=0.0, **top)
    prism("edge_housing_" + tag, P([(2.0, 3.0), (2.27, 3.0), (2.27, 4.3), (2.0, 4.3)]), 0.05, "black_coat", -1.14, bevel=0.01, **top)
    lamp("edge_" + tag, X(2.135), 3.65, 0.07, 1.05, -1.17, **top)
    seam("top_h", (0.1, 3.2), (2.2, 3.2), -1.115, top)
    rivets("top", row((0.12, 2.5), (0.12, 5.6), 8) + row((2.18, 2.5), (2.18, 4.25), 5) + row((0.6, 5.65), (1.45, 5.65), 3)
           + [(1.9, 5.3), (2.15, 4.75)] + row((0.85, 3.38), (1.85, 3.38), 3) + row((0.85, 4.65), (1.4, 4.65), 2), -1.15, top)
    rivets("panel_top", row((0.25, 2.52), (2.1, 2.52), 5) + row((0.25, 3.05), (2.1, 3.05), 5), -1.35, top)
    for z0 in (4.75, 3.05):
        ram("ram", 0.52, z0, -1.1, top, 0.085, 0.17, 1.5)
    cable("hose_%s0" % tag, [(X(0.25), -1.62, 5.5), (X(-0.15), -1.75, 4.0), (X(0.1), -1.7, 2.5), (X(0.35), -1.5, 2.3)], 0.07)
    cable("hose_%s1" % tag, [(X(0.5), -1.5, 5.5), (X(0.05), -1.62, 3.9), (X(0.3), -1.55, 2.35)], 0.05)
    # ---- collar stack: dark steel drums with a framed opening for each glass button
    cx = X(PW / 2)
    cylinder("collar_cap_top_" + tag, 1.2, 0.14, "steel_brushed", (cx, 0.0, 2.27))
    for i, z in enumerate(SLOT_Z):
        cylinder("drum_%s%d" % (tag, i), 1.1, 0.8, "steel_drum", (cx, 0.0, z), bevel=0.06)
        ring("drum_bezel_%s%d" % (tag, i), oct_(2.06, 0.84, 0.12, cx, z), oct_(SLOT_W + 0.06, SLOT_H + 0.06, 0.08, cx, z),
             0.25, "steel_dark", -1.2, slope=0.06, bevel=0.03)
        prism("drum_back_%s%d" % (tag, i), oct_(SLOT_W + 0.1, SLOT_H + 0.1, 0.08, cx, z), 0.1, "black_coat", -1.05, bevel=0.0)
        cylinder("drum_sep_%s%d" % (tag, i), 1.16, 0.1, "steel_brushed", (cx, 0.0, z - 0.45), bevel=0.02)
        lamp("slot_%s%d" % (tag, i), cx, z - 0.45, 0.22, 0.05, -1.18)
        anchor("slot_%s%d" % (tag, i), cx, z, SLOT_W, SLOT_H, -1.22)
    # ---- lower armour with a foot that reaches in under the key bar: hazard patch and grille at
    # the inner top, pistons on bolted socket plates at the outer edge, a raised foot plate with
    # the stencil, chevrons and an orange indicator panel
    low_outline = [(0.0, -1.5), (PW, -1.5), (PW, -3.85), (3.15, -4.45), (3.15, -5.6), (0.0, -5.6)]
    prism("armour_low_rim_" + tag, P(expand(low_outline, 0.07)), 0.5, "steel_dark", -1.03, bevel=0.05, **low)
    prism("armour_low_" + tag, P(low_outline), 0.55, "red_paint", -1.1, bevel=0.07, **low)
    prism("hazard_" + tag, P([(1.25, -1.6), (2.22, -1.6), (2.22, -1.92), (1.25, -1.92)]), 0.04, "hazard", -1.14, bevel=0.01, **low)
    prism("grille_frame_" + tag, P([(1.2, -2.05), (2.15, -2.05), (2.15, -3.3), (1.2, -3.3)]), 0.08, "steel_dark", -1.16, bevel=0.03, **low)
    for k in range(9):
        prism("grille_slat_%s%d" % (tag, k), P([(1.28, -2.17 - 0.12 * k), (2.07, -2.17 - 0.12 * k), (2.07, -2.22 - 0.12 * k), (1.28, -2.22 - 0.12 * k)]),
              0.03, "black_coat", -1.18, bevel=0.0, **low)
    sub_plate("foot", [(0.15, -3.98), (2.2, -3.98), (3.06, -4.5), (3.06, -5.5), (0.15, -5.5)], -1.3, low)
    empty("text_" + tag, (X(1.25), -1.36, -4.38))
    prism("ind_panel_" + tag, P([(2.66, -4.6), (3.0, -4.6), (3.0, -5.4), (2.66, -5.4)]), 0.04, "black_coat", -1.33, bevel=0.01, **low)
    for k in range(3):
        prism("ind_low_%s%d" % (tag, k), P([(2.73, -4.74 - 0.22 * k), (2.93, -4.74 - 0.22 * k), (2.93, -4.82 - 0.22 * k), (2.73, -4.82 - 0.22 * k)]),
              0.03, "lamp_orange", -1.36, bevel=0.0, **low)
    light("ind_low_" + tag, X(2.83), -4.95, -1.6)
    for k in range(2):
        u0 = 1.3 + 0.55 * k
        prism("foot_chevron_%s%d" % (tag, k), P([(u0, -5.3), (u0 + 0.28, -5.3), (u0 + 0.6, -4.95), (u0 + 0.32, -4.95)]),
              0.03, "white_paint", -1.34, bevel=0.008, segments=1, **low)
    seam("low_v", (1.05, -1.55), (1.05, -3.85), -1.115, low)
    rivets("low", row((0.12, -1.65), (0.12, -3.75), 6) + row((2.18, -1.65), (2.18, -3.7), 6) + row((0.5, -1.58), (1.0, -1.58), 2)
           + row((1.3, -2.0), (2.1, -2.0), 3) + row((1.3, -3.36), (2.1, -3.36), 3), -1.15, low)
    rivets("foot", row((0.26, -4.1), (2.1, -4.1), 5) + row((0.26, -5.4), (2.95, -5.4), 7) + row((0.26, -4.5), (0.26, -5.0), 2)
           + [(2.55, -4.3), (2.95, -4.7), (2.95, -5.1)], -1.35, low)
    for z0 in (-2.45, -3.6):
        ram("piston", 0.5, z0, -1.1, low, 0.11, 0.19, 1.3)
    # cables from the pillar into the machinery under the screen
    cable("cable_%s0" % tag, [(X(2.0), -1.0, -1.45), (X(2.6), -1.05, -2.2), (X(3.1), -0.95, -2.75)], 0.07)
    cable("cable_%s1" % tag, [(X(2.1), -0.8, -1.4), (X(2.9), -0.85, -2.0), (X(3.6), -0.8, -2.62)], 0.05)
    # hose runs in the gap between pillar and bezel, and a bundle into the key bar
    cable("run_%s0" % tag, [(X(2.33), -1.0, 5.4), (X(2.4), -1.05, 2.0), (X(2.36), -1.05, -1.3)], 0.08)
    cable("run_%s1" % tag, [(X(2.47), -0.95, 5.4), (X(2.52), -0.97, 1.0), (X(2.44), -0.95, -1.4)], 0.06, "rubber_red")
    cable("run_%s2" % tag, [(X(2.26), -0.9, 5.4), (X(2.3), -0.92, 0.3), (X(2.28), -0.9, -1.35)], 0.045)
    cable("bundle_%s0" % tag, [(X(2.7), -0.95, -2.6), (X(2.95), -1.15, -3.3), (X(3.05), -1.1, -3.95), (X(3.3), -0.75, -4.2)], 0.075)
    cable("bundle_%s1" % tag, [(X(2.85), -0.9, -2.62), (X(3.15), -1.08, -3.25), (X(3.2), -1.05, -3.9), (X(3.45), -0.7, -4.15)], 0.055, "rubber_red")
    cable("bundle_%s2" % tag, [(X(2.6), -0.85, -2.58), (X(2.8), -1.0, -3.4), (X(2.95), -0.95, -4.0), (X(3.2), -0.7, -4.25)], 0.04)


def build_bezel():
    """A narrow grey steel band with big chamfers at the top, a bright inner lip, then a dark
    sloped recess down to the glass. Above it a dark header strip fills the top of the view."""
    W, H = 13.9, 7.7
    ow, oh = SCREEN_W + 0.3, SCREEN_H + 0.4
    ct, cb = SCREEN_CUT
    ring("bezel_outer", screen_outline(W, H, ct + 0.4, cb + 0.2), screen_outline(ow, oh, ct + 0.18, cb + 0.1), 0.5, "steel_bezel", -0.9, bevel=0.06)
    ring("bezel_lip", screen_outline(ow + 0.02, oh + 0.02, ct + 0.19, cb + 0.11), screen_outline(ow - 0.08, oh - 0.08, ct + 0.14, cb + 0.08),
         0.06, "steel_brushed", -0.94, bevel=0.01, segments=1)
    ring("bezel_slope", screen_outline(ow - 0.08, oh - 0.08, ct + 0.14, cb + 0.08), screen_outline(SCREEN_W, SCREEN_H, ct, cb), 0.3, "steel_dark", -0.9,
         slope=0.4, bevel=0.02)
    prism("screen_glass", screen_outline(SCREEN_W + 0.04, SCREEN_H + 0.04, ct, cb), 0.05, "glass_dark", -0.44, bevel=0.0)
    anchor("screen", 0, SCREEN_CZ, SCREEN_W, SCREEN_H, -0.46)
    for x in (-5.6, -2.8, 2.8, 5.6):
        cylinder("bolt_%.2f" % x, 0.05, 0.06, "steel_brushed", (x, -0.93, SCREEN_CZ - H / 2 + 0.1), axis="Y", bevel=0.01, segments=16)
    for z in (SCREEN_CZ + 1.8, SCREEN_CZ - 1.8):
        for x in (-W / 2 + 0.1, W / 2 - 0.1):
            cylinder("bolt_side_%.1f_%.1f" % (x, z), 0.05, 0.06, "steel_brushed", (x, -0.93, z), axis="Y", bevel=0.01, segments=16)
    # raised steel clips over the bezel's top edge (the original has them in red; here steel)
    top = SCREEN_CZ + H / 2
    for x in (-4.3, 4.3):
        prism("clip_%.1f" % x, crect(1.6, 0.34, 0.1, 0.1, 0.0, 0.0, x, top + 0.04), 0.4, "steel_bezel", -0.97, bevel=0.03)
    # header strip: dark steel above the bezel up to the top of the view, a thin dark window,
    # small red LED modules and end lamps
    prism("header", crect(14.6, 1.1, cx=0, cz=top + 0.5), 0.7, "black_coat", -0.72, bevel=0.03)
    prism("header_window", crect(7.4, 0.1, cx=0, cz=top + 0.1), 0.03, "glass_dark", -0.74, bevel=0.0)
    for x in (-1.5, 1.5):
        prism("header_mod_%.1f" % x, oct_(0.56, 0.16, 0.03, x, top + 0.3), 0.05, "black_coat", -0.76, bevel=0.0)
        lamp("header_%.1f" % x, x, top + 0.3, 0.44, 0.07, -0.78, "lamp_red")
    for x in (-5.4, 5.4):
        lamp("header_end_%.1f" % x, x, top + 0.3, 0.22, 0.08, -0.74, "lamp_red", with_light=False)
    # machinery strip under the screen: a slim housing, lamp pods, a short light bar, pipes
    prism("under_strip", crect(13.8, 0.36, 0.08, 0.08, 0.08, 0.08, 0, -2.98), 0.6, "steel_dark", -0.85, bevel=0.03)
    lamp("under_bar", 2.6, -2.98, 0.8, 0.06, -0.87)
    lamp("under_white", -0.6, -2.98, 0.12, 0.1, -0.87, "lamp_white")
    for x in (-5.8, -4.0, -2.2, 2.2, 4.0, 5.8):
        cylinder("pod_%.1f" % x, 0.08, 0.08, "steel_brushed", (x, -0.9, -2.98), axis="Y", bevel=0.01, segments=20)
        lamp("pod_%.1f" % x, x, -2.98, 0.08, 0.08, -0.95, with_light=abs(x) > 5)
    for z, r in ((-2.78, 0.04), (-3.18, 0.05)):
        cylinder("under_pipe_%.2f" % z, r, 13.6, "rubber" if r > 0.045 else "steel_brushed", (0, -0.92, z), axis="X", bevel=0.0)
    # status housing: light steel rim with a recessed black channel
    ring("status_housing", oct_(13.0, 0.66, 0.14, 0, -3.55), oct_(12.45, 0.44, 0.07, 0, -3.55), 0.5, "steel_bezel", -0.85,
         slope=0.12, bevel=0.03)
    prism("status_channel", oct_(12.6, 0.5, 0.07, 0, -3.55), 0.05, "black_coat", -0.6, bevel=0.0)
    anchor("status", 0, -3.55, 12.45, 0.44, -0.86)


def build_keys():
    """A physical key bank seen in perspective: the tray bows toward the viewer and each key sits
    on that arc, turned with it (the outer keys splay and show their inner sides). A key is a
    chunky block whose label face leans back, with a lower chamfer that shows its depth, a
    chamfered steel frame around a worn face plate, and a black LED slot near the top edge.
    Each key's parts are children of an empty `key_root_i` at the key's place on the arc, so the
    press travel (MenuFrame.KEY_TRAVEL) stays in the key's own frame."""
    k = 1.0 / (2.0 * KEY_ARC_R)
    prism("key_base", crect(13.9, 1.6, 0.2, 0.2, 0.0, 0.0, 0, -4.72), 0.8, "steel_dark", -0.6, bevel=0.05, curve=(0.0, k))
    # a chamfered steel ledge along the bottom of the bank, in front of the keys' lower chamfer
    prism("key_ledge", crect(13.9, 0.24, 0.0, 0.0, 0.06, 0.06, 0, -5.5), 0.5, "steel_bezel", -1.22, bevel=0.05, curve=(0.0, k))
    # side profile (y, z) of a key body built at x = 0: the nose at (-1.25, -5.0) is the nearest
    # point; above it the label face leans back to (-0.98, -4.1), below it a chamfer drops to the base
    body = [(-1.0, -5.32), (-0.6, -5.32), (-0.6, -4.1), (-0.98, -4.1), (-1.25, -5.0)]
    tilt = math.degrees(math.atan2(0.27, 0.9))

    def y_face(z):  # the leaning label face at height z
        return -1.25 + 0.27 * ((z - (-5.0)) / 0.9)

    for i, x in enumerate(KEY_X):
        yaw = math.degrees(math.asin(x / KEY_ARC_R))  # turn with the arc: the outer edge recedes, the outer side shows
        rec = KEY_ARC_R - math.sqrt(KEY_ARC_R ** 2 - x * x)
        root = empty("key_root_%d" % i, (x, rec, 0))
        root.rotation_euler = Euler((0, 0, math.radians(yaw)))
        zc = -4.55
        zs = -4.27
        parts = [
            profile("key_body_%d" % i, body, -KEY_W / 2, KEY_W, "steel_dark", bevel=0.07),
            ring("key_frame_%d" % i, crect(KEY_W - 0.04, 0.98, 0.09, 0.09, 0.09, 0.09, 0, zc), crect(KEY_W - 0.18, 0.84, 0.06, 0.06, 0.06, 0.06, 0, zc),
                 0.05, "steel_bezel", y_face(zc) - 0.03, slope=0.012, bevel=0.012, segments=2, pivot=(0, zc), rot=(-tilt, 0, 0)),
            prism("key_plate_%d" % i, crect(KEY_W - 0.16, 0.86, 0.06, 0.06, 0.06, 0.06, 0, zc), 0.03, "steel_face",
                  y_face(zc) - 0.012, (0, zc), (-tilt, 0, 0), bevel=0.008),
            prism("key_slot_%d" % i, oct_(0.52, 0.12, 0.03, 0, zs), 0.02, "recess", y_face(zs) - 0.03, (0, zs), (-tilt, 0, 0), bevel=0.0),
            prism("key_led_%d" % i, oct_(0.38, 0.055, 0.02, 0, zs), 0.02, "led_%d" % i, y_face(zs) - 0.045, (0, zs), (-tilt, 0, 0), bevel=0.0),
            anchor("key_%d" % i, 0, zc, KEY_W - 0.2, 0.84, y_face(zc) - 0.04),  # the face; the label sits low in it
        ]
        for p in parts:
            p.parent = root
    for x in (-6.55, -3.9, -1.3, 1.3, 3.9, 6.55):
        lamp("gap_%.2f" % x, x, KEY_CZ, 0.035, 0.4, -1.0, with_light=abs(x) in (1.3, 6.55), curve=(0.0, k))


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
