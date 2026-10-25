extends Node3D
## The online overworld: joins the map room the trainer is saved on, shows every player in it and
## sends arrow-key/WASD moves. The server decides where everyone is; this only draws it.

const TOWN_SCENE := "res://scenes/phase0.tscn" # sky, sun, HUD and material fixes
const LOGIN_SCENE := "res://scenes/login.tscn"
const CREATOR_SCENE := "res://scenes/character_creator.tscn"
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
var _npcs := {} # trainer id -> NpcModel standing on the current map
var _grass: Array[Node3D] = [] # tall grass tufts (hidden during battles, which happen "elsewhere" in X/Y)
var _pending_npcs: Variant = null
var _has_pokemon := true # until the server says otherwise; false shows the starter choice in Aquacorde
var _hud: GameHud
var _map_id := "" # the map we're on, once the room state says
## Tests turn this off so stray key presses (the window takes focus while you type) can't move.
var accept_input := true


func _ready() -> void:
	var town := (load(TOWN_SCENE) as PackedScene).instantiate()
	town.get_node("Camera3D").queue_free()
	town.get_node("World/Garchomp").queue_free()
	_load_overworld(town.get_node("World"))
	add_child(town)
	_add_ground_collision(town)
	_plant_tall_grass.call_deferred()
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.far = 20000.0
	add_child(_camera)
	_camera.make_current()
	town.get_node("HUD").free() # the title screen's HUD; the world has its own
	_hud = GameHud.new()
	add_child(_hud)
	_hud.requested.connect(_on_hud_request)
	_status = _hud.status
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
		"npcs":
			_pending_npcs = data # placed once the room state (and its map origin) has arrived
		"battleUpdate":
			if _battle:
				_battle.apply(data)
		"healed":
			_mom_heals()


## A HUD button or key (P, B, C, Esc). Nothing opens over a battle, a talk or another menu.
func _on_hud_request(what: String) -> void:
	if _busy or not accept_input:
		return
	match what:
		"party":
			open_party()
		"bag":
			_open_menu(BagMenu.new())
		"look":
			get_tree().change_scene_to_file(CREATOR_SCENE)
		"settings":
			var menu := SettingsMenu.new()
			menu.logout_requested.connect(_log_out)
			_open_menu(menu)


## The party screen; walking waits until it's closed.
func open_party() -> PartyMenu:
	var menu := PartyMenu.new()
	_open_menu(menu)
	return menu


func _open_menu(menu: CanvasLayer) -> void:
	_busy = true
	add_child(menu)
	menu.closed.connect(func() -> void:
		_busy = false
		_hud.refresh())


func _log_out() -> void:
	set_process(false)
	await Session.logout()
	get_tree().change_scene_to_file(LOGIN_SCENE)


## The map we're on (for the music menu's "back to the area's music").
func current_map() -> String:
	return _map_id


## Moves to the next map. Neighbouring overworld maps share one 3D world, so our trainer stays
## where it is and only the room changes: the other players change, the view doesn't.
func _warp(to: String, ticket: String) -> void:
	var old := _room
	_carry = _players.get(old.get_session_id())
	_players.erase(old.get_session_id())
	for sid: String in _players:
		_players[sid].queue_free()
	_players.clear()
	_show_npcs([])
	_room = null
	old.leave()
	_join(to, ticket)


## The map's NPC trainers, standing where the server says.
func _show_npcs(list: Variant) -> void:
	for n: Node in _npcs.values():
		n.queue_free()
	_npcs.clear()
	if not (list is Array):
		return
	for t: Dictionary in list:
		var npc := NpcModel.create(str(t.get("model", "")))
		if npc == null:
			continue
		add_child(npc)
		npc.position = _tile_to_world(int(t.x), int(t.y))
		npc.rotation_degrees.y = FACING_YAW.get(t.get("facing", "down"), 0.0)
		npc.play_motion(0)
		_npcs[t.id] = npc


