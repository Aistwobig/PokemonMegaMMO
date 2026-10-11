class_name StarterChoice extends Node3D
## Picking the first Pokémon in Aquacorde, as at the café table in X/Y: Chespin, Fennekin and
## Froakie stand in front of the player and the friends ask which one will be their partner.
## Lines from story text 49; the server decides (POST /trainer/starter).

signal finished

const STARTERS := [["chespin", "Chespin", "Grass"], ["fennekin", "Fennekin", "Fire"], ["froakie", "Froakie", "Water"]]

var _trainer: Node3D
var _camera: Camera3D
var _box: DialogueBox
var _ui: CanvasLayer
var _models: Array[NpcModel] = []


func _init(trainer: Node3D) -> void:
	_trainer = trainer


func _ready() -> void:
	var origin := _trainer.global_position
	var yaw := deg_to_rad(_trainer.rotation_degrees.y)
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var left := Vector3(forward.z, 0, -forward.x) # screen left, seen from behind the player
	for i in STARTERS.size():
		var mon := NpcModel.create(STARTERS[i][0], NpcModel.POKEMON)
		if mon == null:
			continue
		add_child(mon)
		var at := origin + forward * 46 + left * (1 - i) * 30 # Chespin on the left, like the buttons
		mon.global_position = at
		mon.look_at(at - forward, Vector3.UP, true)
		mon.scale = Vector3.ONE * _fit(mon, 26.0)
		mon.play_motion(0)
		_models.append(mon)
	_camera = Camera3D.new()
	_camera.fov = 34
	add_child(_camera)
	_camera.global_position = origin - forward * 20 + Vector3.UP * 70
	_camera.look_at(origin + forward * 46 + Vector3.UP * 8)
	_trainer.visible = false # the camera stands where the player is
	_camera.make_current()
	_box = DialogueBox.new()
	add_child(_box)
	_ui = CanvasLayer.new()
	add_child(_ui)
	_run()


func _run() -> void:
	var name: String = Session.trainer.get("name", "Trainer")
	var g := Session.gender()
	_box.speaker = "Shauna"
	await _box.say(GameText.pages(GameText.AQUACORDE, 0, name, g)) # Hey! This way! Over here!
	_box.speaker = "Tierno"
	await _box.say(GameText.pages(GameText.AQUACORDE, 31, name, g)) # Here you are! Which one will be your partner?
	while true:
		var species: String = await _pick()
		_box.speaker = ""
		var err := await Session.choose_starter(species)
		if err == "":
			var pretty: String = STARTERS.filter(func(s: Array) -> bool: return s[0] == species)[0][1]
			await _box.say(PackedStringArray(["%s received %s!" % [name, pretty]]))
			break
		await _box.say(PackedStringArray([err]))
		if "already" in err:
			break
	_trainer.visible = true
	finished.emit()
	queue_free()


## Three buttons, one per starter; returns the species picked.
func _pick() -> String:
	var row := HBoxContainer.new()
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_left = -330
	row.offset_right = 330
	row.offset_top = -120
	row.offset_bottom = -40
	row.add_theme_constant_override("separation", 16)
	_ui.add_child(row)
	var colors := {"Grass": Color(0.35, 0.7, 0.3), "Fire": Color(0.9, 0.45, 0.2), "Water": Color(0.3, 0.55, 0.9)}
	var picked := [""]
	for s: Array in STARTERS:
		var b := Button.new()
		b.text = "%s\n%s type" % [s[1], s[2]]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		var style := StyleBoxFlat.new()
		style.bg_color = colors[s[2]]
		style.set_corner_radius_all(12)
		style.border_color = Color(1, 1, 1, 0.7)
		style.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = style.bg_color.lightened(0.15)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.pressed.connect(func() -> void: picked[0] = s[0])
		row.add_child(b)
	while picked[0] == "":
		await get_tree().process_frame
	row.queue_free()
	return picked[0]


func choose(species: String) -> void:
	for c in _ui.get_children():
		for b in c.get_children():
			if b is Button and (b as Button).text.to_lower().begins_with(species):
				(b as Button).pressed.emit()


static func _fit(mon: Node3D, target: float) -> float:
	var box := AABB()
	var first := true
	for c in mon.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (c as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return target / maxf(box.size.y, 1.0)
