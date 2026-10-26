class_name TrainerModel
extends Node3D
## An overworld trainer assembled at runtime from a look (see server/src/world/appearance.ts):
##   { gender: "f2", parts: { tops: { part: "f2_tops_jersey", color: "d01b02" }, ... } }
## The importer exports each gender as one skeleton (base.dae), one DAE per part sharing that
## skeleton, every color variant as a PNG, the motions, and manifest.json.

const FOLDER := "res://asset-cache/trainers/%s"
const MOTION_STAND := 0
const MOTION_WALK := 2
const MOTION_RUN := 3

## Used until a player has made their character, and as the creator's starting point.
const DEFAULT_LOOKS := {
	"f1": {"gender": "f1", "parts": {
		"face": {"part": "f1_face01"}, "hair": {"part": "f1_hair_long"},
		"hat": {"part": "f1_hat_hat", "color": "d01c01"}, "tops": {"part": "f1_tops_noslee", "color": "d01s01"},
		"btms": {"part": "f1_btms_tskirt", "color": "d01f01"}, "shoes": {"part": "f1_shoes_shoes_socks", "color": "d01f01"},
		"bag": {"part": "f1_bag01", "color": "d01b01"}}, "hairColor": 2},
	"f2": {"gender": "f2", "parts": {
		"face": {"part": "f2_face01"}, "hair": {"part": "f2_hair_short"},
		"hat": {"part": "f2_hat_hun", "color": "d01b01"}, "tops": {"part": "f2_tops_jersey", "color": "d01b01"},
		"btms": {"part": "f2_btms_skinny", "color": "d01b01"}, "shoes": {"part": "f2_shoes_sboots", "color": "d01b01"},
		"bag": {"part": "f2_bag01", "color": "d01b01"}}, "hairColor": 0},
}

## X/Y tints its grey hair textures; the look stores an index into this list. The server allows
## the same count (HAIR_COLORS in server/src/world/appearance.ts).
const HAIR_COLORS := [
	Color("4a3324"), Color("7b4b2a"), Color("d8b16a"), Color("23201f"), Color("a4522c"), Color("bdb4aa"),
]
## Skin tones, as multipliers on the pale skin painted into the textures (index 0 = as painted).
## The server allows the same count (SKIN_TONES).
const SKIN_TONES := [Color(1, 1, 1), Color(0.96, 0.86, 0.76), Color(0.8, 0.62, 0.48), Color(0.56, 0.4, 0.3)]
const SKIN_SHADER := preload("res://shaders/skin_tint.gdshader")

static var _manifests := {} # gender -> Dictionary
static var _motion_libraries := {} # gender -> AnimationLibrary
static var _motion_lists := {} # gender -> Array[int]

var player: AnimationPlayer
## Motion numbers present (the game's motion packs have empty slots, so there are gaps).
var motions: Array[int] = []
var look: Dictionary


## Returns null when that gender isn't in the asset cache yet.
static func from_look(new_look: Dictionary, load_motions := true) -> TrainerModel:
	var gender: String = new_look.get("gender", "f2")
	var folder := FOLDER % gender
	if not ResourceLoader.exists(folder.path_join("base.dae")):
		return null
	var t := TrainerModel.new()
	t.look = new_look
	var base := (load(folder.path_join("base.dae")) as PackedScene).instantiate()
	t.add_child(base)
	var skel := base.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skin := _skin_from_pose(skel)
	_attach_accessory_bones(skel)
	var manifest := get_manifest(gender)
	var tints := {
		"hair": HAIR_COLORS[clampi(int(new_look.get("hairColor", 0)), 0, HAIR_COLORS.size() - 1)],
		"skin": SKIN_TONES[clampi(int(new_look.get("skinTone", 0)), 0, SKIN_TONES.size() - 1)],
	}
	for choice: Dictionary in _all_parts(new_look, manifest):
		_attach_part(skel, skin, folder, choice, manifest, tints)
	t.player = AnimationPlayer.new()
	base.add_child(t.player)
	t.player.root_node = NodePath("..")
	if load_motions:
		t.player.add_animation_library("", _motion_library(gender))
		t.motions = _motion_lists[gender]
	Outline.apply(t)
	return t


