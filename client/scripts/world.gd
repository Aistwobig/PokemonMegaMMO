extends Node3D
## The online overworld: joins the map room the trainer is saved on, shows every player in it and
## sends arrow-key/WASD moves. The server decides where everyone is; this only draws it.

const TOWN_SCENE := "res://scenes/phase0.tscn"
const LOGIN_SCENE := "res://scenes/login.tscn"
const TILE := 18.0 # world units per map tile (a 720-unit map chunk is 40×40 tiles)
const GROUND_Y := 143.0 # Vaniville's plaza height; real per-tile heights come with the collision data
## Where tile (0, 0) of the server's placeholder Vaniville grid sits in the 3D town.
const GRID_ORIGIN := Vector3(54.0 - 5 * TILE, GROUND_Y, 470.0 - 5 * TILE)
const STEP_TIME := 0.22 # seconds per tile; a bit slower than the server's 200 ms step limit
const MOTION_IDLE := 0
const MOTION_WALK := 2
const FACING_YAW := {"down": 0.0, "up": 180.0, "left": -90.0, "right": 90.0}

var _client: Colyseus.Client
var _room: Colyseus.Room
var _players := {} # sessionId -> RemoteTrainer
var _camera: Camera3D
var _status: Label
var _next_step_at := 0.0


func _ready() -> void:
	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	town.get_node("Camera3D").queue_free()
	town.get_node("World/Garchomp").queue_free()
	add_child(town)
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
			rt = RemoteTrainer.new(p.get("name", "Trainer"), sid == _room.get_session_id())
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
		_camera.look_at_from_position(me.position + Vector3(0, 420, 560), me.position + Vector3(0, 30, 0))
	if _room == null or not _room.connected:
		return
	var dir := _held_direction()
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
	return GRID_ORIGIN + Vector3(x * TILE, 0, y * TILE)


func _exit_tree() -> void:
	if _room:
		_room.leave()


## One player on the map: model, name tag, and smooth tile-to-tile walking.
class RemoteTrainer extends Node3D:
	var _model: TrainerModel
	var _tween: Tween
	var _walking_until := 0.0

	func _init(trainer_name: String, is_me: bool) -> void:
		# Until character creation exists, the look is picked from the name.
		var look := "serena" if trainer_name.hash() % 2 == 0 else "calem"
		_model = TrainerModel.create(look)
		if _model:
			add_child(_model)
			_model.play_motion(MOTION_IDLE)
		var tag := Label3D.new()
		tag.text = trainer_name
		tag.position.y = 70
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
		if _model and _model.player.current_animation != "mot%02d" % MOTION_WALK:
			_model.play_motion(MOTION_WALK)

	func _face(facing: String) -> void:
		rotation_degrees.y = FACING_YAW.get(facing, 0.0)

	func _process(_delta: float) -> void:
		if _model and Time.get_ticks_msec() / 1000.0 > _walking_until \
				and _model.player.current_animation != "mot%02d" % MOTION_IDLE:
			_model.play_motion(MOTION_IDLE)
