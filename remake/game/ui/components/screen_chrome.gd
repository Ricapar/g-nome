@tool
class_name ScreenChrome
extends Control
## Ornaments on the centre screen: corner brackets and thin rule lines beside the title.

@export var color := Color(0.15, 0.9, 0.35, 0.55):
	set(v): color = v; queue_redraw()
@export var title_y := 0.065 ## title centre line as a fraction of the height
@export var title_gap := 0.36 ## half-width of the gap left for the title, as a fraction


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	var m := 14.0
	var k := 28.0
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p := Vector2(m + corner.x * (size.x - 2 * m), m + corner.y * (size.y - 2 * m))
		var dx := Vector2(k if corner.x == 0 else -k, 0)
		var dy := Vector2(0, k if corner.y == 0 else -k)
		draw_polyline(PackedVector2Array([p + dx, p, p + dy]), color, 2.0)
	var y := size.y * title_y
	var cx := size.x * 0.5
	for side: float in [-1.0, 1.0]:
		var a := cx + side * size.x * title_gap
		var b := cx + side * (size.x * 0.5 - 50.0)
		draw_line(Vector2(a, y), Vector2(b, y), Color(color, color.a * 0.7), 1.5)
		for t in 4:
			var x := lerpf(a, b, 0.15 + t * 0.06)
			draw_line(Vector2(x, y - 5), Vector2(x, y + 5), color, 2.0)
		draw_rect(Rect2(Vector2(b - side * 6 - 3, y - 3), Vector2(6, 6)), color)
