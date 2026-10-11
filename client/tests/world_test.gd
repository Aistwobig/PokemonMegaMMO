extends Node
## Logs in a throwaway account and opens the online world, for screenshots/manual checks.
##   godot --path client res://tests/world_test.tscn
## SHOTS=<dir> also plays the first route through the real client: walks Vaniville → Route 1 →
## Aquacorde (picking Froakie there) → Route 2, battles the first wild Pokémon in the tall grass and
## throws Poké Balls until it's caught, saving screenshots along the way. Then quits.

## Same walk as server/src/scripts/paths.ts. A leg is [direction, steps], or [direction, "warp"] to
## keep going until the room changes.
const WALK := [
	["vaniville_door", "vaniville", []],
	["vaniville_lane", "vaniville", [["down", 11], ["left", 7]]],
	["route1", "route1", [["up", "warp"], ["up", 20]]],
	["aquacorde", "aquacorde", [["up", "warp"]]],
	["aquacorde_plaza", "aquacorde", [["up", 21], ["left", 6], ["up", 9], ["right", 6]]],
	["aquacorde_bridge", "aquacorde", [["up", 20]]],
	["route2", "route2", [["up", "warp"], ["up", 15]]],
]

var _failures := 0


func _ready() -> void:
	Session.token = ""
	var id := str(randi() % 100000)
	var err := await Session.register("world_" + id, "pikachu-thunder", "Tester " + id, false)
	if err != "":
		push_error("register failed: " + err)
		get_tree().quit(1)
		return
	var look := TrainerModel.default_look("f1")
	look.parts.hat = {"part": "f1_hat_cap", "color": "d01s01"}
	look.parts.socks = {"part": "f1_socks_tights", "color": "kd01p03"}
	look.hairColor = 4
	err = await Session.save_appearance(look)
	if err != "":
		push_error("saving the look failed: " + err)
	var world: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	var shots := OS.get_environment("SHOTS")
	if shots == "":
		return
	# Moves go straight to the server, so keys typed elsewhere while the window has focus can't
	# interfere. Wild encounters are dismissed by the world as usual.
	world.accept_input = false
	await _wait(4.0)
	for i in WALK.size():
		var stop: Array = WALK[i]
		for leg: Array in stop[2]:
			await _walk(world, leg[0], leg[1])
		await _wait(1.2)
		var room: String = world._room.state.get("mapId", "") if world._room and world._room.state is Dictionary else ""
		_check("%s: in %s" % [stop[0], stop[1]], room == stop[1], "%s at %s" % [room, _me(world)])
		print("       at ", _me(world))
		await _shot(shots, "%02d_%s" % [i + 1, stop[0]])
		if stop[0] == "aquacorde":
			await _pick_starter(world, shots)
	await _battle(world, shots)
	print("all checks passed" if _failures == 0 else "%d check(s) failed" % _failures)
	get_tree().quit(1 if _failures else 0)


## Walks n tiles (or until the room changes for "warp"). Aims for the target tile and resends
## moves until it's reached, since a move sent too soon after the last one is dropped.
func _walk(world: Node, dir: String, n: Variant) -> void:
	var step: Vector2i = {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}[dir]
	var start_room: Variant = world._room
	var target := _pos(world) + step * (0 if n is String else int(n))
	var stuck := 0
	for i in 120:
		if world._room != start_room:
			return # warped
		if not (n is String) and _pos(world) == target:
			return
		var before := _pos(world)
		world._room.send_message("move", dir)
		await _wait(0.3) # the server allows a step per 200 ms; leave room for jitter
		if OS.get_environment("TRACE") != "":
			print("    ", dir, " -> ", _me(world))
		stuck = stuck + 1 if _pos(world) == before and world._room == start_room else 0
		if stuck >= 4:
			return # walled in: the check after this stop reports where we ended up


func _pos(world: Node) -> Vector2i:
	if world._room == null or not (world._room.state is Dictionary):
		return Vector2i(-999, -999)
	var p: Dictionary = world._room.state.players.get(world._room.get_session_id(), {})
	return Vector2i(int(p.get("x", -999)), int(p.get("y", -999)))


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


## Aquacorde: the starter choice opens by itself for a trainer without Pokémon.
func _pick_starter(world: Node, shots: String) -> void:
	var choice: StarterChoice = null
	for i in 40:
		for c in world.get_children():
			if c is StarterChoice:
				choice = c
		if choice:
			break
		await _wait(0.1)
	_check("starter choice opens in Aquacorde", choice != null)
	if choice == null:
		return
	for i in 12: # through the friends' lines, until the buttons show
		await _press_space()
	await _shot(shots, "04b_starters")
	choice.choose("froakie")
	for i in 8:
		await _press_space()
	await _wait(1.0)
	var party: Dictionary = await Session.get_party()
	_check("got Froakie", party.get("party", []).size() == 1 and party.party[0].species == "froakie", str(party))


## Route 2: back and forth in the grass until a wild Pokémon appears, then fight and catch it.
func _battle(world: Node, shots: String) -> void:
	for i in 200:
		if world._battle:
			break
		await _walk(world, "left" if i % 6 < 3 else "right", 1)
	var battle: BattleScene = world._battle
	_check("a wild battle starts in the tall grass", battle != null)
	if battle == null:
		return
	await _until_menu(battle)
	await _shot(shots, "08_battle")
	battle._choose({"type": "move", "index": _attack_index(battle)})
	await _until_menu(battle)
	await _shot(shots, "09_after_attack")
	var ended := [""] # an array: lambdas can't assign to the function's local variables
	battle.finished.connect(func(r: String) -> void: ended[0] = r)
	for i in 12:
		if ended[0] != "" or not is_instance_valid(battle):
			break
		var req: Variant = battle._update.get("request")
		if req is Dictionary and req.kind == "switch":
			break
		battle._choose({"type": "ball", "item": "pokeball"})
		await _wait(1.5)
		if i == 0:
			await _shot(shots, "10_throw")
		await _until_menu(battle)
	var result: String = ended[0]
	_check("the battle ends", result != "", "still going")
	print("       result: ", result)
	await _wait(1.5)
	await _shot(shots, "11_after_battle")
	var party: Dictionary = await Session.get_party()
	if result == "caught":
		_check("caught Pokémon joins the party", party.get("party", []).size() == 2, str(party.get("party", [])))


func _attack_index(battle: BattleScene) -> int:
	var moves: Array = battle._update.request.moves
	for m: Dictionary in moves:
		if m.id in ["pound", "tackle", "scratch", "bubble", "ember", "vinewhip"]:
			return int(m.index)
	return 0


func _until_menu(battle: BattleScene) -> void:
	for i in 300:
		if not is_instance_valid(battle) or battle._menu.visible:
			return
		battle._skip_wait = true
		await _wait(0.05)


func _press_space() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_SPACE
	down.pressed = true
	Input.parse_input_event(down)
	await _wait(0.05)
	var up := InputEventKey.new()
	up.keycode = KEY_SPACE
	Input.parse_input_event(up)
	await _wait(0.5)


func _me(world: Node) -> String:
	if world._room == null or not (world._room.state is Dictionary):
		return "?"
	var p: Dictionary = world._room.state.players.get(world._room.get_session_id(), {})
	return "tile (%s, %s)" % [p.get("x"), p.get("y")]


func _check(name: String, ok: bool, detail := "") -> void:
	print(("  ok   " if ok else "  FAIL ") + name + ("" if ok or detail == "" else " — " + detail))
	if not ok:
		_failures += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
