extends Node
## Login state shared by every scene (autoload "Session").
## Talks to the server's /auth endpoints — see server/README.md for the API.

const SAVE_PATH := "user://session.cfg"

var server_url := "http://localhost:2567"
var token := ""
var trainer := {} # { name, mapId, x, y, facing, appearance, introDone }


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		server_url = cfg.get_value("server", "url", server_url)
		token = cfg.get_value("session", "token", "")


func is_logged_in() -> bool:
	return token != "" and not trainer.is_empty()


## Each of these returns "" on success, or an error message to show the player.
func login(username: String, password: String, remember: bool) -> String:
	var res := await _request(HTTPClient.METHOD_POST, "/auth/login", {username = username, password = password})
	return _accept(res, remember)


func register(username: String, password: String, trainer_name: String, remember: bool) -> String:
	var res := await _request(HTTPClient.METHOD_POST, "/auth/register",
		{username = username, password = password, trainerName = trainer_name})
	return _accept(res, remember)


## Logs back in with a token saved by "Stay logged in". Returns true if it's still valid.
func resume() -> bool:
	if token == "":
		return false
	var res := await _request(HTTPClient.METHOD_GET, "/auth/me")
	if res.code == 200:
		trainer = res.data.trainer
		return true
	if res.code == 401:
		_set_session("", {}, false) # expired or logged out elsewhere; keep it if the server was just down
	return false


## Saves the look from character creation. Returns "" or an error message.
func save_appearance(look: Dictionary) -> String:
	var res := await _request(HTTPClient.METHOD_PUT, "/trainer/appearance", {look = look})
	if res.code == 200:
		trainer = res.data.trainer
		return ""
	if res.code == 0:
		return "Can't reach the server at %s. Is it running?" % server_url
	return res.data.get("error", "Something went wrong (error %d)." % res.code)


func has_appearance() -> bool:
	return trainer.get("appearance") is Dictionary


func intro_done() -> bool:
	return trainer.get("introDone", false) == true


## Tells the server the intro was seen, so it doesn't play again. Returns "" or an error message.
func complete_intro() -> String:
	var res := await _request(HTTPClient.METHOD_POST, "/trainer/intro")
	if res.code == 200:
		trainer = res.data.trainer
		return ""
	if res.code == 0:
		return "Can't reach the server at %s. Is it running?" % server_url
	return res.data.get("error", "Something went wrong (error %d)." % res.code)


## The party and bag: { party: [{species, name, level, hp, maxHp, ...}], items: {pokeball: n} }, or {} if
## the server can't be reached.
func get_party() -> Dictionary:
	var res := await _request(HTTPClient.METHOD_GET, "/trainer/party")
	return res.data if res.code == 200 else {}


## Picks the first Pokémon (chespin, fennekin or froakie). Returns "" or an error message.
func choose_starter(species: String) -> String:
	var res := await _request(HTTPClient.METHOD_POST, "/trainer/starter", {species = species})
	if res.code == 201:
		return ""
	if res.code == 0:
		return "Can't reach the server at %s. Is it running?" % server_url
	return res.data.get("error", "Something went wrong (error %d)." % res.code)


## "f1" (girl) or "f2" (boy), for text that differs by gender.
func gender() -> String:
	return trainer.get("appearance").get("gender", "f2") if has_appearance() else "f2"


func logout() -> void:
	await _request(HTTPClient.METHOD_POST, "/auth/logout")
	_set_session("", {}, false)


func _accept(res: Dictionary, remember: bool) -> String:
	if res.code == 200 or res.code == 201:
		_set_session(res.data.token, res.data.trainer, remember)
		return ""
	if res.code == 0:
		return "Can't reach the server at %s. Is it running?" % server_url
	return res.data.get("error", "Something went wrong (error %d)." % res.code)


func _set_session(new_token: String, new_trainer: Dictionary, remember: bool) -> void:
	token = new_token
	trainer = new_trainer
	var cfg := ConfigFile.new()
	cfg.set_value("server", "url", server_url)
	cfg.set_value("session", "token", token if remember else "")
	cfg.save(SAVE_PATH)


## Returns { code, data }. code is 0 when the server couldn't be reached.
func _request(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var err := http.request(server_url + path, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		http.queue_free()
		return {code = 0, data = {}}
	var result: Array = await http.request_completed # [result, response_code, headers, body]
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {code = 0, data = {}}
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(text) if text != "" else null # 204 responses have no body
	return {code = result[1], data = data if data is Dictionary else {}}
