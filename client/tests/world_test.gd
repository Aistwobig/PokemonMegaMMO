extends Node
## Logs in a throwaway account and opens the online world, for screenshots/manual checks.
##   godot --path client res://tests/world_test.tscn


func _ready() -> void:
	Session.token = ""
	var id := str(randi() % 100000)
	var err := await Session.register("world_" + id, "pikachu-thunder", "Tester " + id, false)
	if err != "":
		push_error("register failed: " + err)
		get_tree().quit(1)
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
