class_name ScreenFade extends CanvasLayer
## Full-screen fade for scene changes and cutscenes: await fade.to(Color.BLACK), await fade.clear().

var _rect: ColorRect


func _init(start := Color.BLACK) -> void:
	layer = 20
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = start
	add_child(_rect)


func to(color: Color, seconds := 0.6) -> void:
	color.a = 1.0
	var from := color
	from.a = _rect.color.a if _rect.color.a > 0 else 0.0
	_rect.color = from
	await create_tween().tween_property(_rect, "color:a", 1.0, seconds).finished


func clear(seconds := 0.6) -> void:
	await create_tween().tween_property(_rect, "color:a", 0.0, seconds).finished
