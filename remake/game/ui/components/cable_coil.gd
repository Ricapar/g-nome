@tool
class_name CableCoil
extends Control
## A coiled cable (vector): drawn loops with a dark outline, the cable colour and a highlight.

@export var color := Color("#c9a227"):
	set(v): color = v; queue_redraw()
@export var loops := 7:
	set(v): loops = v; queue_redraw()
@export var thickness := 5.0:
	set(v): thickness = v; queue_redraw()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	# a spring lying on its side: tall, narrow loops
	var ry := size.y * 0.5 - thickness
	var rx := maxf(size.x / (loops + 1) * 0.75, thickness)
	var step := (size.x - 2.0 * rx) / maxf(loops - 1, 1)
	# back halves first (darker), then front halves
	for pass_i in 2:
		for i in loops:
			var cx := rx + i * step
			var c := Vector2(cx, size.y * 0.5)
			var a0 := PI * 0.5 if pass_i == 0 else -PI * 0.5
			var shade := 0.45 if pass_i == 0 else 1.0
			_arc(c, rx, ry, a0, a0 + PI, thickness + 2.0, Color(0.03, 0.03, 0.03))
			_arc(c, rx, ry, a0, a0 + PI, thickness, color * shade)
			if pass_i == 1:
				_arc(c + Vector2(-0.5, -thickness * 0.25), rx, ry, -PI * 0.85, -PI * 0.35, thickness * 0.3, color.lightened(0.5))


func _arc(c: Vector2, rx: float, ry: float, a0: float, a1: float, w: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for k in n + 1:
		var a := lerpf(a0, a1, float(k) / n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, w, true)
