class_name PartyMenu extends CanvasLayer
## The party window (P): your Pokémon on the left (icon, level, HP), the selected one's summary on
## the right (types, stats, EXP, moves). Reordering: click the selected Pokémon again, then the one
## to swap with — the first one leads in battle. The server keeps the order (POST /trainer/party/swap).

signal closed

const STAT_NAMES := [["atk", "Attack"], ["def", "Defense"], ["spa", "Sp. Atk"], ["spd", "Sp. Def"], ["spe", "Speed"]]

var _list: VBoxContainer
var _details: VBoxContainer
var _status: Label
var _party: Array = []
var _items := {}
var _selected := 0 # slot shown on the right
var _picked := -1 # slot picked for a swap


func _ready() -> void:
	layer = 8
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var w := Ui.window("Pokémon", close_menu)
	var root: Control = w.root
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(900, 540)
	root.position = Vector2(-450, -270)
	add_child(root)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	w.content.add_child(body)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.custom_minimum_size = Vector2(380, 0)
	body.add_child(_list)
	var right := Ui.panel(Color(0.06, 0.08, 0.11, 0.9))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 6)
	right.add_child(_details)
	_status = Ui.label("", 13, Ui.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	w.content.add_child(_status)
	await refresh()


func refresh() -> void:
	var data: Dictionary = await Session.get_party()
	_party = data.get("party", [])
	_items = data.get("items", {})
	_build()


func _build() -> void:
	for c in _list.get_children():
		c.queue_free()
	for p: Dictionary in _party:
		_list.add_child(_row(p))
	for i in range(_party.size(), 6):
		var empty := Ui.panel(Color(0.12, 0.14, 0.18, 0.4))
		empty.custom_minimum_size = Vector2(0, 66)
		_list.add_child(empty)
	if _picked >= 0:
		_status.text = "Pick the Pokémon to swap with %s (or the same one to cancel)." % _name_of(_picked)
	else:
		_status.text = "Click a Pokémon to see it, click it again to move it. The first one leads in battle.  ·  Walk into your front door in Vaniville to heal."
	_show_details(_by_slot(_selected) if _by_slot(_selected) else (_party[0] if not _party.is_empty() else {}))


func _row(p: Dictionary) -> Control:
	var slot := int(p.slot)
	var fainted := int(p.hp) <= 0
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 66)
	var base := Color(0.55, 0.45, 0.15) if slot == _picked else Color(0.3, 0.42, 0.62) if slot == _selected else Color(0.14, 0.17, 0.23)
	for state in ["normal", "hover", "pressed"]:
		var s := Ui.panel_style(base.lightened(0.1) if state == "hover" else base, 6)
		s.shadow_size = 0
		b.add_theme_stylebox_override(state, s)
	b.pressed.connect(_pick.bind(slot))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -10
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var icon := PokemonIcon.new(str(p.species), 2.0)
	icon.hop = slot == _selected and not fainted
	icon.fainted = fainted
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var name := Ui.label(str(p.name), 16)
	top.add_child(name)
	var g := Ui.label(" " + Ui.gender_symbol(p.get("gender")), 15, Ui.gender_color(p.get("gender")))
	top.add_child(g)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var badge := Ui.status_badge(p.get("status"), int(p.hp))
	if badge:
		top.add_child(badge)
	top.add_child(Ui.label("  Lv. %d" % int(p.level), 14, Ui.TEXT_DIM))
	var hp := StatBar.new(8)
	hp.set_value(int(p.hp), int(p.maxHp))
	col.add_child(hp)
	var hp_text := Ui.label("HP %d / %d" % [int(p.hp), int(p.maxHp)], 12, Ui.TEXT_DIM)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(hp_text)
	for c in [name, g, hp_text]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _show_details(p: Dictionary) -> void:
	for c in _details.get_children():
		c.queue_free()
	if p.is_empty():
		var none := Ui.label("You don't have any Pokémon yet.\n\nYour friends are waiting in Aquacorde Town, north of Vaniville.", 16, Ui.TEXT_DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD
		_details.add_child(none)
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_details.add_child(head)
	var icon := PokemonIcon.new(str(p.species), 3.0)
	icon.hop = int(p.hp) > 0
	icon.fainted = int(p.hp) <= 0
	head.add_child(icon)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	head.add_child(info)
	var title := HBoxContainer.new()
	info.add_child(title)
	title.add_child(Ui.label(str(p.name), 22))
	title.add_child(Ui.label("  " + Ui.gender_symbol(p.get("gender")), 20, Ui.gender_color(p.get("gender"))))
	title.add_child(Ui.label("   Lv. %d" % int(p.level), 18, Ui.TEXT_DIM))
	var types := HBoxContainer.new()
	types.add_theme_constant_override("separation", 4)
	info.add_child(types)
	for t: String in p.get("types", []):
		types.add_child(Ui.badge(t.to_upper(), Ui.TYPE_COLORS.get(t, Color.GRAY)))
	var badge := Ui.status_badge(p.get("status"), int(p.hp))
	if badge:
		types.add_child(badge)
	info.add_child(Ui.label("%s nature  ·  %s" % [p.get("nature", "?"), p.get("ability", "?")], 13, Ui.TEXT_DIM))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	_details.add_child(grid)
	_stat_row(grid, "HP", "%d / %d" % [int(p.hp), int(p.maxHp)], int(p.hp), int(p.maxHp), true)
	var stats: Dictionary = p.get("stats", {})
	var best := 1
	for s: Array in STAT_NAMES:
		best = maxi(best, int(stats.get(s[0], 0)))
	for s: Array in STAT_NAMES: # bars compare the stats with each other
		var v := int(stats.get(s[0], 0))
		_stat_row(grid, s[1], str(v), v, int(best * 1.15), false)
	var lo := int(p.get("levelExp", 0))
	var hi := int(p.get("nextLevelExp", 0))
	var exp := int(p.get("exp", 0))
	_stat_row(grid, "EXP", "%d to next Lv." % maxi(hi - exp, 0), exp - lo, maxi(hi - lo, 1), false, Ui.EXP_BLUE)

	_details.add_child(Ui.label("Moves", 15, Ui.TEXT_DIM))
	var moves := GridContainer.new()
	moves.columns = 2
	moves.add_theme_constant_override("h_separation", 6)
	moves.add_theme_constant_override("v_separation", 6)
	_details.add_child(moves)
	var infos: Array = p.get("moveInfo", [])
	if infos.is_empty(): # older server: names only
		for m: String in p.get("moves", []):
			infos.append({"name": m})
	for m: Dictionary in infos:
		moves.add_child(_move_card(m))


func _stat_row(grid: GridContainer, name: String, text: String, v: int, max_v: int, hp: bool, color := Color(0.55, 0.62, 0.75)) -> void:
	var l := Ui.label(name, 13, Ui.TEXT_DIM)
	l.custom_minimum_size.x = 60
	grid.add_child(l)
	var bar := StatBar.new(7, hp)
	bar.fill = color
	bar.custom_minimum_size.x = 200
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.set_value(v, max_v)
	grid.add_child(bar)
	grid.add_child(Ui.label(text, 13))


func _move_card(m: Dictionary) -> Control:
	var t: String = m.get("type", "")
	var color: Color = Ui.TYPE_COLORS.get(t, Color(0.3, 0.33, 0.4))
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = color.darkened(0.35)
	s.border_color = color
	s.set_border_width_all(1)
	s.border_width_left = 4
	s.set_corner_radius_all(5)
	s.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(210, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	p.add_child(col)
	col.add_child(Ui.label(str(m.name), 15))
	if m.has("type"):
		var power := "—" if int(m.get("power", 0)) == 0 else str(int(m.power))
		col.add_child(Ui.label("%s · %s · Pow %s · PP %d" % [t, m.get("category", ""), power, int(m.get("pp", 0))], 11, Color(1, 1, 1, 0.75)))
	return p


func _by_slot(slot: int) -> Variant:
	for p: Dictionary in _party:
		if int(p.slot) == slot:
			return p
	return null


func _name_of(slot: int) -> String:
	var p: Variant = _by_slot(slot)
	return str(p.name) if p is Dictionary else "?"


## Click a Pokémon to see it; click it again to pick it for a swap, then click the other one.
func _pick(slot: int) -> void:
	if _picked < 0 and slot != _selected:
		_selected = slot
		_build()
		return
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
	_selected = slot
	await refresh()


func close_menu() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_P, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		close_menu()
