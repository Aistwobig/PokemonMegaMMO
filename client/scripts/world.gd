extends Node3D
## The online overworld: joins the map room the trainer is saved on, shows every player in it and
## sends arrow-key/WASD moves. The server decides where everyone is; this only draws it.

const TOWN_SCENE := "res://scenes/phase0.tscn" # sky, sun, HUD and material fixes
const LOGIN_SCENE := "res://scenes/login.tscn"
## The overworld (Vaniville, Route 1, Aquacorde, Route 2): every chunk of map01, from
## importer/README.md. Without it, the two Vaniville chunks from Phase 0 are used.
const OVERWORLD := "res://asset-cache/maps/map01/"
const TILE := 18.0 # world units per map tile (a 720-unit map chunk is 40×40 tiles)
const GROUND_Y := 144.0 # Vaniville's ground height, where the height probe starts if it knows nothing
## World placement: chunk (11, 14), Vaniville's north half, is centered on the origin, so global
## tile (440, 560) starts at (-360, -360) and every other chunk follows at 720 units per chunk.
const ORIGIN_CHUNK := Vector2i(11, 14)
## Close behind and above, like X/Y's town camera (its real per-zone settings aren't decoded yet).
const CAMERA_OFFSET := Vector3(0, 230, 290)
const STEP_TIME := 0.22 # seconds per tile; a bit slower than the server's 200 ms step limit
const FACING_YAW := {"down": 0.0, "up": 180.0, "left": -90.0, "right": 90.0}

var _client: Colyseus.Client
var _room: Colyseus.Room
var _players := {} # sessionId -> RemoteTrainer
var _camera: Camera3D
var _status: Label
var _next_step_at := 0.0
var _heights := {} # Vector2i global tile -> ground height
var _origin := Vector2i(440, 560) # global tile of the current room's (0, 0), from the room state
var _carry: RemoteTrainer # our own trainer, kept across a warp so the walk looks seamless
var _teleport := false # the next warp jumps instead of walking (blacking out)
var _battle: BattleScene
var _busy := false # a battle, the starter choice or a message is on screen: no walking
var _box: DialogueBox
var _has_pokemon := true # until the server says otherwise; false shows the starter choice in Aquacorde
## Tests turn this off so stray key presses (the window takes focus while you type) can't move.
var accept_input := true


func _ready() -> void:
	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	town.get_node("Camera3D").queue_free()
	town.get_node("World/Garchomp").queue_free()
	_load_overworld(town.get_node("World"))
	add_child(town)
	_add_ground_collision(town)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.far = 20000.0
	add_child(_camera)
	_camera.make_current()
	_status = Label.new()
	_status.position = Vector2(16, 40)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	town.get_node("HUD").add_child(_status)
	_box = DialogueBox.new()
	add_child(_box)
	var party := await Session.get_party()
	_has_pokemon = party.is_empty() or not party.get("party", []).is_empty()
	_join(Session.trainer.get("mapId", "vaniville"), "")


func _join(map_id: String, ticket: String) -> void:
	_status.text = "Connecting to %s…" % map_id
	if _client == null:
		_client = Colyseus.Client.new(Session.server_url.replace("http", "ws"))
		_client.auth.set_token(Session.token)
	var options := {} if ticket == "" else {ticket = ticket}
	var room: Colyseus.Room = _client.join_or_create(map_id, options)
	_room = room
	if room == null:
		_status.text = "Couldn't join %s." % map_id
		return
	# Signals from a room we've already left (after a warp) are ignored.
	room.joined.connect(func() -> void: if room == _room: _status.text = "")
	room.state_changed.connect(func() -> void: if room == _room: _sync_players())
	room.message_received.connect(func(type: Variant, data: Variant) -> void: if room == _room: _on_message(type, data))
	room.error.connect(func(code: int, message: String) -> void: if room == _room: _status.text = "Server: %s (%d)" % [message, code])
	room.left.connect(func(code: int, reason: String) -> void: if room == _room: _on_left(code, reason))


func _on_message(type: Variant, data: Variant) -> void:
	match str(type):
		"warp":
			_teleport = data.get("blackout", false) == true
			_warp(str(data.get("to", "")), str(data.get("ticket", "")))
		"battleStart":
			_start_battle(data)
		"battleUpdate":
			if _battle:
				_battle.apply(data)
		"healed":
			_mom_heals()


## Moves to the next map. Neighbouring overworld maps share one 3D world, so our trainer stays
## where it is and only the room changes: the other players change, the view doesn't.
func _warp(to: String, ticket: String) -> void:
	var old := _room
	_carry = _players.get(old.get_session_id())
	_players.erase(old.get_session_id())
	for sid: String in _players:
		_players[sid].queue_free()
	_players.clear()
	_room = null
	old.leave()
	_join(to, ticket)


