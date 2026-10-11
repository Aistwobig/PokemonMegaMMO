class_name PartyMenu extends CanvasLayer
## The party screen (P in the world): your Pokémon with HP, level and moves, the selected one's
## details, and reordering — click one Pokémon, then another, to swap them (the first leads in
## battle). The server keeps the order (POST /trainer/party/swap).

signal closed

var _grid: GridContainer
var _details: Label
var _status: Label
var _party: Array = []
var _items := {}
var _picked := -1 # slot picked for a swap


func _ready() -> void:
	layer = 8
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1000, 560)
	panel.position = Vector2(-500, -280)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.14, 0.24, 0.97)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var title := Label.new()
	title.text = "Pokémon"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "Close (P)"
	close.pressed.connect(close_menu)
	top.add_child(close)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_grid)
	_details = Label.new()
	_details.custom_minimum_size = Vector2(300, 0)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD
	_details.add_theme_font_size_override("font_size", 17)
	body.add_child(_details)
	_status = Label.new()
	_status.modulate = Color(0.8, 0.9, 1)
	col.add_child(_status)
	await refresh()


func refresh() -> void:
	var data: Dictionary = await Session.get_party()
	_party = data.get("party", [])
	_items = data.get("items", {})
	_build()


func _build() -> void:
	for c in _grid.get_children():
		c.queue_free()
	if _party.is_empty():
		_details.text = "You don't have any Pokémon yet.\n\nYour friends are waiting in Aquacorde Town, north of Vaniville."
	for p: Dictionary in _party:
		_grid.add_child(_card(p))
	var balls := int(_items.get("pokeball", 0))
	_status.text = "Click a Pokémon, then another, to swap them. The first one leads in battle.   Poké Balls: %d   ·   Walk into your front door to heal." % balls
	if not _party.is_empty() and _details.text == "":
		_show_details(_party[0])


func _card(p: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(320, 120)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var fainted := int(p.hp) == 0
	var gender: String = {"M": " ♂", "F": " ♀"}.get(p.get("gender", ""), "")
	var status_text := " FNT" if fainted else (" " + str(p.status).to_upper()) if p.get("status") else ""
	b.text = "  %s%s   Lv. %d%s\n  HP %d / %d\n  %s" % [p.name, gender, int(p.level), status_text, int(p.hp), int(p.maxHp), " · ".join(p.get("moves", []))]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.75, 0.25) if int(p.slot) == _picked else Color(0.35, 0.2, 0.2) if fainted else Color(0.2, 0.45, 0.3)
	style.set_corner_radius_all(12)
	style.border_color = Color(1, 1, 1, 0.5)
	style.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = style.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(_pick.bind(int(p.slot)))
	b.mouse_entered.connect(_show_details.bind(p))
	return b


func _show_details(p: Dictionary) -> void:
	var s: Dictionary = p.get("stats", {})
	_details.text = "%s   Lv. %d\n%s nature · %s\n\nHP %d / %d\nAttack %d\nDefense %d\nSp. Atk %d\nSp. Def %d\nSpeed %d\n\nEXP %d (next level at %d)\n\nMoves:\n%s" % [
		p.name, int(p.level), p.get("nature", "?"), p.get("ability", "?"), int(p.hp), int(p.maxHp),
		int(s.get("atk", 0)), int(s.get("def", 0)), int(s.get("spa", 0)), int(s.get("spd", 0)), int(s.get("spe", 0)),
		int(p.get("exp", 0)), int(p.get("nextLevelExp", 0)), "\n".join(p.get("moves", []))]


## Click one, then another: they swap places.
func _pick(slot: int) -> void:
	if _picked < 0:
		_picked = slot
		_build()
		return
	var a := _picked
	_picked = -1
	if a == slot:
		_build()
		return
	var err := await Session.swap_party(a, slot)
	if err != "":
		_status.text = err
	await refresh()


func close_menu() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_P, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		close_menu()
