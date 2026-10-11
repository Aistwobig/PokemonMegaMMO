class_name NpcModel extends Node3D
## A story/NPC character from the asset cache (`asset-cache/npc/<id>/`, exported by
## `BchTool export ... --motions` from an `a/0/2/1` pack): one pre-assembled model plus its motions.
## Motion numbers follow the same layout as the player's: 0 = stand, 2 = walk.
## Pokémon use the same loader with POKEMON (from importer/tools/pokemon.py; motion 0 = battle idle).

const FOLDER := "res://asset-cache/npc/%s"
const POKEMON := "res://asset-cache/pokemon/%s"

var player: AnimationPlayer
var id: String


## Returns null when that character isn't in the asset cache.
static func create(npc_id: String, folder_format := FOLDER) -> NpcModel:
	var folder := folder_format % npc_id
	var path := folder.path_join(npc_id + ".dae")
	if not ResourceLoader.exists(path):
		return null
	var n := NpcModel.new()
	n.id = npc_id
	var model := (load(path) as PackedScene).instantiate()
	n.add_child(model)
	var material_info := _material_info(folder.path_join(npc_id + ".materials.json"))
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
				var mat_name := mat.resource_name.trim_suffix("_mat") if mat else "" # SPICA names them "<name>_mat"
				if mat and material_info.has(mat_name) and mat.albedo_texture:
					mi.set_surface_override_material(s, _transformed(mat, material_info[mat_name]))
				elif mat:
					mat = mat.duplicate() as StandardMaterial3D
					TrainerModel._fix_transparency(mat)
					mi.set_surface_override_material(s, mat)
	n.player = AnimationPlayer.new()
	model.add_child(n.player)
	n.player.root_node = NodePath("..")
	n.player.add_animation_library("", _motions(npc_id, folder))
	Outline.apply(n)
	return n


const UV_SHADER := preload("res://shaders/pokemon.gdshader")


static func _material_info(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if data is Dictionary else {}


## A material whose UVs need the game's transform or mirrored wrapping gets the UV shader.
static func _transformed(mat: StandardMaterial3D, info: Dictionary) -> Material:
	var m: Array = info.get("m", [1, 0, 0, 1, 0, 0])
	var plain: bool = m == [1, 0, 0, 1, 0, 0] and info.get("wrapU") == "Repeat" and info.get("wrapV") == "Repeat"
	if plain:
		var copy := mat.duplicate() as StandardMaterial3D
		TrainerModel._fix_transparency(copy)
		return copy
	var sm := ShaderMaterial.new()
	sm.shader = UV_SHADER
	if TrainerModel._has_alpha(mat.albedo_texture):
		sm.set_meta("cutout", true) # see-through parts (grass blades, fur tips): no outline hull
	sm.set_shader_parameter("albedo_tex", mat.albedo_texture)
	sm.set_shader_parameter("uv_m", Vector4(m[0], m[1], m[2], m[3]))
	sm.set_shader_parameter("uv_t", Vector2(m[4], m[5]))
	sm.set_shader_parameter("mirror_u", info.get("wrapU") == "Mirror")
	sm.set_shader_parameter("mirror_v", info.get("wrapV") == "Mirror")
	sm.set_shader_parameter("clamp_u", str(info.get("wrapU")).begins_with("Clamp"))
	sm.set_shader_parameter("clamp_v", str(info.get("wrapV")).begins_with("Clamp"))
	return sm


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

static func _motions(npc_id: String, folder: String) -> AnimationLibrary:
	if _libraries.has(folder):
		return _libraries[folder]
	var library := AnimationLibrary.new()
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
	_libraries[folder] = library
	return library
