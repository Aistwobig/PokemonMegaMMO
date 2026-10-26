class_name BattleScene extends Node3D
## A wild battle, staged where the player stands: their Pokémon steps out in front of them and the
## wild one faces it. The server runs the battle; this plays back its events (messages, HP,
## motions) and sends the player's choices. See server/src/battle/wild.ts for the messages.

signal finished(result: String)

## Battle motions of X/Y Pokémon models (a/0/0/7 animation packs).
const MOT_IDLE := 0
const MOT_APPEAR := 1
const MOT_PHYSICAL := 8
const MOT_SPECIAL := 12
const MOT_HIT := 16
const MOT_FAINT := 17
const BALL_NAMES := {"pokeball": "Poké Ball", "greatball": "Great Ball", "ultraball": "Ultra Ball"}

var _send: Callable # func(action: Dictionary)
var _trainer: Node3D
var _camera: Camera3D
var _forward := Vector3(0, 0, 1)
var _right := Vector3(1, 0, 0)
var _origin := Vector3.ZERO
var _mons := {"player": null, "wild": null} # side -> NpcModel
var _species := {"player": "", "wild": ""}
var _queue: Array = [] # updates waiting to be played
var _playing := false # playing back events, or waiting for the server's answer: no menu
var _loop_running := false
var _update: Dictionary = {} # the latest update (view + request)
var _ball: MeshInstance3D

# UI
var _ui: CanvasLayer
var _boxes := {} # side -> {panel, icon: PokemonIcon, name: Label, gender: Label, level: Label, status: Container, bar: StatBar, hp: Label}
var _result := "" # how the update being played ends ("win", "caught", ...), for the victory music
var _message: Label
var _message_panel: PanelContainer
var _menu: Control
var _skip_wait := false


func _init(trainer: Node3D, update: Dictionary, send: Callable) -> void:
	_trainer = trainer
	_send = send
	_update = update
	_queue.append(update)


func _ready() -> void:
	_origin = _trainer.global_position
	var yaw := deg_to_rad(_trainer.rotation_degrees.y)
	_forward = Vector3(sin(yaw), 0, cos(yaw))
	_right = Vector3(_forward.z, 0, -_forward.x)
	_camera = Camera3D.new()
	_camera.fov = 34
	_camera.far = 20000
	add_child(_camera)
	_camera.global_position = _origin - _forward * 34 + _right * 56 + Vector3.UP * 50
	_camera.look_at(_origin + _forward * 60 + Vector3.UP * 2)
	_camera.make_current()
	_build_ui()
	_play()


## A new update from the server (after the player's choice).
func apply(update: Dictionary) -> void:
	_update = update
	_queue.append(update)
	if not _loop_running:
		_play()


func _play() -> void:
	_loop_running = true
	_playing = true
	_menu.visible = false
	while not _queue.is_empty():
		var u: Dictionary = _queue.pop_front()
		_result = str(u.get("result", ""))
		_refresh_boxes(u.get("view", {}), u.get("events", []).is_empty())
		for e: Dictionary in u.get("events", []):
			await _play_event(e)
		if u.has("result"):
			await _finish(str(u.result))
			return
	_loop_running = false
	_playing = false
	_message.text = "What will %s do?" % _active_name()
	_show_menu()


func _play_event(e: Dictionary) -> void:
	var side: String = e.get("side", "")
	match str(e.get("anim", "")):
		"appear":
			_spawn("wild", str(e.species))
		"send":
			_spawn("player", str(e.species))
		"attack":
			_motion(side, MOT_PHYSICAL if _has_motion(side, MOT_PHYSICAL) else MOT_SPECIAL)
			_lunge(side)
		"hit":
			_motion(side, MOT_HIT)
			_flash(side)
		"faint":
			_motion(side, MOT_FAINT)
			if side == "wild" and _result == "win":
				_victory_music()
			var mon: Node3D = _mons.get(side)
			if mon:
				var t := create_tween()
				t.tween_interval(0.5)
				t.tween_property(mon, "scale", Vector3.ONE * 0.01, 0.35)
		"throw":
			await _throw_ball()
		"shake":
			await _shake_ball()
		"breakout":
			_release_from_ball()
		"caught":
			_caught()
			_victory_music()
		"levelup":
			Music.jingle(Music.LEVEL_UP)
		"evolve":
			if _mons.player:
				_spawn("player", str(e.species))
	if e.get("hp") != null and side != "":
		# maxHp is missing when the Pokémon fainted ("0 fnt")
		_set_hp(side, _num(e.hp), _num(e.get("maxHp")))
	if e.has("text"):
		await _say(str(e.text))
	elif str(e.get("anim", "")) in ["hit", "attack"]:
		await _wait(0.35)


