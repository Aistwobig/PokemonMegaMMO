extends Node
## Logs in a throwaway account and opens the online world, for screenshots/manual checks.
## SHOT=<file.png> walks a few steps, saves a screenshot and quits.
##   godot --path client res://tests/world_test.tscn


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
	var shot := OS.get_environment("SHOT")
	if shot == "":
		return
	# SHOT=<file.png>: walk from the front door down the lane, screenshot, quit. Moves go straight
	# to the server so keys typed elsewhere while the window has focus don't interfere.
	world.accept_input = false
	await get_tree().create_timer(4.0).timeout
	print("start: ", _me(world))
	for dir: String in ["down", "down", "down", "down", "left"]:
		world._room.send_message("move", dir)
		await get_tree().create_timer(0.35).timeout
	await get_tree().create_timer(1.0).timeout
	print("end: ", _me(world))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()


func _me(world: Node) -> String:
	var p: Dictionary = world._room.state.players.get(world._room.get_session_id(), {})
	return "tile (%s, %s)" % [p.get("x"), p.get("y")]
