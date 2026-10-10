extends Node3D
## Character creation: pick girl/boy, skin, face, hair, clothes and colors on a turning preview,
## then save the look to the server. Shown after register, and from the world with C.

signal saved

const WORLD_SCENE := "res://scenes/world.tscn"
## Rows in the order shown. Clothing rows offer every part of that category in the manifest.
const ROWS := [
	["skin", "Skin"], ["face", "Face"], ["hair", "Hair"], ["hair_color", "Hair color"],
	["hat", "Hat"], ["point", "Hat accessory"], ["tops", "Top"], ["btms", "Bottoms"],
	["socks", "Legs"], ["shoes", "Shoes"], ["bag", "Bag"],
]
const OPTIONAL := ["hat", "point"] # may be "None"
## Friendlier names for part styles: keyed by what follows "<set>_<category>_" in the part name
## (the rest are derived from it).
const STYLE_NAMES := {
	"shoes_socks": "Shoes", "shoes00": "Socks only",
	"hun": "Hunting cap", "hat": "Fedora", "can": "Canotier", "cas": "Casquette", "cap": "Cap", "knit": "Knit cap",
	"poke": "Poké Ball cap", "noslee": "Sleeveless", "puffslee": "Puff sleeves", "tievest": "Tie vest",
	"tshirt": "T-shirt", "lpants": "Long pants", "tspants": "Shorts", "scargo": "Cargo shorts", "skinny": "Skinny jeans",
	"askirt": "A-line skirt", "pskirt": "Pleated skirt", "tskirt": "Tiered skirt", "sboots": "Short boots",
	"lboots": "Long boots", "shoes": "Flats", "midi": "Medium", "vshort": "Very short", "perm": "Wavy",
	"pony": "Ponytail", "twin": "Twin tails", "bob": "Bob", "long": "Long", "short": "Short",
}

## When true (opened from the world), saving returns to the world instead of entering it fresh.
@export var return_to_world := true
## Text of the save button; empty = "Start adventure" for new trainers, "Save" otherwise.
@export var confirm_text := ""

var look: Dictionary
var _preview: TrainerModel
var _turntable: Node3D
var _labels := {} # row -> Label
var _status: Label
var _save: Button
var _dragging := false


func _ready() -> void:
	look = Session.trainer.get("appearance") if Session.has_appearance() else TrainerModel.default_look("f1")
	look = look.duplicate(true)
	_build_scene()
	_build_ui()
	_refresh()


func _process(delta: float) -> void:
	if not _dragging:
		_turntable.rotation.y += delta * 0.6


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_turntable.rotation.y += event.relative.x * 0.01


# --- choices ------------------------------------------------------------------------------------

## Steps a row's style (or value) forward/back.
func step_style(row: String, dir: int) -> void:
	match row:
		"skin":
			look.skinTone = posmod(int(look.get("skinTone", 0)) + dir, TrainerModel.SKIN_TONES.size())
		"hair_color":
			look.hairColor = posmod(int(look.get("hairColor", 0)) + dir, TrainerModel.HAIR_COLORS.size())
		"socks":
			_step_color("socks", dir)
		"tops":
			# Girls' one-pieces live in the same row as tops; picking one hides the bottoms.
			var options := _parts_for("tops") + _parts_for("body")
			var current: String = look.parts.get("body", look.parts.get("tops", {})).get("part", "")
			var next: String = options[posmod(options.find(current) + dir, options.size())]
			look.parts.erase("tops")
			look.parts.erase("body")
			var slot := "body" if _category(next) == "body" else "tops"
			look.parts[slot] = {"part": next, "color": _first(_colors_of(next))}
			if slot == "tops" and not look.parts.has("btms"):
				var btms := _parts_for("btms")
				look.parts.btms = {"part": btms[0], "color": _first(_colors_of(btms[0]))}
			elif slot == "body":
				look.parts.erase("btms")
		_:
			var options: Array = _parts_for(row)
			if row in OPTIONAL:
				options = [""] + options
			var current: String = look.parts.get(row, {}).get("part", "")
			var next: String = options[posmod(options.find(current) + dir, options.size())]
			if next == "":
				look.parts.erase(row)
				if row == "hat":
					look.parts.erase("point") # accessories sit on the hat
			else:
				look.parts[row] = {"part": next, "color": _first(_colors_of(next))}
				if row == "point" and not look.parts.has("hat"):
					var hats := _parts_for("hat")
					look.parts.hat = {"part": hats[0], "color": _first(_colors_of(hats[0]))}
	_refresh()


