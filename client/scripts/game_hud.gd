class_name GameHud extends CanvasLayer
## The in-world HUD, PokeMMO-style: your trainer and money top left with the party bar under it
## (menu icons with HP), the hotbar bottom right, and the place name sliding in when you arrive.
## Buttons and their keys (P, B, C, Esc) ask the world to open things through `requested`, so the
## world can say no while a battle or a talk is on screen.

signal requested(what: String) # "party", "bag", "look", "settings"

const PLACE_NAMES := {
	"vaniville": "Vaniville Town", "route1": "Route 1", "aquacorde": "Aquacorde Town", "route2": "Route 2",
}
const HOTBAR := [
	["party", "Pokémon", "P"], ["bag", "Bag", "B"], ["look", "Look", "C"], ["settings", "Menu", "Esc"],
]

var status: Label # connection messages from the world
var _name: Label
var _money: Label
var _place: Label
var _slots: Array = [] # {root, icon, bar, level}
var _banner: PanelContainer
var _banner_label: Label
var _banner_tween: Tween
var _place_id := ""


func _ready() -> void:
	layer = 4
	# Top left: trainer plate + party bar.
	var top := VBoxContainer.new()
	top.position = Vector2(12, 10)
	top.add_theme_constant_override("separation", 6)
	add_child(top)
	var plate := Ui.panel()
	top.add_child(plate)
	var plate_row := HBoxContainer.new()
	plate_row.add_theme_constant_override("separation", 14)
	plate.add_child(plate_row)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 0)
	plate_row.add_child(who)
	_name = Ui.label(Session.trainer.get("name", "Trainer"), 17)
	who.add_child(_name)
	_place = Ui.label("", 13, Ui.TEXT_DIM)
	who.add_child(_place)
	_money = Ui.label("", 16, Ui.GOLD)
	_money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate_row.add_child(_money)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	top.add_child(bar)
	for i in 6:
		_slots.append(_party_slot(bar, i))
	status = Ui.label("", 15)
	status.add_theme_constant_override("outline_size", 6)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	top.add_child(status)

	# Bottom right: hotbar.
	var hot := HBoxContainer.new()
	hot.add_theme_constant_override("separation", 4)
	hot.anchor_left = 1.0
	hot.anchor_right = 1.0
	hot.anchor_top = 1.0
	hot.anchor_bottom = 1.0
	hot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hot.offset_right = -12
	hot.offset_bottom = -12
	add_child(hot)
	for h: Array in HOTBAR:
		var b := Ui.button("%s  [%s]" % [h[1], h[2]], requested.emit.bind(h[0]), Color(0.12, 0.15, 0.2, 0.9), 14)
		hot.add_child(b)

	# Top center: the place name, shown on arrival.
	_banner = Ui.panel(Color(0.09, 0.11, 0.15, 0.85))
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = -60
	_banner.custom_minimum_size = Vector2(260, 0)
	_banner_label = Ui.label("", 22)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_label)
	_banner.visible = false
	add_child(_banner)
	refresh()


func _party_slot(parent: Container, index: int) -> Dictionary:
	var root := PanelContainer.new()
	var style := Ui.panel_style(Color(0.09, 0.11, 0.15, 0.85), 5)
	style.set_content_margin_all(4)
	root.add_theme_stylebox_override("panel", style)
	root.custom_minimum_size = Vector2(88, 0)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			requested.emit("party"))
	parent.add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	root.add_child(col)
	var icon := PokemonIcon.new("", 2.0)
	col.add_child(icon)
	var level := Ui.label("", 11, Ui.TEXT_DIM)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(level)
	var hp := StatBar.new(5)
	col.add_child(hp)
	return {"root": root, "icon": icon, "bar": hp, "level": level, "index": index}


## Reloads the party and money from the server (after battles, healing, swaps...).
func refresh() -> void:
	var data: Dictionary = await Session.get_party()
	if not is_inside_tree():
		return
	_money.text = Ui.money(int(data.get("money", 0)))
	var party: Array = data.get("party", [])
	for s: Dictionary in _slots:
		var p: Variant = party[s.index] if s.index < party.size() else null
		var root: Control = s.root
		if p is Dictionary:
			root.modulate = Color.WHITE
			s.icon.species = str(p.species)
			s.icon.fainted = int(p.hp) <= 0
			s.icon.hop = s.index == 0 and int(p.hp) > 0
			s.level.text = "Lv. %d" % int(p.level)
			s.bar.visible = true
			s.bar.set_value(int(p.hp), int(p.maxHp))
			var status_text := "  [%s]" % str(p.status).to_upper() if p.get("status") else ""
			root.tooltip_text = "%s %s  Lv. %d%s\nHP %d / %d" % [p.name, Ui.gender_symbol(p.get("gender")), int(p.level), status_text, int(p.hp), int(p.maxHp)]
		else:
			root.modulate = Color(1, 1, 1, 0.35)
			s.icon.species = ""
			s.icon.hop = false
			s.level.text = ""
			s.bar.visible = false
			root.tooltip_text = ""


## A new map: the place name in the plate, and the banner if it's a different place.
func set_place(map_id: String) -> void:
	var place: String = PLACE_NAMES.get(map_id, map_id.capitalize())
	_place.text = place
	if map_id == _place_id:
		return
	_place_id = map_id
	_banner_label.text = place
	_banner.visible = true
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "offset_top", 14.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(2.2)
	_banner_tween.tween_property(_banner, "offset_top", -60.0, 0.3).set_ease(Tween.EASE_IN)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var what := ""
	match event.keycode:
		KEY_P: what = "party"
		KEY_B: what = "bag"
		KEY_C: what = "look"
		KEY_ESCAPE: what = "settings"
	if what != "":
		get_viewport().set_input_as_handled()
		requested.emit(what)
