extends Node3D
## The opening, as in Pokémon X: Professor Sycamore welcomes the player to Kalos, asks what they
## look like (character creation) and confirms their name, then the player wakes up at home.
## Text and models come from the player's RomFS (game text 100). Sycamore is his full-size cutscene
## model (bt0006, a/1/4/0 entries 25 + 28) with the game's own intro gestures.
##
## The set is the game's: the grey hall with its floor grid (BG_top) and the painting wall from
## a/1/1/5, filmed partly by the game's own intro camera ("hakasecam", 2040 frames) — the close-up
## on his face, the pan across the painting of Pokémon and the final sweep — and partly by the fixed
## wide shot the game's code sets up (matched to screenshots of the real intro). He tosses a Poké Ball
## and his Skiddo comes out, as in X/Y. Older asset caches without the intro set get a simple stage.

const HOME_SCENE := "res://scenes/home.tscn"
const CREATOR_SCENE := "res://scenes/character_creator.tscn"
const SET := "res://asset-cache/cutscenes/intro/%s"
const HAKASECAM := "res://asset-cache/cutscenes/intro/hakasecam.camera.json"
const SYCAMORE := "bt0006"
## bt0006's "ba90_opening" motions (story pack 2): 247 = his talking idle (a 10 s loop that sways
## and breathes), 249 / 250 / 252 / 254 = the gestures he makes while welcoming you to Kalos. (248 and
## 255 are held poses and 251 / 253 short transitions: on their own they freeze him.)
const IDLE := 247
const GESTURES := [249, 250, 252, 254]
const THROW := 249 # the gesture used for tossing the Poké Ball
## The chibi fallback: overworld motions 103–107 are its talking gestures, 0 is standing.
const CHIBI_SYCAMORE := "tr0006"
const CHIBI_IDLE := 0
const CHIBI_GESTURES := [103, 104, 105, 106, 107]

## hakasecam's parts used here (frames at 30 fps).
const CAM_CLOSEUP := [0.0, 190.0] # Sycamore's face, "Welcome to the world of Pokémon!"
const CAM_PAINTING := [1650.0, 1725.0] # rising onto the painting: "These mysterious creatures..."
const WALL_DROP := -55.0 # the painting wall sits this much lower for that shot (placed by the game's code)
const CAM_FINALE := [1630.0, 2040.0] # the sweep to the door at the end
## The fixed wide shot (the code's camera): Sycamore right of centre, full length, as in the game.
const WIDE_FOV := 27.5
const WIDE_POS := Vector3(-62, 105, 586)
const WIDE_LOOK := Vector3(-62, 85, 0)
const SKIDDO_AT := Vector3(-128, 0, 40)
const SKIDDO_HEIGHT := 86.0
const PLAYER_AT := Vector3(-100, 0, 40)
const PLAYER_IDLE := 4 # the full-size player's breathing idle (trainers/b1|b2 motion 4)
const SKIDDO_MOVES_TO := Vector3(-215, 0, 60) # steps aside to make room for the player

var _idle := IDLE
var _gestures: Array = GESTURES
var _game_set := false

var _stage: Node3D
var _camera: Camera3D
var _cutcam: CutsceneCamera
var _sycamore: NpcModel
var _skiddo: NpcModel
var _wall: Node3D # the painting wall: only in the painting shot (the rest happens in open space)
var _player: TrainerModel
var _box: DialogueBox
var _fade: ScreenFade
var _skip: Button
var _gesture := 0


func _ready() -> void:
	Music.play(Music.INTRO)
	_game_set = ResourceLoader.exists(SET % "BG_top.dae") and FileAccess.file_exists(HAKASECAM)
	if _game_set:
		_build_game_set()
	else:
		_build_stage()
	_box = DialogueBox.new()
	_box.speaker = "Professor Sycamore"
	add_child(_box)
	_box.talkers["Professor Sycamore"] = LipSync.attach(_sycamore)
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
	if _game_set:
		_cutcam.play_range(HAKASECAM, CAM_CLOSEUP[0], CAM_CLOSEUP[1])
	await _fade.clear(1.2)
	await _talk([23])
	_wide_shot()
	await _talk([24])
	if _game_set:
		await _send_out_skiddo()
	await _say_lines([25])
	if _game_set:
		_set_painting(true)
		_cutcam.play_range(HAKASECAM, CAM_PAINTING[0], CAM_PAINTING[1])
	await _say_lines([26, 27])
	_set_painting(false)
	_wide_shot()
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
	await _say_lines(lines)