func _start_battle(update: Dictionary) -> void:
	var me: RemoteTrainer = _players.get(_room.get_session_id())
	if me == null:
		return
	_busy = true
	# Trainers step out of the picture during a battle, as in X/Y (the camera stands where we were).
	for rt: RemoteTrainer in _players.values():
		rt.visible = false
	_battle = BattleScene.new(me, update, func(action: Dictionary) -> void:
		if _room:
			_room.send_message("battle", action))
	add_child(_battle)
	var result: String = await _battle.finished
	_battle = null
	for rt: RemoteTrainer in _players.values():
		rt.visible = true
	_camera.make_current()
	var fade := ScreenFade.new(Color.BLACK)
	add_child(fade)
	# Blacked out somewhere else: the server warps us home and the arrival clears the busy flag.
	_busy = result == "lost" and _room != null and str(_room.state.get("mapId", "")) != "vaniville"
	await fade.clear(0.4)
	fade.queue_free()


## Walking into your front door: Mom heals your Pokémon (story text 55, lines 29–30).
func _mom_heals() -> void:
	if _busy:
		return
	_busy = true
	var name: String = Session.trainer.get("name", "")
	_box.speaker = "Mom"
	await _box.say(GameText.pages(GameText.HOME, 29, name, Session.gender()))
	await _box.say(GameText.pages(GameText.HOME, 30, name, Session.gender()))
	_busy = false


## Right after the intro, outside the front door: Shauna and the neighbor come to say hello.
func _maybe_meet_neighbors() -> void:
	if _busy or _room == null or not Session.intro_done() or Session.has_seen("neighbors"):
		return
	if str(_room.state.get("mapId", "")) != "vaniville":
		return
	var me: RemoteTrainer = _players.get(_room.get_session_id())
	if me == null:
		return
	_busy = true
	var scene := NeighborsScene.new(self, me)
	add_child(scene)
	await scene.finished
	_busy = false


## The first time in Aquacorde without a Pokémon: pick a starter.
func _maybe_choose_starter() -> void:
	if _has_pokemon or _busy or _room == null or str(_room.state.get("mapId", "")) != "aquacorde":
		return
	var me: RemoteTrainer = _players.get(_room.get_session_id())
	if me == null:
		return
	_busy = true
	_has_pokemon = true
	var choice := StarterChoice.new(me)
	add_child(choice)
	await choice.finished
	_camera.make_current()
	_busy = false


func _on_left(code: int, _reason: String) -> void:
	if code == 4001:
		_status.text = "You logged in somewhere else."
	elif code >= 4000:
		_status.text = "Disconnected (%d)." % code


func _sync_players() -> void:
	var state: Variant = _room.state
	if not (state is Dictionary) or not state.has("players"):
		return
	if int(state.get("originX", -1)) >= 0:
		_origin = Vector2i(int(state.originX), int(state.originY))
	var seen := {}
	for sid: String in state.players:
		var p: Dictionary = state.players[sid]
		seen[sid] = true
		var rt: RemoteTrainer = _players.get(sid)
		if rt == null and _carry and sid == _room.get_session_id():
			rt = _carry # ourselves, arriving from the previous map
			_carry = null
			_players[sid] = rt
			if _teleport:
				rt.teleport(_tile_to_world(p.x, p.y), p.facing)
				_teleport = false
				_busy = false
			else:
				rt.move_to(_tile_to_world(p.x, p.y), p.facing)
		elif rt == null:
			rt = RemoteTrainer.new(p.get("name", "Trainer"), p.get("look", ""), sid == _room.get_session_id())
			add_child(rt)
			rt.teleport(_tile_to_world(p.x, p.y), p.facing)
			_players[sid] = rt
		else:
			rt.move_to(_tile_to_world(p.x, p.y), p.facing)
	for sid: String in _players.keys():
		if not seen.has(sid):
			_players[sid].queue_free()
			_players.erase(sid)


func _process(_delta: float) -> void:
	var me: RemoteTrainer = _players.get(_room.get_session_id()) if _room else null
	if me and _battle == null:
		_camera.look_at_from_position(me.position + CAMERA_OFFSET, me.position + Vector3(0, 22, 0))
	if _room == null or not _room.connected:
		return
	_maybe_choose_starter()
	_maybe_meet_neighbors()
	if _busy:
		return
	var dir := _held_direction() if accept_input else ""
	var now := Time.get_ticks_msec() / 1000.0
	if dir != "" and now >= _next_step_at:
		_room.send_message("move", dir)
		_next_step_at = now + STEP_TIME


func _held_direction() -> String:
	if Input.is_action_pressed(&"ui_up") or Input.is_key_pressed(KEY_W): return "up"
	if Input.is_action_pressed(&"ui_down") or Input.is_key_pressed(KEY_S): return "down"
	if Input.is_action_pressed(&"ui_left") or Input.is_key_pressed(KEY_A): return "left"
	if Input.is_action_pressed(&"ui_right") or Input.is_key_pressed(KEY_D): return "right"
	return ""


