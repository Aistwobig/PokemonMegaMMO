extends Node3D
## Waking up at home in Vaniville Town (the player's house, map chunks t01r01 from the RomFS).
## The player wakes in their bedroom, Mom comes up to say good morning, then the player walks
## downstairs and out the front door into the online world. It's a private, client-side scene:
## nothing here affects other players, so the tile checks run locally.

const WORLD_SCENE := "res://scenes/world.tscn"
const FOLDER := "res://asset-cache/maps/t01r01/"
const MOM := "tr0007"
const STEP_TIME := 0.2
const FACING_YAW := {"down": 0.0, "up": 180.0, "left": -90.0, "right": 90.0}
const DIRS := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
## Each floor: model + tile grid (bedrooms differ for girls and boys), the part of the chunk the
## camera frames (in tiles), and the special tiles.
const FLOORS := {
	"bedroom": {
		"model": {"f1": "bedroom_f1", "f2": "bedroom_f2"},
		"view": Rect2(1, 10, 15, 7),
		"pitch": 52.0, # camera angle down from horizontal
		"bed": Vector3(-322, 17, -132), # the player's feet while lying in bed
		"wake_tile": Vector2i(3, 12),
		# Mom comes up the stairs to just below the player. (Tile E9 by the desk is the PC.)
		"mom_path": [Vector2i(10, 15), Vector2i(9, 15), Vector2i(8, 15), Vector2i(8, 14), Vector2i(8, 13),
			Vector2i(7, 13), Vector2i(6, 13), Vector2i(5, 13), Vector2i(4, 13), Vector2i(3, 13)],
		"stairs": [Vector2i(10, 15), Vector2i(10, 16)], # the stairwell, east of these rows → 1F
		"arrive": [Vector2i(9, 15), "left"],
		"mirror": [Vector2i(7, 10), Vector2i(8, 10), Vector2i(9, 10)], # facing up from here
	},
	"1f": {
		"model": {"f1": "house_1f", "f2": "house_1f"},
		"view": Rect2(4, 2, 15, 11),
		"pitch": 68.0, # steeper, or the back room hides behind the stairwell walls
		"stairs": [Vector2i(13, 9), Vector2i(14, 9)], # the foot of the stairs, north of these → bedroom
		"arrive": [Vector2i(13, 10), "down"],
		"mom": [Vector2i(14, 4), "down"],
		"exit_row": 12, # walking down off this row leaves the house
	},
}

var _floor := ""
var _model: Node3D
var _grid := {}
var _player: TrainerModel
var _tile := Vector2i.ZERO
var _facing := "down"
var _mom: NpcModel
var _mom_tile := Vector2i(-1, -1)
var _camera: Camera3D
var _box: DialogueBox
var _fade: ScreenFade
var _hint: Label
var _busy := true # cutscene or text on screen: no walking
var _moving_until := 0.0
var _talked_to_mom := false
var _leaving := false


func _ready() -> void:
	Music.play_map("vaniville") # the house is in Vaniville's zone and plays its theme
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.0
	add_child(env)
	_camera = Camera3D.new()
	_camera.fov = 30
	add_child(_camera)
	_camera.make_current()
	var look: Dictionary = Session.trainer.get("appearance") if Session.has_appearance() else TrainerModel.default_look("f2")
	_player = TrainerModel.from_look(look)
	if _player == null:
		_player = TrainerModel.new() # no trainer assets: walk around invisible rather than crash
	add_child(_player)
	_box = DialogueBox.new()
	add_child(_box)
	var ui := CanvasLayer.new()
	add_child(ui)
	_hint = Label.new()
	_hint.position = Vector2(20, 20)
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(_hint)
	var skip := Button.new()
	skip.text = "Skip"
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -100
	skip.offset_right = -20
	skip.offset_top = 20
	skip.offset_bottom = 56
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(leave_house)
	ui.add_child(skip)
	_fade = ScreenFade.new(Color.WHITE) # the intro ends on white
	add_child(_fade)
	wake_up()


const FLETCHLING_HEIGHT := 13.0 # world units: 0.3 m next to the ~1.4 m trainer
const FLETCHLING_FLAP := 0 # battle idle: wings beating in place
const FLETCHLING_CHIRP := 12 # the "special move" pose: head up, beak open


