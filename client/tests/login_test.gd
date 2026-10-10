extends Node
## Drives the login screen like a player would, against a running server.
##   godot --headless --path client res://tests/login_test.tscn
## Exit code 0 = all checks passed.

const LoginScene := preload("res://scenes/login.tscn")

var _failures := 0
var _screen: Node


func _ready() -> void:
	Session.token = "" # don't auto-resume a saved session
	var id := str(randi() % 100000)
	var user := "ui_" + id
	var password := "pikachu-thunder"
	_screen = LoginScene.instantiate()
	_screen.enter_world_on_login = false
	add_child(_screen)
	await get_tree().process_frame

	print("validation (no server needed)")
	await _try("ab", password)
	_check("short username rejected", _screen.status_text().begins_with("Username"))
	_screen.set_registering(true)
	await _try(user, password, "different-password", "Ash")
	_check("mismatched passwords rejected", _screen.status_text() == "Passwords don't match.")

	print("register")
	await _try(user, password, password, "Ash " + id)
	_check("registered and logged in", Session.is_logged_in(), _screen.status_text())
	_check("trainer name from server", Session.trainer.get("name") == "Ash " + id, str(Session.trainer))
	await _try(user, password, password, "Other " + id)
	_check("taken username shows server error", _screen.status_text() == "That username is taken.", _screen.status_text())

	print("logout + login")
	await Session.logout()
	_check("logged out", not Session.is_logged_in())
	_screen.set_registering(false)
	await _try(user, "wrong-password-1")
	_check("wrong password shows error", _screen.status_text() == "Wrong username or password.", _screen.status_text())
	await _try(user.to_upper(), password)
	_check("login works", Session.is_logged_in(), _screen.status_text())
	var saved_token := Session.token
	Session.trainer = {}
	_check("resume with token", await Session.resume() and Session.token == saved_token)

	print("server down")
	var real_url := Session.server_url
	Session.server_url = "http://127.0.0.1:1"
	await _try(user, password)
	_check("unreachable server explained", _screen.status_text().begins_with("Can't reach the server"), _screen.status_text())
	Session.server_url = real_url
	await Session.logout()

	print("\nall checks passed" if _failures == 0 else "\n%d check(s) failed" % _failures)
	get_tree().quit(1 if _failures else 0)


## Fills the visible fields and presses the button, then waits for the request to finish.
func _try(username: String, password: String, confirm := "", trainer_name := "") -> void:
	Session.trainer = {}
	_screen.get_node("%Username").text = username
	_screen.get_node("%Password").text = password
	_screen.get_node("%ConfirmPassword").text = confirm
	_screen.get_node("%TrainerName").text = trainer_name
	await _screen.submit()


func _check(name: String, ok: bool, detail := "") -> void:
	print(("  ok   " if ok else "  FAIL ") + name + ("" if ok or detail == "" else " — " + detail))
	if not ok:
		_failures += 1
