class_name DialogueBox extends CanvasLayer
## The text box along the bottom of the screen, X/Y style: text types out, Space/Enter/click shows
## it all or goes to the next box, a ▼ marks that more is coming.
##   await box.say(GameText.pages(...))
##   var picked := await box.ask(pages, ["Yes", "No"])

signal _advanced
signal _picked(index: int)

const CHARS_PER_SEC := 60.0

var speaker := "" # shown above the box when set
var _panel: PanelContainer
var _name: Label
var _text: Label
var _arrow: Label
var _choices: VBoxContainer
var _typing := false
var _visible_chars := 0.0


func _init() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -430
	_panel.offset_right = 430
	_panel.offset_top = -170
	_panel.offset_bottom = -24
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.96)
	style.border_color = Color(0.25, 0.55, 0.85)
	style.set_border_width_all(4)
	style.set_corner_radius_all(18)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_name = Label.new()
	_name.add_theme_color_override("font_color", Color(0.2, 0.45, 0.8))
	_name.add_theme_font_size_override("font_size", 18)
	box.add_child(_name)
	_text = Label.new()
	_text.add_theme_color_override("font_color", Color(0.18, 0.18, 0.2))
	_text.add_theme_font_size_override("font_size", 24)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_text)
	_arrow = Label.new()
	_arrow.text = "▼"
	_arrow.add_theme_color_override("font_color", Color(0.89, 0.24, 0.24))
	_arrow.anchor_left = 1.0
	_arrow.anchor_right = 1.0
	_arrow.anchor_top = 1.0
	_arrow.anchor_bottom = 1.0
	_arrow.offset_left = -36
	_arrow.offset_top = -34
	_panel.add_child.call_deferred(_arrow)
	_choices = VBoxContainer.new()
	_choices.anchor_left = 0.5
	_choices.anchor_right = 0.5
	_choices.anchor_top = 1.0
	_choices.anchor_bottom = 1.0
	_choices.offset_left = 300
	_choices.offset_right = 430
	_choices.offset_top = -290
	_choices.offset_bottom = -184
	_choices.alignment = BoxContainer.ALIGNMENT_END
	add_child(_choices)
	visible = false


## Shows each box in turn and returns when the player has read the last one.
func say(pages: PackedStringArray) -> void:
	visible = true
	for p in pages:
		await _show(p, true)
	visible = false


## Like say(), but the last box stays up with buttons; returns the index picked.
func ask(pages: PackedStringArray, options: Array) -> int:
	visible = true
	for i in pages.size():
		await _show(pages[i], i < pages.size() - 1)
	_arrow.visible = false
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.custom_minimum_size = Vector2(130, 44)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func() -> void: _picked.emit(i))
		_choices.add_child(b)
	(_choices.get_child(0) as Button).grab_focus()
	var picked: int = await _picked
	for c in _choices.get_children():
		c.queue_free()
	visible = false
	return picked


func _show(text: String, wait: bool) -> void:
	_name.text = speaker
	_name.visible = speaker != ""
	_text.text = text
	_visible_chars = 0
	_text.visible_characters = 0
	_typing = true
	_arrow.visible = false
	while _typing:
		await get_tree().process_frame
		_visible_chars += get_process_delta_time() * CHARS_PER_SEC
		_text.visible_characters = int(_visible_chars)
		if _visible_chars >= text.length():
			_typing = false
	_text.visible_characters = -1
	if wait:
		_arrow.visible = true
		await _advanced


func _process(_delta: float) -> void:
	if _arrow.visible:
		_arrow.offset_top = -34 + sin(Time.get_ticks_msec() / 150.0) * 3


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _choices.get_child_count() > 0:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_Z]) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if _typing:
		_typing = false # show the whole box at once
	else:
		_advanced.emit()