## The Fletchling flies in from the window (north wall, above the bed) to hover beside the pillow.
func _fletchling_arrives(bed: Vector3) -> NpcModel:
	var bird := NpcModel.create("fletchling", NpcModel.POKEMON)
	if bird == null:
		return null
	add_child(bird)
	var box := AABB()
	var first := true
	for c in bird.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (c as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	bird.scale = Vector3.ONE * (FLETCHLING_HEIGHT / maxf(box.size.y, 1.0))
	var perch := bed + Vector3(30, 28, 6) # in the air beside the bed, in front of the camera
	var start := perch + Vector3(60, 70, -150) # out of view, by the window
	bird.position = start
	bird.look_at(perch, Vector3.UP, true)
	bird.play_motion(FLETCHLING_FLAP)
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		# a fluttering line: a little bob on the way in
		bird.position = start.lerp(perch, k) + Vector3.UP * sin(k * TAU * 2.0) * 4.0, 0.0, 1.0, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func() -> void:
		bird.look_at(bird.position + Vector3(-0.6, 0, 1), Vector3.UP, true) # turn to the player
		if bird.play_motion(FLETCHLING_CHIRP, false):
			bird.player.get_animation("mot%02d" % FLETCHLING_FLAP).loop_mode = Animation.LOOP_LINEAR
			bird.player.queue("mot%02d" % FLETCHLING_FLAP))
	return bird