## The same look on the full-size ("anime") model used in cutscenes (trainers/b1, trainers/b2): the
## game names the full-size clothing like the overworld one (f2_hat_cap → b2_hat_cap) with the same
## colors. Bottoms come in a version for boots and one for shoes; girls' legs are socks for boots or
## shoes. Returns {} when the full-size parts aren't imported.
static func full_look(look: Dictionary) -> Dictionary:
	var g: String = look.get("gender", "f2")
	var b := "b" + g.substr(1)
	var manifest := get_manifest(b)
	if manifest.is_empty():
		return {}
	var parts: Dictionary = look.get("parts", {})
	var shoes: String = parts.get("shoes", {}).get("part", "")
	var kind := "lboots" if shoes.contains("boots") else "shoes"
	var out := {}
	for cat: String in parts:
		var p: Dictionary = parts[cat]
		var name: String = b + str(p.get("part", "")).substr(2)
		if cat == "btms" and manifest.has(name + "_" + kind):
			name += "_" + kind
		elif cat == "socks":
			name = "%s_socks_%s" % [b, kind]
		if not manifest.has(name):
			continue
		var q := p.duplicate()
		q.part = name
		out[cat] = q
	if b == "b1" and not out.has("socks") and manifest.has("b1_socks_" + kind):
		out.socks = {"part": "b1_socks_" + kind, "color": "none"}
	var full := look.duplicate(true)
	full.gender = b
	full.parts = out
	return full


static func default_look(gender: String) -> Dictionary:
	return DEFAULT_LOOKS.get(gender, DEFAULT_LOOKS["f2"]).duplicate(true)


static func get_manifest(gender: String) -> Dictionary:
	if not _manifests.has(gender):
		var path := (FOLDER % gender).path_join("manifest.json")
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		var parts := {}
		if data is Dictionary:
			for p: Dictionary in data.get("parts", []):
				parts[p.name] = p
		_manifests[gender] = parts
	return _manifests[gender]


func play_motion(index: int, speed := 1.0) -> void:
	var anim := "mot%02d" % index
	if player.has_animation(anim):
		player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
		player.play(anim, 0.15, speed)


## The chosen parts plus the ones that follow from them: the Holo Caster bangle is always worn,
## boys' boots and shoes come with matching legs, and girls always have legs — the "socks" mesh,
## whose texture picks bare legs ("none"), socks, knee-highs or tights.
static func _all_parts(new_look: Dictionary, manifest: Dictionary) -> Array:
	var parts: Array = new_look.get("parts", {}).values()
	var gender: String = new_look.get("gender", "")
	for name: String in manifest:
		if manifest[name].category == "bangle":
			parts.append({"part": name, "color": _first_color(manifest[name])})
			break
	var shoes: String = new_look.get("parts", {}).get("shoes", {}).get("part", "")
	for kind in ["sboots", "shoes"]:
		var leg := "%s_leg_%s" % [gender, kind]
		if shoes.ends_with("_" + kind) and manifest.has(leg):
			parts.append({"part": leg, "color": _first_color(manifest[leg])})
	if not new_look.get("parts", {}).has("socks") and manifest.has("f1_socks_tights") and gender == "f1":
		parts.append({"part": "f1_socks_tights", "color": "none"})
	return parts


static func _first_color(entry: Dictionary) -> String:
	for m: Dictionary in entry.get("materials", []):
		if not m.variants.is_empty():
			return m.variants[0]
	return ""


## Moves a part's meshes onto the shared skeleton and swaps in the chosen color.
static func _attach_part(skel: Skeleton3D, skin: Skin, folder: String, choice: Dictionary, manifest: Dictionary, tints: Dictionary) -> void:
	var path := folder.path_join("%s.dae" % choice.get("part", ""))
	if not ResourceLoader.exists(path):
		push_warning("trainer part missing from the asset cache: " + path)
		return
	var scene := (load(path) as PackedScene).instantiate()
	var color: String = choice.get("color", "")
	var entry: Dictionary = manifest.get(choice.part, {})
	var pica := PicaMaterial.load_info(folder, "parts") # the game's toon materials, when imported
	for c in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		mi.owner = null # it belonged to the part's scene, which is freed below
		mi.get_parent().remove_child(mi)
		skel.add_child(mi)
		mi.skeleton = mi.get_path_to(skel)
		mi.skin = skin
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			mat = mat.duplicate() as StandardMaterial3D # each trainer gets its own colors
			var original := mat.albedo_texture.resource_path.get_file().get_basename() if mat.albedo_texture else ""
			_recolor(mat, entry, color, folder)
			_fix_transparency(mat)
			var mat_name := mat.resource_name.trim_suffix("_mat")
			var pm := _pica(pica, mat_name, mat, original, folder, tints)
			mi.set_surface_override_material(s, pm if pm else _tint(mat, folder, tints))
	scene.free()


## The game's own material for a part (toon shading from its lookup tables, see PicaMaterial), with
## the chosen color variant and the hair/skin tint. null when it can't be used: no material data, or
## clothing showing skin (the "_m" mask tint needs its own shader).
static func _pica(pica: Dictionary, mat_name: String, mat: StandardMaterial3D, original: String, folder: String, tints: Dictionary) -> Material:
	if not pica.has(mat_name) or mat.albedo_texture == null:
		return null
	var tex_name := mat.albedo_texture.resource_path.get_file().get_basename()
	var tint := Color.WHITE
	if tex_name.contains("_hair"):
		tint = tints.hair
	elif tex_name.contains("_face"):
		tint = tints.skin
	elif tints.skin != Color(1, 1, 1) and ResourceLoader.exists(folder.path_join(tex_name + "_m.png")):
		return null
	var pm := PicaMaterial.build(pica[mat_name], folder, {original: mat.albedo_texture})
	pm.set_shader_parameter("tint", tint)
	if pica[mat_name].get("alphaTest", {}).get("Enabled", false):
		pm.set_meta("cutout", true) # hair strands, lace: no outline hull
	return pm