## A room tile to a world position (tile center, on the ground).
func _tile_to_world(x: int, y: int) -> Vector3:
	var g := _origin + Vector2i(x, y)
	var base := ORIGIN_CHUNK * 40
	var pos := Vector3((g.x - base.x) * TILE - 360.0 + TILE / 2, 0, (g.y - base.y) * TILE - 360.0 + TILE / 2)
	if not _heights.has(g):
		_heights[g] = _ground_height(pos.x, pos.z, _nearby_height(g))
	pos.y = _heights[g]
	return pos


## Height of a tile we already know near g, so the probe can follow slopes, bridges and stairs.
func _nearby_height(g: Vector2i) -> Variant:
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var h: Variant = _heights.get(g + Vector2i(dx, dy))
				if h != null:
					return h
	return null


## The ground under a point: rays down onto the world model. Tree tops, roofs and bridges over
## our heads are skipped by taking the first upward-facing surface no higher than a little above a
## nearby known height (ref); with no ref, the first upward-facing surface from high above.
func _ground_height(x: float, z: float, ref: Variant) -> float:
	var space := get_world_3d().direct_space_state
	var top: float = (ref + 40.0) if ref != null else 3000.0
	var from := Vector3(x, top, z)
	for i in 16:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, Vector3(x, top - 3000.0, z)))
		if hit.is_empty():
			break
		if hit.normal.y > 0.6:
			return hit.position.y
		from = hit.position - Vector3(0, 0.5, 0)
	return ref if ref != null else GROUND_Y


## Puts every overworld chunk under the town scene's World node (whose script fixes materials).
func _load_overworld(world: Node3D) -> void:
	if not DirAccess.dir_exists_absolute(OVERWORLD):
		return # Phase 0 assets only: keep the two Vaniville chunks in the scene
	for node_name in ["VanivilleNorth", "VanivilleSouth"]:
		world.get_node(node_name).free()
	var pattern := RegEx.create_from_string("^map01_(\\d+)_(\\d+)\\.dae$")
	for file in DirAccess.get_files_at(OVERWORLD):
		var m := pattern.search(file)
		if m == null:
			continue
		var chunk := (load(OVERWORLD + file) as PackedScene).instantiate() as Node3D
		if chunk.find_children("*", "Skeleton3D", true, false).size() > 0 and chunk.find_children("*", "MeshInstance3D", true, false).size() <= 1:
			chunk.free() # an empty placeholder chunk
			continue
		var c := Vector2i(int(m.get_string(1)), int(m.get_string(2))) - ORIGIN_CHUNK
		chunk.position = Vector3(c.x * 720.0, 0, c.y * 720.0)
		world.add_child(chunk)


## Collision shapes from the town model, for the height probe.
func _add_ground_collision(town: Node) -> void:
	for c in town.get_node("World").find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh:
			mi.create_trimesh_collision()


func _exit_tree() -> void:
	if _room:
		_room.leave()


## One player on the map: model, name tag, and smooth tile-to-tile walking.
class RemoteTrainer extends Node3D:
	var _model: TrainerModel
	var _tween: Tween
	var _walking_until := 0.0

	func _init(trainer_name: String, look_json: String, is_me: bool) -> void:
		var look: Variant = JSON.parse_string(look_json) if look_json != "" else null
		if not (look is Dictionary):
			look = TrainerModel.default_look("f1" if trainer_name.hash() % 2 == 0 else "f2")
		_model = TrainerModel.from_look(look)
		if _model:
			add_child(_model)
			_model.play_motion(TrainerModel.MOTION_STAND)
		var tag := Label3D.new()
		tag.text = trainer_name
		tag.position.y = 52
		tag.font_size = 48
		tag.outline_size = 12
		tag.pixel_size = 0.3 # the game's units are large (a tile is 18), so scale text up to match
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.modulate = Color(1, 0.95, 0.5) if is_me else Color.WHITE
		add_child(tag)

	func teleport(pos: Vector3, facing: String) -> void:
		position = pos
		_face(facing)

	func move_to(pos: Vector3, facing: String) -> void:
		_face(facing)
		if pos.is_equal_approx(position):
			return
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "position", pos, STEP_TIME)
		_walking_until = Time.get_ticks_msec() / 1000.0 + STEP_TIME + 0.08
		if _model and _model.player.current_animation != "mot%02d" % TrainerModel.MOTION_WALK:
			_model.play_motion(TrainerModel.MOTION_WALK)

	func _face(facing: String) -> void:
		rotation_degrees.y = FACING_YAW.get(facing, 0.0)

	func _process(_delta: float) -> void:
		if _model and Time.get_ticks_msec() / 1000.0 > _walking_until \
				and _model.player.current_animation != "mot%02d" % TrainerModel.MOTION_STAND:
			_model.play_motion(TrainerModel.MOTION_STAND)