func _fletchling_leaves(bird: NpcModel) -> void:
	if bird == null:
		return
	var away := bird.position + Vector3(90, 70, -140)
	bird.look_at(away, Vector3.UP, true)
	bird.play_motion(FLETCHLING_FLAP)
	var t := create_tween()
	t.tween_property(bird, "position", away, 1.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	t.tween_callback(bird.queue_free)


const CHIRP_FRAME := 290.0 # the Fletchling flies into the room past the bed: "Cheerp cheerp!"


## The game's own wake-up scene (WakeupCutscene: its camera, Fletchling's flight, the blanket and the
## feathers), then back to the bedroom for the rest.
func _play_wakeup_cutscene() -> void:
	var look: Dictionary = Session.trainer.get("appearance") if Session.has_appearance() else TrainerModel.default_look("f2")
	var scene := WakeupCutscene.new(look)
	var hidden: Array[Node3D] = [] # the field bedroom would overlap the cutscene's own copy of the room
	for c in get_children():
		if c is Node3D and (c as Node3D).visible:
			(c as Node3D).visible = false
			hidden.append(c)
	add_child(scene)
	scene.play()
	await _fade.clear(1.0)
	while scene.camera.playing and scene.camera.frame < CHIRP_FRAME:
		await get_tree().process_frame
	scene.camera.speed = 0.0 # hold the moment while the text is up
	for m in scene.find_children("*", "AnimationPlayer", true, false):
		(m as AnimationPlayer).speed_scale = 0.0
	await _say(GameText.HOME, 16, "") # Cheerp cheerp! ♪
	scene.camera.speed = 1.0
	for m in scene.find_children("*", "AnimationPlayer", true, false):
		(m as AnimationPlayer).speed_scale = 1.0
	await scene.finished
	await _fade.to(Color.BLACK, 0.5)
	scene.queue_free()
	for c in hidden:
		c.visible = true
	_camera.make_current()
	await _fade.clear(0.6)


## The opening cutscene: asleep, a Fletchling's chirp, out of bed, Mom comes up.
func wake_up() -> void:
	_load_floor("bedroom")
	var f: Dictionary = FLOORS.bedroom
	_player.position = f.bed
	_player.rotation_degrees = Vector3(-90, 0, 0) # lying on the back, head on the pillow
	_player_motion(TrainerModel.MOTION_STAND)
	_update_camera(true)
	if WakeupCutscene.available():
		await _play_wakeup_cutscene()
	else:
		await _fade.clear(1.5)
		await _wait(0.4)
		# A Fletchling flutters in at the window, chirps at the sleeping player, and flies off.
		var bird := _fletchling_arrives(f.bed)
		await _wait(1.3)
		await _say(GameText.HOME, 16, "") # Cheerp cheerp! ♪
		await _wait(0.3)
		_fletchling_leaves(bird)
	# Hop out of bed.
	_tile = f.wake_tile
	_facing = "down"
	var target := RoomMap.tile_center(_tile.x, _tile.y)
	var hop := create_tween().set_parallel()
	hop.tween_property(_player, "rotation_degrees", Vector3(0, FACING_YAW.down, 0), 0.45).set_trans(Tween.TRANS_SINE)
	hop.tween_property(_player, "position:x", target.x, 0.45)
	hop.tween_property(_player, "position:z", target.z, 0.45)
	var arc := create_tween()
	arc.tween_property(_player, "position:y", 30.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc.tween_property(_player, "position:y", 0.0, 0.23).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await arc.finished
	await _wait(0.4)

	# Mom comes up the stairs.
	_mom = NpcModel.create(MOM)
	var path: Array = f.mom_path
	if _mom:
		add_child(_mom)
		_box.talkers["Mom"] = LipSync.attach(_mom)
		_mom.position = RoomMap.tile_center(path[0].x, path[0].y)
		_mom_tile = path[0]
		await _npc_walk(_mom, path.slice(1))
		_mom.rotation_degrees.y = FACING_YAW.up
	_face("down")
	await _say(GameText.HOME, 10, "Mom") # Morning! You sure slept well!
	await _say(GameText.HOME, 13, "Mom") # It's about time you got going! ... say hello to the neighbors?
	if _mom:
		var back := path.duplicate()
		back.reverse()
		await _npc_walk(_mom, back.slice(1))
		_mom.queue_free()
		_mom = null
		_mom_tile = Vector2i(-1, -1)
	_hint.text = "Arrow keys / WASD to walk · Space to talk\nHead downstairs and say hi to the neighbors!"
	_busy = false


func _process(_delta: float) -> void:
	_update_camera(false)
	if _player and Time.get_ticks_msec() / 1000.0 > _moving_until and not _busy:
		_player_motion(TrainerModel.MOTION_STAND)
	if _busy or Time.get_ticks_msec() / 1000.0 < _moving_until:
		return
	var dir := _held_direction()
	if dir != "":
		_step(dir)


func _unhandled_input(event: InputEvent) -> void:
	if _busy or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_Z]:
		get_viewport().set_input_as_handled()
		_interact()


func _step(dir: String) -> void:
	_face(dir)
	var f: Dictionary = FLOORS[_floor]
	var next: Vector2i = _tile + DIRS[dir]
	if _floor == "1f" and dir == "down" and _tile.y == f.exit_row:
		leave_house()
		return
	if next in f.stairs:
		_change_floor("1f" if _floor == "bedroom" else "bedroom")
		return
	if not _walkable(next):
		_moving_until = Time.get_ticks_msec() / 1000.0 + 0.08 # turn in place
		return
	_tile = next
	create_tween().tween_property(_player, "position", RoomMap.tile_center(_tile.x, _tile.y), STEP_TIME)
	_moving_until = Time.get_ticks_msec() / 1000.0 + STEP_TIME
	_player_motion(TrainerModel.MOTION_WALK)


## Tiles with bit 0 set are solid (walls, furniture, the bed); people block their tile too.
func _walkable(t: Vector2i) -> bool:
	return (RoomMap.tile_at(_grid, t.x, t.y) & 1) == 0 and t != _mom_tile


func _interact() -> void:
	var ahead: Vector2i = _tile + DIRS[_facing]
	if _mom and ahead == _mom_tile:
		_busy = true
		var back := {"down": "up", "up": "down", "left": "right", "right": "left"}
		_mom.rotation_degrees.y = FACING_YAW[back[_facing]]
		await _say(GameText.HOME, 14, "Mom") # Don't wake up Rhyhorn, OK?
		_talked_to_mom = true
		_busy = false
	elif _facing == "up" and _tile in FLOORS[_floor].get("mirror", []):
		_busy = true
		await _say(GameText.HOME, 2, "") # ... looked in the mirror...
		_busy = false


func _change_floor(to: String) -> void:
	_busy = true
	_player_motion(TrainerModel.MOTION_STAND)
	await _fade.to(Color.BLACK, 0.35)
	_load_floor(to)
	var arrive: Array = FLOORS[to].arrive
	_tile = arrive[0]
	_player.position = RoomMap.tile_center(_tile.x, _tile.y)
	_face(arrive[1])
	_update_camera(true)
	if to == "1f":
		_hint.text = "Go out the front door (bottom of the room)."
	await _fade.clear(0.35)
	_busy = false


func _load_floor(name: String) -> void:
	if _model:
		_model.queue_free()
	if _mom:
		_mom.queue_free()
		_mom = null
		_mom_tile = Vector2i(-1, -1)
	_floor = name
	var f: Dictionary = FLOORS[name]
	var file: String = f.model.get(Session.gender(), f.model.f2)
	_model = RoomMap.load_model(FOLDER + file + ".dae")
	if _model:
		add_child(_model)
	else:
		_hint.text = "The house isn't in the asset cache yet (see importer/README.md)."
	_grid = RoomMap.load_tiles(FOLDER + file + ".tiles.json")
	if f.has("mom"):
		_mom = NpcModel.create(MOM)
		if _mom:
			add_child(_mom)
			_box.talkers["Mom"] = LipSync.attach(_mom)
			_mom_tile = f.mom[0]
			_mom.position = RoomMap.tile_center(_mom_tile.x, _mom_tile.y)
			_mom.rotation_degrees.y = FACING_YAW[f.mom[1]]
			_mom.play_motion(0)


## Out the front door: the intro is done, on to Vaniville Town and the other players.
func leave_house() -> void:
	if _leaving:
		return
	_leaving = true
	_busy = true
	await _fade.to(Color.BLACK, 0.6)
	var err := await Session.complete_intro()
	if err != "":
		push_warning("couldn't save the intro as seen: " + err)
	get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)


