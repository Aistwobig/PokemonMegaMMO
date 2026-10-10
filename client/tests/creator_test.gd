extends Node
## Drives character creation against a running server: register, change the look, save.
##   godot --path client res://tests/creator_test.tscn          (add --write-movie for screenshots)
## Exit code 0 = all checks passed.

const CreatorScene := preload("res://scenes/character_creator.tscn")

var _failures := 0


func _ready() -> void:
	Session.token = ""
	var id := str(randi() % 100000)
	var err := await Session.register("look_" + id, "pikachu-thunder", "Look " + id, false)
	_check("registered", err == "", err)
	_check("new trainer has no look yet", not Session.has_appearance())

	var creator := CreatorScene.instantiate()
	creator.return_to_world = false
	add_child(creator)
	await _wait(1.0) # screenshot: default girl

	creator.step_style("hair", 1)
	creator.step_style("tops", 2)
	creator.step_color("tops", 1)
	creator.step_style("socks", 3)
	creator.step_style("skin", 2)
	await _wait(1.0) # screenshot: edited girl
	_check("girl look is valid locally", creator.look.gender == "f1" and creator.look.parts.has("hair"))

	creator.set_gender("f2")
	creator.step_style("hat", 1)
	creator.step_color("tops", 2)
	creator.step_style("hair_color", 3)
	creator.step_style("skin", 1)
	await _wait(1.0) # screenshot: boy
	creator.save()
	await creator.saved
	_check("look saved to the server", Session.has_appearance(), str(Session.trainer))
	_check("saved look is the boy", Session.trainer.appearance.get("gender") == "f2", str(Session.trainer.appearance))
	_check("hair color kept", int(Session.trainer.appearance.get("hairColor", -1)) == creator.look.hairColor)

	var server_look: Dictionary = Session.trainer.appearance
	Session.trainer = {}
	var ok := await Session.resume()
	_check("look comes back after re-login", ok and Session.trainer.appearance == server_look)

	await Session.logout()
	print("\nall checks passed" if _failures == 0 else "\n%d check(s) failed" % _failures)
	get_tree().quit(1 if _failures else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(name: String, ok: bool, detail := "") -> void:
	print(("  ok   " if ok else "  FAIL ") + name + ("" if ok or detail == "" else " — " + detail))
	if not ok:
		_failures += 1
