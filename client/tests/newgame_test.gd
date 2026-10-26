extends Node
## Registers a trainer, plays past the intro into the world, then uses Menu → Developer → New game
## and checks the intro comes back with the progress reset.
func _ready() -> void:
	var id := str(randi() % 100000)
	var err := await Session.register("ngc_" + id, "pikachu-thunder", "Ngc " + id, false)
	assert(err == "", err)
	await Session.save_appearance(TrainerModel.default_look("f2"))
	await Session.complete_intro()
	await Session.mark_story("neighbors")
	var world: Node = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	await get_tree().create_timer(4.0).timeout
	print("in world: ", world._map_id, " devTools=", Session.dev_tools())
	world._on_hud_request("settings")
	await get_tree().create_timer(0.5).timeout
	var menu: SettingsMenu = world.get_children().filter(func(n: Node) -> bool: return n is SettingsMenu)[0]
	menu.new_game_requested.emit(true)
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if get_tree().current_scene and get_tree().current_scene.scene_file_path.ends_with("intro.tscn"):
			break
	var scene: String = get_tree().current_scene.scene_file_path if get_tree().current_scene else "?"
	print("RESULT scene=", scene, " introDone=", Session.intro_done(), " map=", Session.trainer.get("mapId"), " look=", Session.has_appearance())
	await Session.logout()
	get_tree().quit()