## A trainer spotted us: "!" over their head, they walk up, then the battle.
func _trainer_walks_up(info: Dictionary) -> void:
	var npc: NpcModel = _npcs.get(info.get("id", ""))
	if npc == null:
		return
	var mark := Label3D.new()
	mark.text = "!"
	mark.font_size = 96
	mark.outline_size = 16
	mark.modulate = Color(1, 0.3, 0.25)
	mark.pixel_size = 0.3
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.position.y = 62
	npc.add_child(mark)
	await get_tree().create_timer(0.8).timeout
	mark.queue_free()
	var to: Dictionary = info.get("to", {})
	var target := _tile_to_world(int(to.get("x", 0)), int(to.get("y", 0)))
	var steps := maxi(1, int(npc.position.distance_to(target) / TILE))
	npc.play_motion(2)
	await create_tween().tween_property(npc, "position", target, STEP_TIME * steps).finished
	npc.play_motion(0)
	await get_tree().create_timer(0.3).timeout


func _start_battle(update: Dictionary) -> void:
	var me: RemoteTrainer = _players.get(_room.get_session_id())
	if me == null:
		return
	_busy = true
	_hud.visible = false # battles and story scenes have the screen to themselves
	Music.play(Music.TRAINER_BATTLE if update.has("trainer") else Music.WILD_BATTLE, 0.25)
	if update.has("trainer"):
		await _trainer_walks_up(update.trainer)
	# Trainers step out of the picture during a battle, as in X/Y (the camera stands where we were).
	for rt: RemoteTrainer in _players.values():
		rt.visible = false
	for n: Node3D in _npcs.values():
		n.visible = false
	for g in _grass:
		g.visible = false
	_battle = BattleScene.new(me, update, func(action: Dictionary) -> void:
		if _room:
			_room.send_message("battle", action))
	add_child(_battle)
	var result: String = await _battle.finished
	_battle = null
	for rt: RemoteTrainer in _players.values():
		rt.visible = true
	for n: Node3D in _npcs.values():
		n.visible = true
	for g in _grass:
		g.visible = true
	_camera.make_current()
	Music.play_map(_map_id)
	_hud.visible = true
	_hud.refresh()
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
	_hud.refresh()
	Music.jingle(Music.HEAL)
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
	_hud.visible = false
	add_child(scene)
	await scene.finished
	_hud.visible = true
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
	_hud.visible = false
	add_child(choice)
	await choice.finished
	_camera.make_current()
	_hud.visible = true
	_hud.refresh()
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
	var map_id := str(state.get("mapId", ""))
	if map_id != "" and map_id != _map_id:
		_map_id = map_id
		_hud.set_place(map_id)
		if _battle == null:
			Music.play_map(map_id)
	if _pending_npcs != null:
		_show_npcs(_pending_npcs)
		_pending_npcs = null
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


## X/Y draws tall grass separately from the map: a swaying clump (a/2/3/0, "grass00") on every
## tall-grass tile (0x20002004 in the chunk's tile grid).
const GRASS_TILE := 0x20002004

func _plant_tall_grass() -> void:
	if not DirAccess.dir_exists_absolute(OVERWORLD):
		return
	await get_tree().physics_frame # the ground collision must be in the physics world first
	var pattern := RegEx.create_from_string("^map01_(\\d+)_(\\d+)\\.tiles\\.json$")
	var planted := 0
	for file in DirAccess.get_files_at(OVERWORLD):
		var m := pattern.search(file)
		if m == null:
			continue
		var grid := RoomMap.load_tiles(OVERWORLD + file)
		var chunk := Vector2i(int(m.get_string(1)), int(m.get_string(2)))
		for i in grid.tiles.size():
			if grid.tiles[i] != GRASS_TILE:
				continue
			var g := chunk * 40 + Vector2i(i % grid.width, i / grid.width)
			var tuft := NpcModel.create("grass00")
			if tuft == null:
				return # not exported yet (importer/README.md)
			add_child(tuft)
			var base := ORIGIN_CHUNK * 40
			var x := (g.x - base.x) * TILE - 360.0 + TILE / 2
			var z := (g.y - base.y) * TILE - 360.0 + TILE / 2
			tuft.position = Vector3(x, _ground_height(x, z, null), z)
			tuft.rotation_degrees.y = (g.x * 7 + g.y * 13) % 4 * 90.0 # a little variety
			tuft.play_motion(0)
			tuft.player.seek(randf() * 1.0) # don't all sway in step
			_grass.append(tuft)
			planted += 1


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
