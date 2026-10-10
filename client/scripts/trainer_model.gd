class_name TrainerModel
extends Node3D
## A trainer model from the asset cache with its overworld motions.
## The motions are separate DAE files (<name>_motNN.dae) that share the model's skeleton; their
## animations are copied into one AnimationPlayer here as "mot00", "mot01", ...

const CACHE := "res://asset-cache/trainers/%s/%s.dae"
const FOLDER := "res://asset-cache/trainers/%s"

var player: AnimationPlayer
## Motion numbers present (the game's motion packs have empty slots, so there are gaps).
var motions: Array[int] = []


## Returns null when the trainer isn't in the asset cache.
static func create(trainer_name: String, load_motions := true) -> TrainerModel:
	var path := CACHE % [trainer_name, trainer_name]
	if not ResourceLoader.exists(path):
		return null
	var t := TrainerModel.new()
	t.name = trainer_name.capitalize()
	var model := (load(path) as PackedScene).instantiate()
	bind_skins(model)
	t.add_child(model)
	t.player = AnimationPlayer.new()
	model.add_child(t.player)
	t.player.root_node = NodePath("..")
	if load_motions:
		t._load_motions(trainer_name)
	return t


func _load_motions(trainer_name: String) -> void:
	var library := AnimationLibrary.new()
	var folder := FOLDER % trainer_name
	var pattern := RegEx.create_from_string("_mot(\\d+)\\.dae$")
	for file in DirAccess.get_files_at(folder):
		var m := pattern.search(file)
		if m == null:
			continue
		var scene := (load(folder.path_join(file)) as PackedScene).instantiate()
		var src := scene.find_children("*", "AnimationPlayer", true, false)
		if not src.is_empty():
			var ap := src[0] as AnimationPlayer
			var names := ap.get_animation_list()
			if not names.is_empty():
				library.add_animation("mot%02d" % int(m.get_string(1)), ap.get_animation(names[0]).duplicate())
				motions.append(int(m.get_string(1)))
		scene.free()
	motions.sort()
	player.add_animation_library("", library)


## Godot's DAE import keeps SPICA's bone weights but drops the skin binding, so meshes don't follow
## the skeleton. The mesh is modeled around the bones' starting pose (the DAE node transforms), so
## the skin is built from that pose, and the pose becomes the rest the animations play against.
static func bind_skins(model: Node) -> void:
	for s in model.find_children("*", "Skeleton3D", true, false):
		var skel := s as Skeleton3D
		var skin := Skin.new()
		for i in skel.get_bone_count():
			skin.add_named_bind(skel.get_bone_name(i), skel.get_bone_global_pose(i).affine_inverse())
		for i in skel.get_bone_count():
			skel.set_bone_rest(i, skel.get_bone_pose(i))
		for c in skel.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi.skin == null and mi.mesh and (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES):
				mi.skin = skin
				mi.skeleton = mi.get_path_to(skel)


func play_motion(index: int, speed := 1.0) -> void:
	var anim := "mot%02d" % index
	if player.has_animation(anim):
		player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
		player.play(anim, 0.15, speed)