## Hair textures are grey and take the hair color; faces take the skin tone; clothing with a "_m"
## skin mask gets the tone only where the mask says skin.
static func _tint(mat: StandardMaterial3D, folder: String, tints: Dictionary) -> Material:
	if mat.albedo_texture == null:
		return mat
	var tex_name := mat.albedo_texture.resource_path.get_file().get_basename()
	if tex_name.contains("_hair"):
		mat.albedo_color = tints.hair
		return mat
	var tone: Color = tints.skin
	if tex_name.contains("_face"):
		mat.albedo_color = tone
		return mat
	var mask_path := folder.path_join(tex_name + "_m.png")
	if tone == Color(1, 1, 1) or not ResourceLoader.exists(mask_path):
		return mat
	var shader := ShaderMaterial.new()
	shader.shader = SKIN_SHADER
	shader.set_shader_parameter("albedo_tex", mat.albedo_texture)
	shader.set_shader_parameter("mask_tex", load(mask_path))
	shader.set_shader_parameter("tone", tone)
	return shader


static func _recolor(mat: StandardMaterial3D, entry: Dictionary, color: String, folder: String) -> void:
	if color == "" or mat.albedo_texture == null:
		return
	var current := mat.albedo_texture.resource_path.get_file().get_basename()
	for m: Dictionary in entry.get("materials", []):
		if m.texture == current and color in m.variants:
			var tex_path := folder.path_join(m.stem + color + ".png")
			if ResourceLoader.exists(tex_path):
				mat.albedo_texture = load(tex_path)


static func _fix_transparency(mat: StandardMaterial3D) -> void:
	# Hair strands, lace edges and grass blades are cut out with the texture's alpha.
	if mat.albedo_texture and _has_alpha(mat.albedo_texture):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED


static var _alpha_cache := {}

## Whether a texture really uses its alpha channel. Texture2D.has_alpha() can say no for imported
## (compressed) textures that do, so look at the pixels once per texture.
static func _has_alpha(tex: Texture2D) -> bool:
	if tex.has_alpha():
		return true
	var key := tex.resource_path
	if not _alpha_cache.has(key):
		var img := tex.get_image()
		if img and img.is_compressed():
			img.decompress()
		_alpha_cache[key] = img != null and img.detect_alpha() != Image.ALPHA_NONE
	return _alpha_cache[key]


## Godot's DAE import keeps SPICA's bone weights but drops the skin binding. The meshes are modeled
## around the bones' starting pose (the DAE node transforms), so the skin is built from that pose,
## and the pose becomes the rest the motions play against.
static func _skin_from_pose(skel: Skeleton3D) -> Skin:
	var skin := Skin.new()
	for i in skel.get_bone_count():
		skin.add_named_bind(skel.get_bone_name(i), skel.get_bone_global_pose(i).affine_inverse())
	for i in skel.get_bone_count():
		skel.set_bone_rest(i, skel.get_bone_pose(i))
	return skin


## Hat accessories (the "point" parts: glasses, badge, wing) are weighted to the "acchat" bone,
## which the export leaves on the skeleton's root; the game pins it to the head at runtime, and no
## motion animates it. Left alone, the glasses stay put while the head bobs and they slide over the
## cap. Make it a child of Head, keeping its starting pose, so it moves with the head. The skin's
## binds are global, so they stay valid.
static func _attach_accessory_bones(skel: Skeleton3D) -> void:
	var head := skel.find_bone("Head")
	if head < 0:
		return
	var head_rest := skel.get_bone_global_rest(head)
	for i in skel.get_bone_count():
		if not skel.get_bone_name(i).begins_with("acc") or skel.get_bone_parent(i) == head:
			continue
		var local := head_rest.affine_inverse() * skel.get_bone_global_rest(i)
		skel.set_bone_parent(i, head)
		skel.set_bone_rest(i, local)
		skel.set_bone_pose(i, local)


static func _motion_library(gender: String) -> AnimationLibrary:
	if _motion_libraries.has(gender):
		return _motion_libraries[gender]
	var library := AnimationLibrary.new()
	var found: Array[int] = []
	var folder := FOLDER % gender
	var pattern := RegEx.create_from_string("^motion_mot(\\d+)\\.dae$")
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
				found.append(int(m.get_string(1)))
		scene.free()
	found.sort()
	_motion_libraries[gender] = library
	_motion_lists[gender] = found
	return library