func _victory_music() -> void:
	var vs_trainer: bool = _update.get("view", {}).get("trainer") is Dictionary
	Music.play(Music.TRAINER_WIN if vs_trainer else Music.WILD_WIN, 0.2)


## A number from the server's JSON (which may also be null or text).
static func _num(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	if v is String:
		return (v as String).to_int()
	return 0


func _finish(result: String) -> void:
	_menu.visible = false
	await _wait(0.6)
	var fade := ScreenFade.new(Color(0, 0, 0, 0))
	add_child(fade)
	await fade.to(Color.BLACK, 0.4)
	finished.emit(result)
	queue_free()


# --- models ------------------------------------------------------------------------------------------

func _spawn(side: String, species: String) -> void:
	var old: Node3D = _mons.get(side)
	if old:
		old.queue_free()
	var mon := NpcModel.create(species, NpcModel.POKEMON)
	_species[side] = species
	_mons[side] = mon
	if mon == null:
		return
	add_child(mon)
	var at := _origin + _forward * (28.0 if side == "player" else 104.0) + _right * (24.0 if side == "player" else -10.0)
	mon.global_position = at
	mon.look_at(at + (_forward if side == "player" else -_forward), Vector3.UP, true)
	var size := _scale_for(mon, species)
	BlobShadow.attach(mon, 14.0).scale = Vector3.ONE / size # sized in world units, not the model's
	mon.scale = Vector3.ONE * 0.01
	create_tween().tween_property(mon, "scale", Vector3.ONE * size, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not mon.play_motion(MOT_APPEAR, false):
		mon.play_motion(MOT_IDLE)
	else:
		mon.player.get_animation("mot%02d" % MOT_IDLE).loop_mode = Animation.LOOP_LINEAR
		mon.player.queue("mot%02d" % MOT_IDLE)


## Pokémon models come at their battle size; scale them to the trainers, keeping big ones bigger.
func _scale_for(mon: Node3D, species: String) -> float:
	var box := AABB()
	var first := true
	for c in mon.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (c as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var height := maxf(box.size.y, 1.0)
	var real: float = POKEDEX_HEIGHTS.get(species, 0.6)
	var target := 34.0 * clampf(real / 0.6, 0.7, 2.2)
	return target / height


func _motion(side: String, index: int) -> void:
	var mon: NpcModel = _mons.get(side)
	if mon and mon.play_motion(index, false):
		mon.player.get_animation("mot%02d" % MOT_IDLE).loop_mode = Animation.LOOP_LINEAR
		mon.player.queue("mot%02d" % MOT_IDLE)


func _has_motion(side: String, index: int) -> bool:
	var mon: NpcModel = _mons.get(side)
	return mon != null and mon.player.has_animation("mot%02d" % index)


func _lunge(side: String) -> void:
	var mon: Node3D = _mons.get(side)
	if mon == null:
		return
	var dir := _forward if side == "player" else -_forward
	var start := mon.global_position
	var t := create_tween()
	t.tween_property(mon, "global_position", start + dir * 14, 0.15)
	t.tween_property(mon, "global_position", start, 0.2)


func _flash(side: String) -> void:
	var mon: Node3D = _mons.get(side)
	if mon == null:
		return
	var t := create_tween()
	for i in 3: # the Pokémon may be swapped out (and freed) mid-flash
		t.tween_callback(func() -> void: if is_instance_valid(mon): mon.visible = false)
		t.tween_interval(0.06)
		t.tween_callback(func() -> void: if is_instance_valid(mon): mon.visible = true)
		t.tween_interval(0.06)


# --- Poké Ball -----------------------------------------------------------------------------------------

func _throw_ball() -> void:
	if _ball == null:
		_ball = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 3.0
		sphere.height = 6.0
		_ball.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.15, 0.15)
		mat.roughness = 0.3
		_ball.material_override = mat
		add_child(_ball)
	var wild: Node3D = _mons.wild
	var target := (wild.global_position if wild else _origin + _forward * 104) + Vector3.UP * 6
	var from := _origin + Vector3.UP * 30 + _right * 4
	_ball.visible = true
	_ball.global_position = from
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		_ball.global_position = from.lerp(target, k) + Vector3.UP * sin(k * PI) * 40, 0.0, 1.0, 0.6)
	await t.finished
	if wild:
		await create_tween().tween_property(wild, "scale", Vector3.ONE * 0.01, 0.25).finished
	await create_tween().tween_property(_ball, "global_position", target - Vector3.UP * 3, 0.25).finished


func _shake_ball() -> void:
	var t := create_tween()
	t.tween_property(_ball, "rotation:z", 0.5, 0.12)
	t.tween_property(_ball, "rotation:z", -0.5, 0.2)
	t.tween_property(_ball, "rotation:z", 0.0, 0.12)
	t.tween_interval(0.45)
	await t.finished


func _release_from_ball() -> void:
	_ball.visible = false
	var wild: Node3D = _mons.wild
	if wild:
		create_tween().tween_property(wild, "scale", Vector3.ONE * _scale_for(wild, _species.wild), 0.25)


func _caught() -> void:
	var mat := _ball.material_override as StandardMaterial3D
	create_tween().tween_property(mat, "albedo_color", Color(0.5, 0.5, 0.5), 0.5)


# --- UI ------------------------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_boxes.wild = _info_box(false)
	_boxes.player = _info_box(true)
	_message_panel = PanelContainer.new()
	_message_panel.anchor_top = 1.0
	_message_panel.anchor_bottom = 1.0
	_message_panel.anchor_right = 1.0
	_message_panel.offset_top = -150
	_message_panel.offset_left = 16
	_message_panel.offset_right = -16
	_message_panel.offset_bottom = -16
	var style := Ui.panel_style(Color(0.07, 0.09, 0.13, 0.93), 8)
	style.border_color = Color(1, 1, 1, 0.22)
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	_message_panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(_message_panel)
	_message = Ui.label("", 22)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.custom_minimum_size.x = 560
	_message_panel.add_child(_message)
	_menu = Control.new()
	_menu.anchor_left = 1.0
	_menu.anchor_right = 1.0
	_menu.anchor_top = 1.0
	_menu.anchor_bottom = 1.0
	_menu.offset_left = -540
	_menu.offset_top = -142
	_menu.offset_right = -28
	_menu.offset_bottom = -26
	_ui.add_child(_menu)


## The wild/foe box sits top left, ours bottom right above the message box (X/Y's layout).
func _info_box(is_player: bool) -> Dictionary:
	var panel := PanelContainer.new()
	if is_player:
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_left = -420
		panel.offset_top = -268
		panel.offset_right = -16
		panel.offset_bottom = -164
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		panel.offset_left = 16
		panel.offset_top = 16
	panel.custom_minimum_size = Vector2(404, 0)
	panel.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.08, 0.1, 0.14, 0.9), 8))
	_ui.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var icon := PokemonIcon.new("", 2.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var name_label := Ui.label("", 19)
	top.add_child(name_label)
	var gender := Ui.label("", 18)
	top.add_child(gender)
	var status := HBoxContainer.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(status)
	var level := Ui.label("", 16, Ui.TEXT_DIM)
	top.add_child(level)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	col.add_child(hp_row)
	hp_row.add_child(Ui.badge("HP", Color(0.85, 0.55, 0.15), 11))
	var bar := StatBar.new(10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(bar)
	var hp := Ui.label("", 14)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp.visible = is_player
	col.add_child(hp)
	return {"panel": panel, "icon": icon, "name": name_label, "gender": gender, "level": level, "status": status,
		"bar": bar, "hp": hp, "max": 1, "cur": 0}


func _refresh_boxes(view: Dictionary, set_hp: bool) -> void:
	for side in ["player", "wild"]:
		var v: Variant = view.get(side)
		if not (v is Dictionary):
			continue
		var box: Dictionary = _boxes[side]
		box.name.text = str(v.name)
		box.gender.text = " " + Ui.gender_symbol(v.get("gender", ""))
		box.gender.add_theme_color_override("font_color", Ui.gender_color(v.get("gender", "")))
		box.level.text = "Lv. %d" % int(v.level)
		box.icon.species = str(v.get("species", ""))
		box.icon.hop = side == "player"
		box.max = maxi(int(v.maxHp), 1)
		_set_status(side, v.get("status"), int(v.hp))
		if set_hp or box.cur == 0:
			_set_hp(side, int(v.hp), int(v.maxHp), true)


func _set_status(side: String, status: Variant, hp: int) -> void:
	var box: Dictionary = _boxes[side]
	for c in (box.status as Container).get_children():
		c.queue_free()
	var badge := Ui.status_badge(status, hp)
	if badge:
		box.status.add_child(badge)


func _set_hp(side: String, hp: int, max_hp: int, instant := false) -> void:
	var box: Dictionary = _boxes[side]
	if max_hp > 0:
		box.max = max_hp
	box.cur = hp
	box.hp.text = "%d / %d" % [hp, box.max]
	(box.bar as StatBar).set_value(hp, box.max, not instant)
	box.icon.fainted = hp <= 0
	if hp <= 0:
		_set_status(side, "fnt", 0)


func _say(text: String) -> void:
	_message.text = text
	_skip_wait = false
	var until := Time.get_ticks_msec() / 1000.0 + clampf(0.8 + text.length() * 0.025, 0.9, 2.4)
	while Time.get_ticks_msec() / 1000.0 < until and not _skip_wait:
		await get_tree().process_frame


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_Z]) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if pressed and _playing:
		_skip_wait = true


