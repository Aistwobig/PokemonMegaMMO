extends Node3D
## The opening, as in Pokémon X: Professor Sycamore welcomes the player to Kalos, asks what they
## look like (character creation) and confirms their name, then the player wakes up at home.
## Text and models come from the player's RomFS (game text 100, NPC model tr0006).

const HOME_SCENE := "res://scenes/home.tscn"
const CREATOR_SCENE := "res://scenes/character_creator.tscn"
const SYCAMORE := "tr0006"
## Sycamore's talking gestures (his model's motions 103–107); 0 is standing.
const GESTURES := [103, 104, 105, 106, 107]

var _stage: Node3D
var _camera: Camera3D
var _sycamore: NpcModel
var _player: TrainerModel
var _box: DialogueBox
var _fade: ScreenFade
var _skip: Button
var _gesture := 0


func _ready() -> void:
	_build_stage()
	_box = DialogueBox.new()
	_box.speaker = "Professor Sycamore"
	add_child(_box)
	var ui := CanvasLayer.new()
	add_child(ui)
	_skip = Button.new()
	_skip.text = "Skip intro"
	_skip.anchor_left = 1.0
	_skip.anchor_right = 1.0
	_skip.offset_left = -140
	_skip.offset_right = -20
	_skip.offset_top = 20
	_skip.offset_bottom = 56
	_skip.pressed.connect(skip)
	ui.add_child(_skip)
	_fade = ScreenFade.new()
	add_child(_fade)
	play()


func play() -> void:
	await _fade.clear(1.2)
	await _talk([23, 24])
	await _talk([25])
	await _talk([26, 27])
	await _talk([28])
	await _talk([29, 30])
	await _create_character()
	_show_player()
	if not is_inside_tree():
		return
	var name_ok := await _box.ask(_pages(32), ["Yes"])
	if name_ok == 0:
		await _talk([34])
	await _talk([35])
	await _talk([36])
	await _talk([37])
	await _finish()


## Jumps to the end. Character creation still happens if the trainer has no look yet.
func skip() -> void:
	_skip.disabled = true
	if not Session.has_appearance():
		return # the creator is next anyway; finish after it
	await _finish()


func _talk(lines: Array) -> void:
	_next_gesture()
	for i: int in lines:
		await _box.say(_pages(i))


func _pages(index: int) -> PackedStringArray:
	var pages := GameText.pages(GameText.INTRO, index, Session.trainer.get("name", "Trainer"), Session.gender())
	if pages.is_empty():
		pages = ["(Text missing — run the importer's text export.)"]
	return pages


func _next_gesture() -> void:
	if _sycamore == null:
		return
	var g: int = GESTURES[_gesture % GESTURES.size()]
	_gesture += 1
	if _sycamore.play_motion(g, false):
		_sycamore.player.get_animation("mot00").loop_mode = Animation.LOOP_LINEAR
		_sycamore.player.queue("mot00")


func _create_character() -> void:
	var creator := (load(CREATOR_SCENE) as PackedScene).instantiate()
	creator.return_to_world = false
	creator.confirm_text = "That's me!"
	remove_child(_stage) # its sky and camera would fight the creator's
	_skip.visible = false
	add_child(creator)
	await creator.saved
	creator.queue_free()
	add_child(_stage)
	_skip.visible = true
	_camera.make_current()
	if _skip.disabled: # Skip was pressed before creating the character
		await _finish()


## The player's new look appears beside the professor.
func _show_player() -> void:
	if not Session.has_appearance() or _player:
		return
	_player = TrainerModel.from_look(Session.trainer.appearance)
	if _player == null:
		return
	_player.position = Vector3(26, 0, 6)
	_player.rotation_degrees.y = -20
	_stage.add_child(_player)
	_player.play_motion(TrainerModel.MOTION_STAND)
	create_tween().tween_property(_sycamore, "position:x", -22.0, 0.6).set_trans(Tween.TRANS_SINE)
	create_tween().tween_property(_camera, "position", Vector3(2, 34, 150), 0.6).set_trans(Tween.TRANS_SINE)


var _finishing := false

func _finish() -> void:
	if _finishing or not is_inside_tree():
		return
	_finishing = true
	_box.visible = false
	var zoom := create_tween()
	zoom.tween_property(_camera, "fov", 12.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _fade.to(Color.WHITE, 1.4)
	get_tree().change_scene_to_file.call_deferred(HOME_SCENE)


func _build_stage() -> void:
	_stage = Node3D.new()
	add_child(_stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.62, 0.93)
	sky_mat.sky_horizon_color = Color(0.86, 0.93, 1.0)
	sky_mat.ground_horizon_color = Color(0.86, 0.93, 1.0)
	sky_mat.ground_bottom_color = Color(0.75, 0.85, 0.97)
	sky.sky_material = sky_mat
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	env.environment.glow_enabled = true
	_stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	_stage.add_child(sun)
	# A soft round platform for the professor to stand on.
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 70
	floor_mesh.bottom_radius = 70
	floor_mesh.height = 2
	floor_mesh.radial_segments = 64
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.95, 0.97, 1.0)
	floor_mat.roughness = 0.6
	floor_mesh.material = floor_mat
	var platform := MeshInstance3D.new()
	platform.mesh = floor_mesh
	platform.position.y = -1
	_stage.add_child(platform)

	_sycamore = NpcModel.create(SYCAMORE)
	if _sycamore:
		_stage.add_child(_sycamore)
		_sycamore.play_motion(0)
	_camera = Camera3D.new()
	_camera.fov = 30
	_camera.position = Vector3(0, 36, 120)
	_camera.rotation_degrees.x = -4
	_stage.add_child(_camera)
	_camera.make_current()
