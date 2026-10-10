class_name NpcModel extends Node3D
## A story/NPC character from the asset cache (`asset-cache/npc/<id>/`, exported by
## `BchTool export ... --motions` from an `a/0/2/1` pack): one pre-assembled model plus its motions.
## Motion numbers follow the same layout as the player's: 0 = stand, 2 = walk.

const FOLDER := "res://asset-cache/npc/%s"

var player: AnimationPlayer
var id: String


## Returns null when that character isn't in the asset cache.
static func create(npc_id: String) -> NpcModel:
	var folder := FOLDER % npc_id
	var path := folder.path_join(npc_id + ".dae")
	if not ResourceLoader.exists(path):
		return null
	var n := NpcModel.new()
	n.id = npc_id
	var model := (load(path) as PackedScene).instantiate()
	n.add_child(model)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel := skels[0] as Skeleton3D
		var skin := TrainerModel._skin_from_pose(skel)
		for c in model.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			mi.skeleton = mi.get_path_to(skel)
			mi.skin = skin
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s) as StandardMaterial3D
				if mat:
					mat = mat.duplicate() as StandardMaterial3D
					TrainerModel._fix_transparency(mat)
					mi.set_surface_override_material(s, mat)
	n.player = AnimationPlayer.new()
	model.add_child(n.player)
	n.player.root_node = NodePath("..")
	n.player.add_animation_library("", _motions(npc_id))
	return n


func play_motion(index: int, loop := true, speed := 1.0) -> bool:
	var anim := "mot%02d" % index
	if not player.has_animation(anim):
		return false
	player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	player.play(anim, 0.15, speed)
	return true


func motion_list() -> Array[int]:
	var out: Array[int] = []
	for a in player.get_animation_list():
		out.append(int(a.substr(3)))
	return out


static var _libraries := {}

static func _motions(npc_id: String) -> AnimationLibrary:
	if _libraries.has(npc_id):
		return _libraries[npc_id]
	var library := AnimationLibrary.new()
	var folder := FOLDER % npc_id
	var pattern := RegEx.create_from_string("_mot(\\d+)\\.dae$")
	for file in DirAccess.get_files_at(folder):
		var m := pattern.search(file)
		if m == null or not file.ends_with(".dae"):
			continue
		var scene := (load(folder.path_join(file)) as PackedScene).instantiate()
		var src := scene.find_children("*", "AnimationPlayer", true, false)
		if not src.is_empty():
			var ap := src[0] as AnimationPlayer
			var names := ap.get_animation_list()
			if not names.is_empty():
				library.add_animation("mot%02d" % int(m.get_string(1)), ap.get_animation(names[0]).duplicate())
		scene.free()
	_libraries[npc_id] = library
	return library