func _active_name() -> String:
	var p: Variant = _update.get("view", {}).get("player")
	return str(p.name) if p is Dictionary else "your Pokémon"


# --- the command menu (X/Y's bottom screen, as one panel) -----------------------------------------

func _show_menu() -> void:
	var req: Variant = _update.get("request")
	if not (req is Dictionary):
		return
	if req.kind == "switch":
		_message.text = "Choose a Pokémon."
		_show_party(true)
	else:
		_show_commands()


func _clear_menu() -> GridContainer:
	for c in _menu.get_children():
		c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_menu.add_child(grid)
	_menu.visible = true
	return grid


func _button(grid: Container, text: String, color: Color, action: Callable, enabled := true) -> Button:
	var b := Ui.button(text, action, color, 18)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.disabled = not enabled
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	grid.add_child(b)
	return b


func _show_commands() -> void:
	var grid := _clear_menu()
	_button(grid, "FIGHT", Color(0.78, 0.24, 0.22), _show_moves)
	_button(grid, "BAG", Color(0.82, 0.58, 0.14), _show_bag)
	_button(grid, "POKéMON", Color(0.22, 0.62, 0.32), _show_party.bind(false))
	var vs_trainer: bool = _update.get("view", {}).get("trainer") is Dictionary
	_button(grid, "RUN", Color(0.24, 0.42, 0.78), _choose.bind({"type": "run"}), not vs_trainer)


