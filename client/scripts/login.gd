extends Node
## Login / register screen. The town from the asset cache orbits in the background when present.

signal logged_in

const WORLD_SCENE := "res://scenes/world.tscn"
const CREATOR_SCENE := "res://scenes/character_creator.tscn"
const INTRO_SCENE := "res://scenes/intro.tscn"
const BACKGROUND_SCENE := "res://scenes/phase0.tscn"
const BACKGROUND_ASSET := "res://asset-cache/phase0/vaniville/vaniville_north.dae"
const USERNAME := "^[A-Za-z0-9_]{3,16}$" # same rules as the server, for instant feedback
const TRAINER_NAME := "^[\\p{L}\\p{N} ]{1,12}$"

## Tests turn this off to stay on the screen after logging in.
@export var enter_world_on_login := true

var _registering := false
var _busy := false

@onready var _login_tab: Button = %LoginTab
@onready var _register_tab: Button = %RegisterTab
@onready var _username: LineEdit = %Username
@onready var _password: LineEdit = %Password
@onready var _confirm: LineEdit = %ConfirmPassword
@onready var _trainer_name: LineEdit = %TrainerName
@onready var _remember: CheckBox = %Remember
@onready var _submit: Button = %Submit
@onready var _status: Label = %Status
@onready var _server: Label = %Server


func _ready() -> void:
	Music.play(Music.TITLE)
	_add_background()
	_login_tab.pressed.connect(_set_mode.bind(false))
	_register_tab.pressed.connect(_set_mode.bind(true))
	_submit.pressed.connect(submit)
	for field: LineEdit in [_username, _password, _confirm, _trainer_name]:
		field.text_submitted.connect(func(_t: String) -> void: submit())
	_add_server_field()
	_set_mode(false)

	if Session.token != "":
		_set_busy(true, "Logging you back in…")
		var ok := await Session.resume()
		_set_busy(false)
		if ok:
			_enter_world()
			return
		_show("", false)
	_username.grab_focus()


## The server address: "Server:" and an editable box (play on a friend's server: type their address).
func _add_server_field() -> void:
	_server.text = "Server:"
	var row := HBoxContainer.new()
	_server.get_parent().add_child(row)
	_server.get_parent().move_child(row, _server.get_index())
	_server.reparent(row)
	var box := LineEdit.new()
	box.name = "ServerAddress"
	box.text = Session.server_url.trim_prefix("http://")
	box.placeholder_text = "localhost:2567"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.tooltip_text = "The game server to play on (ask whoever hosts it). Port 2567 if you leave it out."
	var apply := func(_t: Variant = null) -> void:
		Session.set_server(box.text)
		box.text = Session.server_url.trim_prefix("http://")
	box.text_submitted.connect(apply)
	box.focus_exited.connect(apply)
	row.add_child(box)


## Switches between the Log in and Register forms.
func set_registering(registering: bool) -> void:
	_set_mode(registering)


func submit() -> void:
	if _busy:
		return
	var error := _validate()
	if error != "":
		_show(error, true)
		return
	_set_busy(true, "Creating your trainer…" if _registering else "Logging in…")
	if _registering:
		error = await Session.register(_username.text, _password.text, _clean_name(), _remember.button_pressed)
	else:
		error = await Session.login(_username.text, _password.text, _remember.button_pressed)
	_set_busy(false)
	if error != "":
		_show(error, true)
		return
	_show("Welcome, %s!" % Session.trainer.name, false)
	_enter_world()


func status_text() -> String:
	return _status.text


func _validate() -> String:
	if not RegEx.create_from_string(USERNAME).search(_username.text):
		return "Username must be 3–16 letters, digits or _."
	if _password.text.length() < 8:
		return "Password must be at least 8 characters."
	if not _registering:
		return ""
	if _password.text.to_lower().contains(_username.text.to_lower()):
		return "Password can't contain your username."
	if _confirm.text != _password.text:
		return "Passwords don't match."
	if not RegEx.create_from_string(TRAINER_NAME).search(_clean_name()):
		return "Trainer name must be 1–12 letters, digits or spaces."
	return ""


func _clean_name() -> String:
	return " ".join(_trainer_name.text.strip_edges().split(" ", false))


func _set_mode(registering: bool) -> void:
	_registering = registering
	_login_tab.button_pressed = not registering
	_register_tab.button_pressed = registering
	_confirm.visible = registering
	_trainer_name.visible = registering
	_submit.text = "Create trainer" if registering else "Log in"
	_password.placeholder_text = "Password (8+ characters)" if registering else "Password"
	_show("", false)


func _set_busy(busy: bool, message := "") -> void:
	_busy = busy
	for c: Control in [_username, _password, _confirm, _trainer_name, _remember, _submit, _login_tab, _register_tab]:
		if c is LineEdit:
			(c as LineEdit).editable = not busy
		else:
			(c as BaseButton).disabled = busy
	if busy:
		_show(message, false)


func _show(message: String, is_error: bool) -> void:
	_status.text = message
	_status.modulate = Color(1, 0.55, 0.5) if is_error else Color(0.75, 0.9, 1)


func _enter_world() -> void:
	logged_in.emit()
	if enter_world_on_login:
		# New trainers get the intro first: Sycamore's welcome (with character creation) and
		# waking up at home.
		var next := WORLD_SCENE
		if not Session.intro_done():
			next = INTRO_SCENE
		elif not Session.has_appearance():
			next = CREATOR_SCENE
		get_tree().change_scene_to_file.call_deferred(next)


func _add_background() -> void:
	if not ResourceLoader.exists(BACKGROUND_ASSET):
		return # no asset cache yet: the plain backdrop in the scene stays
	var world: Node = (load(BACKGROUND_SCENE) as PackedScene).instantiate()
	world.get_node("HUD").queue_free()
	var cam := world.get_node("Camera3D")
	cam.set("auto_orbit", 4.0)
	cam.set("distance", 1300.0)
	add_child(world)
	move_child(world, 0)
	$UI/Root/Backdrop.visible = false