func _npc_walk(npc: NpcModel, path: Array) -> void:
	npc.play_motion(2)
	for t: Vector2i in path:
		var from := RoomMap.world_to_tile(npc.position)
		var d := t - from
		npc.rotation_degrees.y = FACING_YAW["right" if d.x > 0 else "left" if d.x < 0 else "down" if d.y > 0 else "up"]
		if npc == _mom:
			_mom_tile = t
		await create_tween().tween_property(npc, "position", RoomMap.tile_center(t.x, t.y), STEP_TIME * 1.3).finished
	npc.play_motion(0)


func _say(file: Array, index: int, speaker: String) -> void:
	_box.speaker = speaker
	var pages := GameText.pages(file, index, Session.trainer.get("name", "Trainer"), Session.gender())
	if not pages.is_empty():
		await _box.say(pages)


func _face(dir: String) -> void:
	_facing = dir
	_player.rotation_degrees = Vector3(0, FACING_YAW[dir], 0)


func _player_motion(m: int) -> void:
	if _player.player and _player.player.current_animation != "mot%02d" % m:
		_player.play_motion(m)


## Frames the room, drifting a little toward the player.
func _update_camera(snap: bool) -> void:
	if _floor == "":
		return
	var view: Rect2 = FLOORS[_floor].view
	var center := RoomMap.tile_center(0, 0) + Vector3((view.get_center().x - 0.5) * RoomMap.TILE, 0, (view.get_center().y - 0.5) * RoomMap.TILE)
	var focus := center.lerp(Vector3(_player.position.x, 0, _player.position.z), 0.35)
	var distance := maxf(view.size.x * 0.6, view.size.y) * RoomMap.TILE * 1.9
	var pitch := deg_to_rad(FLOORS[_floor].pitch)
	var back := Vector3(0, sin(pitch), cos(pitch))
	var pos := focus + back * distance
	_camera.position = pos if snap else _camera.position.lerp(pos, 0.08)
	_camera.look_at(_camera.position - back, Vector3.UP)


func _held_direction() -> String:
	if Input.is_action_pressed(&"ui_up") or Input.is_key_pressed(KEY_W): return "up"
	if Input.is_action_pressed(&"ui_down") or Input.is_key_pressed(KEY_S): return "down"
	if Input.is_action_pressed(&"ui_left") or Input.is_key_pressed(KEY_A): return "left"
	if Input.is_action_pressed(&"ui_right") or Input.is_key_pressed(KEY_D): return "right"
	return ""


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
