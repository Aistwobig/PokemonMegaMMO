class_name WakeupCutscene extends Node3D
## X/Y's opening wake-up scene, from the game's own data (a/1/6/5 entries 507–527, exported to
## asset-cache/cutscenes/wakeup): the bedroom, the blanket, Fletchling flying in and the feathers
## it leaves, the player waking up, all animated on one 600-frame (20 s) timeline and filmed by the
## game's camera ("bird_cam"). Everything is authored in the same space, so it plays as it is.
##   var scene := WakeupCutscene.new(look); add_child(scene); await scene.finished

signal finished

const FOLDER := "res://asset-cache/cutscenes/wakeup/%s"
const FRAMES := 600
const FPS := 30.0

var look: Dictionary
var camera: CutsceneCamera
var player_model: TrainerModel
var _models: Array[NpcModel] = []


func _init(trainer_look: Dictionary) -> void:
	look = trainer_look


## Whether the asset cache has this scene (older imports don't).
static func available() -> bool:
	return FileAccess.file_exists((FOLDER % "bird_cam.camera.json"))


func _ready() -> void:
	var g := "m" if str(look.get("gender", "f2")) == "f2" else "f"
	if get_viewport().find_children("*", "WorldEnvironment", true, false).is_empty():
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color.BLACK
		add_child(env)
	# The room (the player's bedroom, girl's or boy's) with the game's materials.
	var room := Node3D.new()
	room.set_script(load("res://scripts/phase0_materials.gd"))
	var bg_path := (FOLDER % "opening_bg_%s/opening_bg_%s.dae") % [g, g]
	room.add_child((load(bg_path) as PackedScene).instantiate())
	add_child(room)
	for id in ["opening_blanket_" + g, "opening_feather", "fletchling", "opening_shadow"]:
		var m := NpcModel.create(id, FOLDER)
		if m:
			add_child(m)
			_models.append(m)
	player_model = TrainerModel.from_look(look)
	if player_model:
		add_child(player_model)
		var anim_scene := (load(FOLDER % ("opening_tr_%s_mot00.dae" % g)) as PackedScene).instantiate()
		var ap := anim_scene.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			var lib := AnimationLibrary.new()
			var a := (ap[0] as AnimationPlayer)
			lib.add_animation("wakeup", a.get_animation(a.get_animation_list()[0]).duplicate())
			player_model.player.add_animation_library("cutscene", lib)
		anim_scene.free()
	camera = CutsceneCamera.new()
	add_child(camera)
	camera.data = CutsceneCamera.load_file(FOLDER % "bird_cam.camera.json")
	camera.make_current()
	camera._apply(0)


## Plays the scene from the start; `finished` fires at the end (also returned for await).
func play() -> void:
	for m in _models:
		if m.player.has_animation("mot00"):
			m.player.get_animation("mot00").loop_mode = Animation.LOOP_NONE
			m.player.play("mot00", 0.0)
	if player_model and player_model.player.has_animation("cutscene/wakeup"):
		player_model.player.play("cutscene/wakeup", 0.0)
	camera.play(FOLDER % "bird_cam.camera.json")
	await camera.finished
	finished.emit()


## Jumps every animation and the camera to `frame` (for previews and tests).
func seek(frame: float) -> void:
	var t := frame / FPS
	for m in _models:
		if m.player.has_animation("mot00"):
			m.player.play("mot00", 0.0)
			m.player.seek(t, true)
			m.player.pause()
	if player_model and player_model.player.has_animation("cutscene/wakeup"):
		player_model.player.play("cutscene/wakeup", 0.0)
		player_model.player.seek(t, true)
		player_model.player.pause()
	camera._apply(frame)
