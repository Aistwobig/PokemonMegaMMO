extends Node3D
## The online overworld: joins the map room the trainer is saved on, shows every player in it and
## sends arrow-key/WASD moves. The server decides where everyone is; this only draws it.

const TOWN_SCENE := "res://scenes/phase0.tscn"
const LOGIN_SCENE := "res://scenes/login.tscn"
const TILE := 18.0 # world units per map tile (a 720-unit map chunk is 40×40 tiles)
const GROUND_Y := 144.0 # Vaniville's usual ground height, where the height probe starts looking
## Server tile (0, 0) of Vaniville is tile (0, 0) of the north chunk, whose model is centered on the
## origin; the south chunk sits 720 units further south, so rows 40+ continue onto it.
const GRID_ORIGIN := Vector3(-360.0 + TILE / 2, 0, -360.0 + TILE / 2)
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
var _heights := {} # Vector2i tile -> ground height
## Tests turn this off so stray key presses (the window takes focus while you type) can't move.
var accept_input := true


func _ready() -> void:
	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	town.get_node("Camera3D").queue_free()
	town.get_node("World/Garchomp").queue_free()
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
	_join(Session.trainer.get("mapId", "vaniville"), "")


func _join(map_id: String, ticket: String) -> void:
	_status.text = "Connecting to %s…" % map_id
	if _client == null:
		_client = Colyseus.Client.new(Session.server_url.replace("http", "ws"))
		_client.auth.set_token(Session.token)
	var options := {} if ticket == "" else {ticket = ticket}
	_room = _client.join_or_create(map_id, options)
	if _room == null:
		_status.text = "Couldn't join %s." % map_id
		return
	_room.joined.connect(func() -> void: _status.text = "")
	_room.state_changed.connect(_sync_players)
	_room.message_received.connect(_on_message)
	_room.error.connect(func(code: int, message: String) -> void: _status.text = "Server: %s (%d)" % [message, code])
	_room.left.connect(_on_left)


func _on_message(type: Variant, data: Variant) -> void:
	match str(type):
		"warp":
			# Other maps aren't built in 3D yet: say so instead of leaving town.
			_status.text = "Path to %s — that map isn't in 3D yet." % data.get("to", "?")
		"wildEncounter":
			_status.text = "A wild %s appeared! (battles come in Phase 3)" % data.get("species", "?")
			_room.send_message("battleEnd")


func _on_left(code: int, _reason: String) -> void:
	if code == 4001:
		_status.text = "You logged in somewhere else."
	elif code >= 4000:
		_status.text = "Disconnected (%d)." % code


func _sync_players() -> void:
	var state: Variant = _room.state
	if not (state is Dictionary) or not state.has("players"):
		return
	var seen := {}
	for sid: String in state.players:
		var p: Dictionary = state.players[sid]
		seen[sid] = true
		var rt: RemoteTrainer = _players.get(sid)
		if rt == null:
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
	if me:
		_camera.look_at_from_position(me.position + CAMERA_OFFSET, me.position + Vector3(0, 22, 0))
	if _room == null or not _room.connected:
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


func _tile_to_world(x: int, y: int) -> Vector3:
	var key := Vector2i(x, y)
	if not _heights.has(key):
		_heights[key] = _ground_height(GRID_ORIGIN.x + x * TILE, GRID_ORIGIN.z + y * TILE)
	return GRID_ORIGIN + Vector3(x * TILE, _heights[key], y * TILE)


## The town's ground under a point: rays down onto the town model, skipping tree tops and roofs by
## taking the highest surface that isn't far above the usual ground height.
func _ground_height(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, GROUND_Y + 400, z)
	var best := GROUND_Y
	var found := false
	for i in 12:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, Vector3(x, GROUND_Y - 300, z)))
		if hit.is_empty():
			break
		var y: float = hit.position.y
		if hit.normal.y > 0.6 and y < GROUND_Y + 40:
			best = y
			found = true
			break
		from = hit.position - Vector3(0, 0.5, 0)
	return best if found else GROUND_Y


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
