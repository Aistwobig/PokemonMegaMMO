extends CanvasLayer
## Minimal in-world HUD: who you're logged in as. P is the party (world.gd), C changes your look,
## Esc logs out.

const LOGIN_SCENE := "res://scenes/login.tscn"
const CREATOR_SCENE := "res://scenes/character_creator.tscn"


func _ready() -> void:
	var who: String = Session.trainer.get("name", "not logged in")
	$Label.text = "%s  ·  P Pokémon  ·  C change look  ·  Esc log out" % who


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		set_process_unhandled_input(false)
		await Session.logout()
		get_tree().change_scene_to_file(LOGIN_SCENE)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		get_tree().change_scene_to_file(CREATOR_SCENE)