func step_color(row: String, dir: int) -> void:
	_step_color("body" if row == "tops" and look.parts.has("body") else row, dir)
	_refresh()


func set_gender(gender: String) -> void:
	if gender == look.gender:
		return
	var keep := {"skinTone": look.get("skinTone", 0), "hairColor": look.get("hairColor", 0)}
	look = TrainerModel.default_look(gender)
	look.merge(keep, true)
	_refresh()


func randomize_look() -> void:
	for row: Array in ROWS:
		for i in randi() % 12:
			step_style(row[0], 1)
		for i in randi() % 8:
			_step_color(row[0], 1)
	_refresh()


func _step_color(slot: String, dir: int) -> void:
	var choice: Dictionary = look.parts.get(slot, {})
	if slot == "socks" and choice.is_empty():
		choice = {"part": "f1_socks_tights", "color": "none"}
	if choice.is_empty():
		return
	var colors := _colors_of(choice.part)
	if colors.is_empty():
		return
	choice.color = colors[posmod(colors.find(choice.get("color", "")) + dir, colors.size())]
	look.parts[slot] = choice


func _parts_for(category: String) -> Array:
	var manifest := TrainerModel.get_manifest(look.gender)
	var names := []
	for name: String in manifest:
		# Pajamas belong to bedtime scenes; the stand parts are photo props.
		if manifest[name].category == category and not name.contains("pajama"):
			names.append(name)
	names.sort()
	return names


func _colors_of(part: String) -> Array:
	var colors := {}
	var entry: Dictionary = TrainerModel.get_manifest(look.gender).get(part, {})
	for m: Dictionary in entry.get("materials", []):
		# Some shoes carry an ankle strip of the legs mesh; its sock styles aren't shoe colors.
		if m.get("stem", "").ends_with("_socks_") and entry.get("category") != "socks":
			continue
		for v in m.variants:
			colors[v] = true
	var list := colors.keys()
	list.sort()
	return list


func _category(part: String) -> String:
	return TrainerModel.get_manifest(look.gender).get(part, {}).get("category", "")


func _first(list: Array) -> String:
	return list[0] if not list.is_empty() else ""


# --- display ------------------------------------------------------------------------------------

func _refresh() -> void:
	if _preview:
		_preview.queue_free()
	_preview = TrainerModel.from_look(look)
	if _preview:
		_turntable.add_child(_preview)
		_preview.play_motion(TrainerModel.MOTION_STAND)
	for row: Array in ROWS:
		var key: String = row[0]
		var label: Label = _labels[key]
		label.get_parent().visible = _row_visible(key)
		label.text = _describe(key)


func _row_visible(row: String) -> bool:
	match row:
		"socks": return look.gender == "f1"
		"btms": return not look.parts.has("body")
	return true


func _describe(row: String) -> String:
	match row:
		"skin": return "Tone %d" % (int(look.get("skinTone", 0)) + 1)
		"hair_color": return "Color %d" % (int(look.get("hairColor", 0)) + 1)
		"socks":
			var code: String = look.parts.get("socks", {}).get("color", "none")
			return "Bare" if code == "none" else _sock_name(code)
	var slot := "body" if row == "tops" and look.parts.has("body") else row
	var choice: Dictionary = look.parts.get(slot, {})
	if choice.is_empty():
		return "None"
	var text := _style_name(choice.part)
	var colors := _colors_of(choice.part)
	if colors.size() > 1:
		text += "  ·  %d/%d" % [colors.find(choice.get("color", "")) + 1, colors.size()]
	return text


