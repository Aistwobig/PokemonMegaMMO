class_name NeighborsScene extends Node3D
## Stepping out of the house for the first time, as in X/Y: Shauna and the neighbor (Serena for boys,
## Calem for girls) come up to say hello and invite the player to the next town, Rhyhorn roars in
## the yard, and Mom sees them off. Lines from story text 57; places from zone 0's NPC list
## (Shauna (26, 40), the neighbor (28, 40), Mom at the door (27, 36), Rhyhorn in the yard (30, 42)).
## Played locally in the online world; only the player sees it.

signal finished

const SHAUNA := "tr0003"
const MOM := "tr0007"
const RHYHORN := "pm0111"
const STEP := 0.28

var _world: Node # world.gd, for tile → world positions
var _player: Node3D
var _box: DialogueBox
var _name := ""
var _gender := "f2"


func _init(world: Node, player: Node3D) -> void:
	_world = world
	_player = player


func _ready() -> void:
	_name = Session.trainer.get("name", "Trainer")
	_gender = Session.gender()
	_box = DialogueBox.new()
	add_child(_box)
	_run()


func _run() -> void:
	var girl := _gender == "f1"
	var neighbor_name := "Calem" if girl else "Serena"
	# The neighbor is the other player character in their default outfit.
	var neighbor: Node3D = TrainerModel.from_look(TrainerModel.default_look("f2" if girl else "f1"))
	var shauna: Node3D = NpcModel.create(SHAUNA)
	var rhyhorn: Node3D = NpcModel.create(RHYHORN)
	for n: Node3D in [neighbor, shauna, rhyhorn]:
		if n:
			add_child(n)
	if rhyhorn:
		_place(rhyhorn, Vector2i(30, 42), "left")
		rhyhorn.scale = Vector3.ONE * 1.2
		_motion(rhyhorn, 0)
	_face_player("down")
	await _wait(0.6)

	# They run up from the lane.
	if neighbor:
		_place(neighbor, Vector2i(27, 43), "up")
	if shauna:
		_place(shauna, Vector2i(26, 43), "up")
	# Side by side: the neighbor's walk runs alongside Shauna's (same length), we wait for Shauna's.
	_walk(neighbor, [Vector2i(27, 42), Vector2i(27, 41), Vector2i(27, 40), Vector2i(27, 39), Vector2i(27, 38)], 3)
	await _walk(shauna, [Vector2i(26, 42), Vector2i(26, 41), Vector2i(26, 40), Vector2i(26, 39), Vector2i(26, 38)], 3)
	await _wait(0.1)
	_face(shauna, "right")
	await _say(neighbor_name, 2 if girl else 1) # Welcome to Vaniville Town! I'm your neighbor.
	_face(shauna, "up")
	await _say("Shauna", 3) # And I'm Shauna! Great to meet you! We've come to get you!
	await _say(neighbor_name, 5 if girl else 4) # Professor Sycamore has a request for five kids...
	await _say("Shauna", 6) # We'll wait for you in the next town over! We're going to get...a Pokémon!

	# Rhyhorn wakes up in the yard.
	if rhyhorn:
		_face(rhyhorn, "left")
	await _say("Rhyhorn", 7) # Grr... Groo...
	if rhyhorn:
		var start := rhyhorn.position
		var hop := create_tween()
		hop.tween_property(rhyhorn, "position:y", start.y + 14, 0.15)
		hop.tween_property(rhyhorn, "position:y", start.y, 0.15)
		hop.tween_property(rhyhorn, "position:y", start.y + 10, 0.12)
		hop.tween_property(rhyhorn, "position:y", start.y, 0.12)
	await _say("Rhyhorn", 8) # Roaaaah!
	_face(shauna, "right")
	await _say("Shauna", 9) # What was that just now?

	# Mom comes out of the door behind the player.
	var mom: Node3D = NpcModel.create(MOM)
	if mom:
		add_child(mom)
		_place(mom, Vector2i(27, 36), "down")
		mom.position.z += 6.0 # just outside the door
		_motion(mom, 0)
	_face_player("up")
	await _say("Mom", 10) # Ha ha ha! What a card! Rhyhorn just wanted to give you a send-off!

	# The friends head off to Aquacorde.
	_walk(neighbor, [Vector2i(27, 39), Vector2i(27, 40), Vector2i(27, 41), Vector2i(27, 42), Vector2i(27, 43), Vector2i(27, 44)], 3)
	await _walk(shauna, [Vector2i(26, 39), Vector2i(26, 40), Vector2i(26, 41), Vector2i(26, 42), Vector2i(26, 43), Vector2i(26, 44)], 3)
	await _wait(0.1)
	for n: Node3D in [neighbor, shauna]:
		if n:
			n.queue_free()
	await _say("Mom", 11) # Good luck! Go for broke! You'll have Pokémon by your side.
	if mom:
		await create_tween().tween_property(mom, "scale", Vector3.ONE * 0.01, 0.25).finished
		mom.queue_free()
	_face_player("down")
	await Session.mark_story("neighbors")
	finished.emit()
	queue_free()


func _say(speaker: String, line: int) -> void:
	_box.speaker = speaker
	var pages := GameText.pages(GameText.NEIGHBORS, line, _name, _gender)
	if not pages.is_empty():
		await _box.say(pages)


func _place(n: Node3D, tile: Vector2i, facing: String) -> void:
	n.position = _world._tile_to_world(tile.x, tile.y)
	_face(n, facing)


func _face(n: Node3D, facing: String) -> void:
	if n:
		n.rotation_degrees.y = {"down": 0.0, "up": 180.0, "left": -90.0, "right": 90.0}[facing]


func _face_player(facing: String) -> void:
	_face(_player, facing)


func _motion(n: Node3D, index: int) -> void:
	if n is NpcModel:
		(n as NpcModel).play_motion(index)
	elif n is TrainerModel:
		(n as TrainerModel).play_motion(index)


## Walks (or runs, motion 3) along tiles; returns when there.
func _walk(n: Node3D, path: Array, motion: int) -> void:
	if n == null:
		return
	_motion(n, motion if n is TrainerModel else 2)
	for t: Vector2i in path:
		var to: Vector3 = _world._tile_to_world(t.x, t.y)
		var d := to - n.position
		if absf(d.x) > absf(d.z):
			_face(n, "right" if d.x > 0 else "left")
		else:
			_face(n, "down" if d.z > 0 else "up")
		await create_tween().tween_property(n, "position", to, STEP * (0.6 if motion == 3 else 1.0)).finished
	_motion(n, 0)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
