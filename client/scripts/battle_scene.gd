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
const TYPE_COLORS := {
	"Normal": Color("a8a77a"), "Fire": Color("ee8130"), "Water": Color("6390f0"), "Electric": Color("f7d02c"),
	"Grass": Color("7ac74c"), "Ice": Color("96d9d6"), "Fighting": Color("c22e28"), "Poison": Color("a33ea1"),
	"Ground": Color("e2bf65"), "Flying": Color("a98ff3"), "Psychic": Color("f95587"), "Bug": Color("a6b91a"),
	"Rock": Color("b6a136"), "Ghost": Color("735797"), "Dragon": Color("6f35fc"), "Dark": Color("705746"),
	"Steel": Color("b7b7ce"), "Fairy": Color("d685ad"),
}
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
var _boxes := {} # side -> {name: Label, level: Label, bar: ColorRect, back: ColorRect, hp: Label}
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
		"evolve":
			if _mons.player:
				_spawn("player", str(e.species))
	if e.has("hp") and side != "":
		_set_hp(side, int(e.hp), int(e.get("maxHp", 0)))
	if e.has("text"):
		await _say(str(e.text))
	elif str(e.get("anim", "")) in ["hit", "attack"]:
		await _wait(0.35)


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
	for i in 3:
		t.tween_callback(func() -> void: mon.visible = false)
		t.tween_interval(0.06)
		t.tween_callback(func() -> void: mon.visible = true)
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
	_boxes.wild = _info_box(Vector2(24, 24), false)
	_boxes.player = _info_box(Vector2(-404, -330), true)
	_message_panel = PanelContainer.new()
	_message_panel.anchor_top = 1.0
	_message_panel.anchor_bottom = 1.0
	_message_panel.anchor_right = 1.0
	_message_panel.offset_top = -150
	_message_panel.offset_left = 24
	_message_panel.offset_right = -24
	_message_panel.offset_bottom = -24
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.16, 0.92)
	style.border_color = Color(0.85, 0.85, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(18)
	_message_panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(_message_panel)
	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 24)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.custom_minimum_size.x = 560
	_message_panel.add_child(_message)
	_menu = Control.new()
	_menu.anchor_left = 1.0
	_menu.anchor_right = 1.0
	_menu.anchor_top = 1.0
	_menu.anchor_bottom = 1.0
	_menu.offset_left = -520
	_menu.offset_top = -146
	_menu.offset_right = -30
	_menu.offset_bottom = -28
	_ui.add_child(_menu)


func _info_box(pos: Vector2, is_player: bool) -> Dictionary:
	var panel := PanelContainer.new()
	if is_player:
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
	panel.offset_left = pos.x
	panel.offset_top = pos.y
	panel.custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.97, 0.95, 0.95)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var row := HBoxContainer.new()
	col.add_child(row)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.18))
	row.add_child(name_label)
	var level := Label.new()
	level.add_theme_font_size_override("font_size", 20)
	level.add_theme_color_override("font_color", Color(0.15, 0.15, 0.18))
	row.add_child(level)
	var back := ColorRect.new()
	back.color = Color(0.25, 0.25, 0.28)
	back.custom_minimum_size = Vector2(0, 12)
	col.add_child(back)
	var bar := ColorRect.new()
	bar.color = Color(0.3, 0.85, 0.4)
	bar.size = Vector2(0, 12)
	back.add_child(bar)
	var hp := Label.new()
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25))
	hp.visible = is_player
	col.add_child(hp)
	return {"panel": panel, "name": name_label, "level": level, "bar": bar, "back": back, "hp": hp, "max": 1, "cur": 0}


func _refresh_boxes(view: Dictionary, set_hp: bool) -> void:
	for side in ["player", "wild"]:
		var v: Variant = view.get(side)
		if not (v is Dictionary):
			continue
		var box: Dictionary = _boxes[side]
		var gender: String = {"M": " ♂", "F": " ♀"}.get(v.get("gender", ""), "")
		box.name.text = str(v.name) + gender
		box.level.text = "Lv. %d" % int(v.level)
		box.max = maxi(int(v.maxHp), 1)
		if set_hp or box.cur == 0:
			_set_hp(side, int(v.hp), int(v.maxHp), true)


