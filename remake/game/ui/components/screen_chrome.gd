@tool
class_name ScreenChrome
extends Control
## Ornaments on the centre screen (target look): a thin rule under the title with tick groups and
## end markers, and small readout dashes low in the corners. The glass itself (grid, inner border)
## is drawn by shaders/screen_glass.gdshader.

@export var color := Color(0.15, 0.9, 0.35, 0.55):
	set(v): color = v; queue_redraw()
@export var rule_y := 0.118 ## rule line as a fraction of the height (just under the title)
@export var margin := 0.035 ## side margin as a fraction of the width


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var y := size.y * rule_y
	var x0 := size.x * margin
	var x1 := size.x * (1.0 - margin)
	var dim := Color(color, color.a * 0.45)
	draw_line(Vector2(x0, y), Vector2(x1, y), dim, 1.0)
	# tick groups near both ends, a square marker at each end
	for side: float in [0.0, 1.0]:
		var xs := lerpf(x0, x1, side)
		var dir := 1.0 if side == 0.0 else -1.0
		draw_rect(Rect2(Vector2(xs - 2.0 + (dir * 2.0 if dir > 0 else -2.0), y - 2.5), Vector2(5, 5)), color)
		for t in 5:
			var x := xs + dir * (size.x * 0.06 + t * 5.0)
			draw_line(Vector2(x, y - 3.0), Vector2(x, y + 3.0), color, 1.0)
		var xd := xs + dir * size.x * 0.12
		draw_line(Vector2(xd, y - 1.0), Vector2(xd + dir * 26.0, y - 1.0), color, 2.0)
	# readout dashes low in the corners (decoration, like a dormant data readout)
	var yb := size.y * 0.955
	for side: float in [0.0, 1.0]:
		var xs := lerpf(x0, x1, side)
		var dir := 1.0 if side == 0.0 else -1.0
		for t in 9:
			var w := 3.0 if t % 3 == 1 else 6.0
			var x := xs + dir * (t * 9.0)
			draw_line(Vector2(x, yb), Vector2(x + dir * w, yb), Color(color, color.a * (0.4 if t % 2 else 0.8)), 2.0)
		var xr := xs + dir * size.x * 0.11
		draw_line(Vector2(xr, yb), Vector2(xr + dir * 40.0, yb), dim, 1.0)
		draw_line(Vector2(xr + dir * 40.0, yb), Vector2(xr + dir * 50.0, yb - 10.0), dim, 1.0)
