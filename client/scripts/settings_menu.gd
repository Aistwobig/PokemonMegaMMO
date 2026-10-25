class_name SettingsMenu extends CanvasLayer
## The game menu (Esc): music volume, the soundtrack player, and logging out.

signal closed
signal logout_requested

var _now: Label
var _jukebox: ItemList
var _tracks: Array[String] = []


func _ready() -> void:
	layer = 8
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var w := Ui.window("Menu", close_menu)
	var root: Control = w.root
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(520, 520)
	root.position = Vector2(-260, -260)
	add_child(root)
	var c: VBoxContainer = w.content

	c.add_child(Ui.label("Music volume", 14, Ui.TEXT_DIM))
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 100
	vol.value = Music.volume * 100
	vol.focus_mode = Control.FOCUS_NONE
	vol.value_changed.connect(func(v: float) -> void: Music.volume = v / 100.0)
	vol.drag_ended.connect(func(_c: bool) -> void: Music.save_settings())
	c.add_child(vol)

	c.add_child(Ui.label("Soundtrack", 14, Ui.TEXT_DIM))
	_now = Ui.label("", 13)
	c.add_child(_now)
	_jukebox = ItemList.new()
	_jukebox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_jukebox.focus_mode = Control.FOCUS_NONE
	_jukebox.add_theme_font_size_override("font_size", 13)
	_jukebox.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.05, 0.06, 0.09, 0.9), 4))
	_jukebox.item_clicked.connect(func(i: int, _p: Vector2, _b: int) -> void: _play_track(i))
	c.add_child(_jukebox)
	if DirAccess.dir_exists_absolute(Music.DIR):
		for f in DirAccess.get_files_at(Music.DIR):
			if f.ends_with(".mp3"):
				_tracks.append(f.get_basename())
	_tracks.sort()
	for t in _tracks:
		_jukebox.add_item(t.trim_prefix("bgm_xy_").trim_prefix("me_xy_") + ("  (jingle)" if t.begins_with("me_") else ""))
	if _tracks.is_empty():
		_jukebox.add_item("No music yet: run Import.bat again to add the soundtrack.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	c.add_child(row)
	row.add_child(Ui.button("Back to the area's music", _area_music))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(Ui.button("Log out", logout_requested.emit, Color(0.55, 0.2, 0.2)))
	_update_now()


func _play_track(i: int) -> void:
	if i >= _tracks.size():
		return
	var t := _tracks[i]
	if t.begins_with("me_"):
		Music.jingle(t)
	else:
		Music.play(t, 0.4)
	_update_now()


func _area_music() -> void:
	var world := get_parent()
	if world and world.has_method("current_map"):
		Music.play_map(world.current_map())
	_update_now()


func _update_now() -> void:
	_now.text = "Now playing: " + (Music.current if Music.current != "" else "—")


func close_menu() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_menu()