func _style_name(part: String) -> String:
	if part.ends_with("_mae"):
		return _style_name(part.trim_suffix("_mae")) + " with bangs"
	var bits := part.split("_", true, 2) # "f1", "tops", "noslee" / "f1", "face01"
	if bits.size() < 3:
		var number := bits[1].right(2)
		return bits[1].rstrip("0123456789").capitalize() + (" %d" % (int(number) + 1) if number.is_valid_int() else "")
	var key: String = bits[2]
	if STYLE_NAMES.has(key):
		return STYLE_NAMES[key]
	var last: String = key.split("_")[-1]
	var name: String = STYLE_NAMES.get(last, last.capitalize().rstrip("0123456789").strip_edges())
	return ("One-piece " + name.to_lower()) if bits[1] == "body" else name


func _sock_name(code: String) -> String:
	if code.begins_with("kd"): return "Knee socks %s" % code.right(2)
	if code.begins_with("od"): return "Tights %s" % code.right(2)
	return "Socks %s" % code.right(2)


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.17, 0.27)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.55
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 0.8
	add_child(sun)
	_turntable = Node3D.new()
	_turntable.position.x = 18 # the panel takes the left side of the screen
	add_child(_turntable)
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 40, 150), Vector3(0, 26, 0))
	cam.make_current() # also when shown inside another scene (the intro)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(32, 32)
	panel.custom_minimum_size = Vector2(430, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.18, 0.92)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Create your trainer" if not Session.has_appearance() else "Change your look"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var who := Label.new()
	who.text = Session.trainer.get("name", "")
	who.modulate = Color(1, 1, 1, 0.6)
	box.add_child(who)

	var genders := HBoxContainer.new()
	for g: Array in [["f1", "Girl"], ["f2", "Boy"]]:
		var b := Button.new()
		b.text = g[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_gender.bind(g[0]))
		genders.add_child(b)
	box.add_child(genders)

	for row: Array in ROWS:
		box.add_child(_row(row[0], row[1]))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var random := Button.new()
	random.text = "Random"
	random.pressed.connect(randomize_look)
	actions.add_child(random)
	_save = Button.new()
	_save.text = confirm_text if confirm_text != "" else "Save" if Session.has_appearance() else "Start adventure"
	_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var red := StyleBoxFlat.new()
	red.bg_color = Color(0.89, 0.24, 0.24)
	red.set_corner_radius_all(8)
	red.content_margin_top = 8
	red.content_margin_bottom = 8
	for s in ["normal", "hover", "pressed"]:
		_save.add_theme_stylebox_override(s, red)
	_save.pressed.connect(save)
	actions.add_child(_save)
	box.add_child(actions)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.modulate = Color(1, 0.6, 0.55)
	box.add_child(_status)


func _row(key: String, title: String) -> Control:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = title
	name_label.custom_minimum_size.x = 120
	name_label.modulate = Color(1, 1, 1, 0.7)
	row.add_child(name_label)
	row.add_child(_arrow("‹", step_style.bind(key, -1)))
	var value := Label.new()
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.clip_text = true
	row.add_child(value)
	row.add_child(_arrow("›", step_style.bind(key, 1)))
	var has_colors := key in ["hat", "point", "tops", "btms", "shoes", "bag"]
	var color := _arrow("◐", step_color.bind(key, 1))
	color.tooltip_text = "Next color"
	color.modulate = Color(1, 1, 1, 1 if has_colors else 0)
	color.disabled = not has_colors
	row.add_child(color)
	_labels[key] = value
	return row


func _arrow(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(34, 0)
	b.pressed.connect(action)
	return b


func save() -> void:
	_save.disabled = true
	_status.text = ""
	var err := await Session.save_appearance(look)
	_save.disabled = false
	if err != "":
		_status.text = err
		return
	saved.emit()
	if return_to_world:
		get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)
