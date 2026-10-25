class_name StatBar extends Control
## An HP or EXP bar. HP bars change color with how much is left (green → yellow → red);
## set_value(..., true) slides there like X/Y's bars.

var value := 0.0
var max_value := 1.0
var color_by_ratio := true # HP colors; false = fixed `fill` (EXP)
var fill := Ui.EXP_BLUE
var _shown := 0.0 # ratio drawn right now (animates towards value / max)
var _tween: Tween


func _init(height := 8.0, is_hp := true) -> void:
	custom_minimum_size = Vector2(0, height)
	color_by_ratio = is_hp
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_value(v: float, max_v: float, animate := false) -> void:
	value = v
	max_value = maxf(max_v, 1.0)
	var target := clampf(value / max_value, 0.0, 1.0)
	if _tween:
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween()
		_tween.tween_method(_show, _shown, target, 0.25 + absf(target - _shown) * 0.6)
	else:
		_show(target)


func _show(ratio: float) -> void:
	_shown = ratio
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.05, 0.06, 0.08, 0.9))
	var inner := r.grow(-1)
	var c := Ui.hp_color(_shown) if color_by_ratio else fill
	if _shown > 0:
		var w := maxf(inner.size.x * _shown, 2.0)
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), c)
		# a lighter top half, like the 3DS bars
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y * 0.4)), c.lightened(0.25))
	draw_rect(r, Color(1, 1, 1, 0.18), false, 1.0)
