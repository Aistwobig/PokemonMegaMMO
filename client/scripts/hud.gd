extends CanvasLayer
## Minimal in-world HUD: who you're logged in as. Esc logs out.

const LOGIN_SCENE := "res://scenes/login.tscn"


func _ready() -> void:
	var who: String = Session.trainer.get("name", "not logged in")
	$Label.text = "%s  ·  Esc to log out" % who


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		set_process_unhandled_input(false)
		await Session.logout()
		get_tree().change_scene_to_file(LOGIN_SCENE)