func _say_lines(lines: Array) -> void:
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
	var g: int = _gestures[_gesture % _gestures.size()]
	_gesture += 1
	_gesture_once(g)


func _gesture_once(g: int) -> void:
	if _sycamore.play_motion(g, false):
		var idle := "mot%02d" % _idle
		_sycamore.player.get_animation(idle).loop_mode = Animation.LOOP_LINEAR
		_sycamore.player.queue(idle)


## The painting shot: the wall in, the professor and Skiddo out of the picture.
func _set_painting(on: bool) -> void:
	if _wall:
		_wall.visible = on
	for n in [_sycamore, _skiddo, _player]:
		if n and n != _skiddo:
			n.visible = not on
	if _skiddo and _skiddo_out:
		_skiddo.visible = not on


var _skiddo_out := false


## The fixed full-length shot of the professor (and whoever is with him).
func _wide_shot() -> void:
	if not _game_set:
		return
	_cutcam.playing = false
	_camera.fov = WIDE_FOV
	_camera.look_at_from_position(WIDE_POS, WIDE_LOOK)
	_camera.make_current()


## He tosses a Poké Ball; it pops open in a flash of light and his Skiddo stands beside him.
func _send_out_skiddo() -> void:
	_gesture_once(THROW)
	var ball := (load(SET % "monsball.dae") as PackedScene).instantiate() as Node3D
	ball.scale = Vector3.ONE * 1.6
	_stage.add_child(ball)
	var from := Vector3(-30, 120, 10)
	var to := SKIDDO_AT + Vector3(0, 10, 0)
	ball.position = from
	var arc := create_tween()
	arc.tween_method(func(k: float) -> void:
		ball.position = from.lerp(to, k) + Vector3.UP * sin(k * PI) * 70.0
		ball.rotation.z = -k * TAU * 1.5, 0.0, 1.0, 0.7)
	await arc.finished
	var flash := OmniLight3D.new()
	flash.position = to
	flash.light_energy = 6.0
	flash.omni_range = 220.0
	_stage.add_child(flash)
	ball.queue_free()
	if _skiddo:
		_skiddo.visible = true
		_skiddo_out = true
		var size := _skiddo.scale
		_skiddo.scale = size * 0.05
		create_tween().tween_property(_skiddo, "scale", size, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if not _skiddo.play_motion(1, false): # battle "appear"
			_skiddo.play_motion(0)
		else:
			_skiddo.player.get_animation("mot00").loop_mode = Animation.LOOP_LINEAR
			_skiddo.player.queue("mot00")
	await create_tween().tween_property(flash, "light_energy", 0.0, 0.5).finished
	flash.queue_free()


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
	_wide_shot()
	_camera.make_current()
	if _skip.disabled: # Skip was pressed before creating the character
		await _finish()


## The player's new look appears beside the professor.
func _show_player() -> void:
	if not Session.has_appearance() or _player:
		return
	var look: Dictionary = Session.trainer.appearance
	var full := TrainerModel.full_look(look) if _game_set else {}
	_player = TrainerModel.from_look(full if not full.is_empty() else look)
	if _player == null:
		return
	_stage.add_child(_player)
	if _game_set:
		# The full-size ("anime") version of the look just made, as in X/Y.
		if not full.is_empty() and PLAYER_IDLE in _player.motions:
			_player.play_motion(PLAYER_IDLE)
			_player.scale = Vector3.ONE * 0.86 # a teenager next to the professor
		else:
			_player.scale = Vector3.ONE * 2.6 # no full-size parts imported: enlarge the overworld model
			_player.play_motion(TrainerModel.MOTION_STAND)
		_player.position = PLAYER_AT
		_player.rotation_degrees.y = 18
		BlobShadow.attach(_player, 34.0, 0.35)
		if _skiddo:
			create_tween().tween_property(_skiddo, "position", SKIDDO_MOVES_TO, 0.5).set_trans(Tween.TRANS_SINE)
		_wide_shot()
		return
	_player.play_motion(TrainerModel.MOTION_STAND)
	_player.position = Vector3(26, 0, 6)
	_player.rotation_degrees.y = -20
	create_tween().tween_property(_sycamore, "position:x", -22.0, 0.6).set_trans(Tween.TRANS_SINE)
	create_tween().tween_property(_camera, "position", Vector3(2, 38, 190), 0.6).set_trans(Tween.TRANS_SINE)


var _finishing := false

func _finish() -> void:
	if _finishing or not is_inside_tree():
		return
	_finishing = true
	_box.visible = false
	if _game_set:
		_cutcam.play_range(HAKASECAM, CAM_FINALE[0], CAM_FINALE[1])
		await get_tree().create_timer((CAM_FINALE[1] - CAM_FINALE[0]) / 30.0 - 1.4).timeout
	else:
		var zoom := create_tween()
		zoom.tween_property(_camera, "fov", 12.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _fade.to(Color.WHITE, 1.4)
	get_tree().change_scene_to_file.call_deferred(HOME_SCENE)


## The game's intro set: the hall with its floor grid and the painting wall, Sycamore at its centre
## (full size, as the intro camera expects), Skiddo hidden until it's sent out.
func _build_game_set() -> void:
	_stage = Node3D.new()
	add_child(_stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.35, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	_stage.add_child(env)
	var set_root := Node3D.new()
	set_root.set_script(load("res://scripts/phase0_materials.gd")) # the game's materials
	set_root.add_child((load(SET % "BG_top.dae") as PackedScene).instantiate())
	_wall = (load(SET % "intro_wall.dae") as PackedScene).instantiate()
	_wall.position.y = WALL_DROP
	set_root.add_child(_wall)
	_stage.add_child(set_root)
	_sycamore = NpcModel.create(SYCAMORE)
	if _sycamore == null:
		_sycamore = NpcModel.create(CHIBI_SYCAMORE)
		_idle = CHIBI_IDLE
		_gestures = CHIBI_GESTURES
	if _sycamore:
		_stage.add_child(_sycamore)
		BlobShadow.attach(_sycamore, 40.0, 0.35)
		_sycamore.player.playback_default_blend_time = 0.35
		_sycamore.play_motion(_idle)
	_skiddo = NpcModel.create("skiddo", NpcModel.POKEMON)
	if _skiddo:
		_stage.add_child(_skiddo)
		var box := AABB()
		var first := true
		for c in _skiddo.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (c as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		_skiddo.scale = Vector3.ONE * (SKIDDO_HEIGHT / maxf(box.size.y, 1.0))
		_skiddo.position = SKIDDO_AT
		_skiddo.rotation_degrees.y = 25 # turned towards the camera and the professor
		BlobShadow.attach(_skiddo, 34.0, 0.4)
		_skiddo.visible = false
	_camera = Camera3D.new()
	_camera.far = 20000
	_stage.add_child(_camera)
	_cutcam = CutsceneCamera.new()
	_cutcam.far = 20000
	_stage.add_child(_cutcam)
	_set_painting(false)
	_wide_shot()


## Fallback stage for asset caches without the intro set.
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
	_stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.6
	_stage.add_child(sun)
	_sycamore = NpcModel.create(SYCAMORE)
	if _sycamore:
		_sycamore.scale = Vector3.ONE * 0.45
	else:
		_sycamore = NpcModel.create(CHIBI_SYCAMORE)
		_idle = CHIBI_IDLE
		_gestures = CHIBI_GESTURES
	if _sycamore:
		_stage.add_child(_sycamore)
		_sycamore.player.playback_default_blend_time = 0.35
		_sycamore.play_motion(_idle)
	_camera = Camera3D.new()
	_camera.fov = 30
	_camera.position = Vector3(0, 40, 175)
	_camera.rotation_degrees.x = -4
	_stage.add_child(_camera)
	_camera.make_current()