func _show_moves() -> void:
	var grid := _clear_menu()
	grid.columns = 3
	for m: Dictionary in _update.request.moves:
		var color: Color = Ui.TYPE_COLORS.get(m.type, Color(0.4, 0.4, 0.45))
		var b := _button(grid, "%s\n%s   PP %d/%d" % [m.name, str(m.type).to_upper(), int(m.pp), int(m.maxPp)],
			color.darkened(0.15), _choose.bind({"type": "move", "index": int(m.index)}), not m.disabled and int(m.pp) > 0)
		b.add_theme_font_size_override("font_size", 15)
	_button(grid, "Back", Color(0.26, 0.29, 0.36), _show_commands)


func _show_bag() -> void:
	var grid := _clear_menu()
	if _update.get("view", {}).get("trainer") is Dictionary:
		_message.text = "You can't catch a Trainer's Pokémon!"
	var balls: Dictionary = _update.get("view", {}).get("balls", {})
	var any := false
	for id: String in BALL_NAMES:
		var n := int(balls.get(id, 0))
		if n > 0:
			any = true
			_button(grid, "%s  ×%d" % [BALL_NAMES[id], n], Color(0.72, 0.25, 0.25), _choose.bind({"type": "ball", "item": id}))
	if not any:
		_message.text = "You don't have any Poké Balls."
	_button(grid, "Back", Color(0.26, 0.29, 0.36), _show_commands)


func _show_party(forced: bool) -> void:
	var grid := _clear_menu()
	grid.columns = 3
	var active: Variant = _update.get("view", {}).get("player")
	for p: Dictionary in _update.get("view", {}).get("party", []):
		var is_active: bool = active is Dictionary and int(active.slot) == int(p.slot) and int(active.hp) > 0
		var b := _button(grid, "%s\nLv. %d   %d/%d" % [p.name, int(p.level), int(p.hp), int(p.maxHp)],
			Color(0.2, 0.42, 0.3) if int(p.hp) > 0 else Color(0.35, 0.22, 0.22),
			_choose.bind({"type": "switch", "slot": int(p.slot)}), int(p.hp) > 0 and not is_active)
		b.add_theme_font_size_override("font_size", 14)
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var icon := PokemonIcon.new(str(p.get("species", "")), 1.0)
		icon.fainted = int(p.hp) <= 0
		icon.position = Vector2(4, 4)
		b.add_child(icon)
	if not forced:
		_button(grid, "Back", Color(0.26, 0.29, 0.36), _show_commands)


func _choose(action: Dictionary) -> void:
	_menu.visible = false
	_message.text = ""
	_playing = true # until the server's answer has played out
	_send.call(action)


## Pokédex heights in meters (for sizing models next to trainers); others default to 0.6.
const POKEDEX_HEIGHTS := {
	"chespin": 0.4, "quilladin": 0.7, "fennekin": 0.4, "braixen": 1.0, "froakie": 0.3, "frogadier": 0.6,
	"fletchling": 0.3, "fletchinder": 0.7, "bunnelby": 0.4, "diggersby": 1.0, "scatterbug": 0.3,
	"spewpa": 0.3, "zigzagoon": 0.4, "linoone": 0.5, "pikachu": 0.4, "raichu": 0.8, "pidgey": 0.3,
	"pidgeotto": 1.1, "caterpie": 0.3, "metapod": 0.7, "weedle": 0.3, "kakuna": 0.6, "vivillon": 1.2,
	"talonflame": 1.2, "chesnaught": 1.6, "delphox": 1.5, "greninja": 1.5,
}
