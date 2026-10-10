extends Node
## Plays the intro end to end with simulated key presses and checks it reaches the world:
## Sycamore's welcome → character creation → waking up → downstairs → out the door.
## Needs the server running. Set SHOTS=<dir> to save screenshots along the way.
##   godot --path client res://tests/intro_test.tscn

var _failures := 0
var _shots := OS.get_environment("SHOTS")
var _shot_n := 0


func _ready() -> void:
	Session.token = ""
	var id := str(randi() % 100000)
	var err := await Session.register("intro_" + id, "pikachu-thunder", "Intro " + id, false)
	_check("registered", err == "", err)
	_check("intro not seen yet", not Session.intro_done())
	_check("intro text exported", GameText.line(GameText.INTRO, 23).begins_with("Welcome to the world"))
	var pages := GameText.format("[VAR 0100(0000)] changed out of h[VAR 1100(00FF,0202)]iser pajamas!", "Ash", "f1")
	_check("player name and girl's text filled in", pages[0] == "Ash changed out of her pajamas!", pages[0])
	pages = GameText.format("That's my [VAR 1100(00FF,0403)]boygirl!\\cNext box", "Ash", "f2")
	_check("boy's text, and boxes split", pages.size() == 2 and pages[0] == "That's my boy!", str(pages))

	# --- Sycamore ---
	# The scenes replace the current scene as they go, so the test steps aside and stays alive.
	var intro: Node = (load("res://scenes/intro.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(intro)
	get_tree().current_scene = intro
	await _wait(2.0)
	await _shot("sycamore")
	var creator: Node = null
	for i in 40: # advance text until the creator appears
		creator = _find_creator(intro)
		if creator:
			break
		await _press(KEY_SPACE)
	_check("character creator opens during the intro", creator != null)
	if creator:
		creator.set_gender("f1")
		await _wait(0.5)
		creator.save()
		await _wait(1.5)
	_check("look saved", Session.has_appearance())
	await _shot("player_beside_sycamore")
	for i in 30:
		if _scene_name() == "Home":
			break
		if is_instance_valid(intro):
			for b: Button in intro.find_children("*", "Button", true, false):
				if b.text == "Yes" and b.is_visible_in_tree():
					b.pressed.emit()
		await _press(KEY_SPACE)
	await _wait(1.0)
	_check("intro leads to the house", _scene_name() == "Home", _scene_name())
	if _scene_name() != "Home":
		_done()
		return

	# --- waking up ---
	var home := get_tree().current_scene
	await _wait(1.2)
	await _shot("in_bed")
	for i in 30: # through the chirp, getting up and Mom's lines
		if not home._busy:
			break
		await _press(KEY_SPACE)
		if i == 4:
			await _shot("mom")
	_check("cutscene ends with the player free to walk", not home._busy)
	_check("Mom went back downstairs", home._mom == null)
	await _shot("bedroom")
	# Bedroom: from beside the bed to the top of the stairs, then onto them.
	await _walk_to(home, Vector2i(9, 15))
	await _walk(home, "right", 1)
	await _wait(1.0)
	_check("door leads downstairs", home._floor == "1f", home._floor)
	await _shot("downstairs")
	# 1F: talk to Mom, then walk to the front door and out.
	# Around the stairwell: left, up past the sofa, right to Mom.
	await _walk(home, "left", 3)
	await _walk(home, "up", 5)
	await _walk(home, "right", 3)
	await _walk(home, "up", 1)
	_check("next to Mom", home._tile == Vector2i(13, 4), str(home._tile))
	home._face("right")
	await _press(KEY_SPACE)
	await _wait(0.5)
	await _shot("talk_to_mom")
	await _press(KEY_SPACE)
	_check("talked to Mom", home._talked_to_mom)
	await _walk_to(home, Vector2i(9, 12))
	await _walk(home, "down", 1)
	await _wait(3.0)
	_check("out the door into the world", _scene_name() == "World", _scene_name())
	_check("intro saved as seen", Session.intro_done())
	await _wait(3.0)
	await _shot("world")
	_done()


func _scene_name() -> String:
	var s := get_tree().current_scene
	return str(s.name) if s else ""


func _find_creator(n: Node) -> Node:
	for c in n.get_children():
		if c.has_signal("saved"):
			return c
	return null


## Walks n tiles in one direction (fewer if something is in the way).
func _walk(home: Node, dir: String, steps: int) -> void:
	var action: StringName = {"up": &"ui_up", "down": &"ui_down", "left": &"ui_left", "right": &"ui_right"}[dir]
	for i in steps: # one tap per tile (a held key's step count depends on frame timing)
		Input.action_press(action)
		await _wait(0.05)
		Input.action_release(action)
		await _wait(0.25)
	await _wait(0.2)


## Walks to a tile: up/down first, then across (fine for these open rooms).
func _walk_to(home: Node, t: Vector2i) -> void:
	for i in 3:
		var d: Vector2i = t - home._tile
		if d.y != 0:
			await _walk(home, "down" if d.y > 0 else "up", absi(d.y))
		d = t - home._tile
		if d.x != 0:
			await _walk(home, "right" if d.x > 0 else "left", absi(d.x))
		if home._tile == t:
			return


func _press(key: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await _wait(0.05)
	var up := InputEventKey.new()
	up.keycode = key
	Input.parse_input_event(up)
	await _wait(0.6)


func _shot(label: String) -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png(_shots.path_join("%02d_%s.png" % [_shot_n, label]))


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _check(name: String, ok: bool, detail := "") -> void:
	print(("  ok   " if ok else "  FAIL ") + name + ("" if ok or detail == "" else " — " + detail))
	if not ok:
		_failures += 1


func _done() -> void:
	print("all checks passed" if _failures == 0 else "%d check(s) failed" % _failures)
	get_tree().quit(1 if _failures else 0)