func _set_hp(side: String, hp: int, max_hp: int, instant := false) -> void:
	var box: Dictionary = _boxes[side]
	if max_hp > 0:
		box.max = max_hp
	box.cur = hp
	var width: float = box.back.size.x if box.back.size.x > 0 else 356.0
	var ratio := clampf(float(hp) / float(box.max), 0.0, 1.0)
	var color := Color(0.3, 0.85, 0.4) if ratio > 0.5 else Color(0.95, 0.8, 0.2) if ratio > 0.2 else Color(0.9, 0.25, 0.2)
	box.hp.text = "%d / %d" % [hp, box.max]
	if instant:
		box.bar.size = Vector2(width * ratio, 12)
		box.bar.color = color
		return
	var t := create_tween().set_parallel()
	t.tween_property(box.bar, "size:x", width * ratio, 0.5)
	t.tween_property(box.bar, "color", color, 0.5)


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
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_menu.add_child(grid)
	_menu.visible = true
	return grid


func _button(grid: Container, text: String, color: Color, action: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 20)
	b.disabled = not enabled
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color.darkened(0.15) if state == "pressed" else color.lightened(0.1) if state == "hover" else color if state == "normal" else color.darkened(0.5)
		s.set_corner_radius_all(10)
		s.border_color = Color(1, 1, 1, 0.6)
		s.set_border_width_all(2)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.pressed.connect(action)
	grid.add_child(b)
	return b


func _show_commands() -> void:
	var grid := _clear_menu()
	_button(grid, "FIGHT", Color(0.85, 0.25, 0.25), _show_moves)
	_button(grid, "BAG", Color(0.9, 0.65, 0.15), _show_bag)
	_button(grid, "POKéMON", Color(0.25, 0.7, 0.35), _show_party.bind(false))
	_button(grid, "RUN", Color(0.25, 0.45, 0.85), _choose.bind({"type": "run"}))


func _show_moves() -> void:
	var grid := _clear_menu()
	grid.columns = 3
	for m: Dictionary in _update.request.moves:
		var label := "%s\n%d/%d" % [m.name, int(m.pp), int(m.maxPp)]
		_button(grid, label, TYPE_COLORS.get(m.type, Color(0.4, 0.4, 0.45)), _choose.bind({"type": "move", "index": int(m.index)}),
			not m.disabled and int(m.pp) > 0)
	_button(grid, "Back", Color(0.35, 0.35, 0.4), _show_commands)


func _show_bag() -> void:
	var grid := _clear_menu()
	var balls: Dictionary = _update.get("view", {}).get("balls", {})
	var any := false
	for id: String in BALL_NAMES:
		var n := int(balls.get(id, 0))
		if n > 0:
			any = true
			_button(grid, "%s  ×%d" % [BALL_NAMES[id], n], Color(0.85, 0.3, 0.3), _choose.bind({"type": "ball", "item": id}))
	if not any:
		_message.text = "You don't have any Poké Balls."
	_button(grid, "Back", Color(0.35, 0.35, 0.4), _show_commands)


func _show_party(forced: bool) -> void:
	var grid := _clear_menu()
	var active: Variant = _update.get("view", {}).get("player")
	for p: Dictionary in _update.get("view", {}).get("party", []):
		var is_active: bool = active is Dictionary and int(active.slot) == int(p.slot) and int(active.hp) > 0
		var label := "%s  Lv. %d\n%d / %d HP" % [p.name, int(p.level), int(p.hp), int(p.maxHp)]
		_button(grid, label, Color(0.25, 0.6, 0.35) if int(p.hp) > 0 else Color(0.4, 0.3, 0.3),
			_choose.bind({"type": "switch", "slot": int(p.slot)}), int(p.hp) > 0 and not is_active)
	if not forced:
		_button(grid, "Back", Color(0.35, 0.35, 0.4), _show_commands)


func _choose(action: Dictionary) -> void:
	_menu.visible = false
	_message.text = ""
	_playing = true # until the server's answer has played out
	_send.call(action)


## Pokédex heights in meters (for sizing models next to trainers); others default to 0.6.
const POKEDEX_HEIGHTS := {
	"chespin": 0.4, "quilladin": 0.7, "fennekin": 0.4, "braixen": 1.0, "froakie": 0.3, "frogadier": 0.6,
	"fletchling": 0.3, "fletchinder": 0.7, "bunnelby": 0.4, "diggersby": 1.0, "scatterbug": 0.3,
	"spewpa": 0.3, "zigzagoon": 0.4, "linoone": 0.5,
}
