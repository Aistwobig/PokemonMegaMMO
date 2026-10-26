class_name LipSync extends Node
## Makes a character's mouth move while their lines type out in the dialogue box (DialogueBox
## turns `talking` on and off). Two kinds of X/Y character:
##  - full-size (cutscene) models have lip bones: the lower lip (FJlipL) drops to open the mouth;
##  - chibi overworld models have no mouth bones; their face texture is a 4 × 2 sheet of whole-face
##    expressions, and the cell below-right of the neutral face is the same face with the mouth open,
##    so the face material flips between the two.
## Mouth shapes change at a syllable-like rhythm, never quite regular.
##   var lips := LipSync.attach(model)   # null when the model has neither

const OPEN_LIP := Vector3(-2.2, 0, 0) # FJlipL offset for a wide-open mouth (bone space)
## Neutral cell → talking cell (3DS UV space, v up): on a 4 × 2 sheet the open mouth is one row down
## and two across; on a 4 × 1 strip (Mom) it's two across. Only the mouth part of the face (its lower
## part) is swapped, so the eyes stay open.
const SHEET_OPEN := Vector2(0.5, -0.5)
const STRIP_OPEN := Vector2(0.5, 0.0)
const MOUTH_FROM := 0.55 # of the face's height, from the top
const SYLLABLES_PER_SEC := 7.0

var talking := false
var _open := 0.0 # 0 closed .. 1 open, eased
var _target := 0.0
var _next_change := 0.0
var _modifier: LipModifier
var _faces: Array[ShaderMaterial] = []
var _open_shift := SHEET_OPEN


class LipModifier extends SkeletonModifier3D:
	var amount := 0.0
	var bone := -1

	func _process_modification() -> void:
		if bone < 0 or amount <= 0.001:
			return
		var sk := get_skeleton()
		sk.set_bone_pose_position(bone, sk.get_bone_pose_position(bone) + OPEN_LIP * amount)


static func attach(model: Node3D) -> LipSync:
	if model == null:
		return null
	var lips := LipSync.new()
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var sk := skels[0] as Skeleton3D
		var b := sk.find_bone("FJlipL")
		if b >= 0:
			lips._modifier = LipModifier.new()
			lips._modifier.bone = b
			sk.add_child(lips._modifier)
	if lips._modifier == null:
		for c in model.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(s)
				var src := mi.mesh.surface_get_material(s)
				if m is ShaderMaterial and src and src.resource_name.to_lower().contains("face"):
					m = m.duplicate() # this character's own copy
					mi.set_surface_override_material(s, m)
					var uvs: PackedVector2Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]
					var lo := 9.0
					var hi := -9.0
					for u in uvs:
						lo = minf(lo, u.y)
						hi = maxf(hi, u.y)
					m.set_shader_parameter("mouth_split", lerpf(lo, hi, MOUTH_FROM))
					if hi - lo > 0.6: # the face fills the texture's height: a one-row strip
						lips._open_shift = STRIP_OPEN
					lips._faces.append(m)
	if lips._modifier == null and lips._faces.is_empty():
		return null
	model.add_child(lips)
	return lips


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if talking:
		if now >= _next_change:
			_target = 0.0 if _target > 0.5 else randf_range(0.6, 1.0)
			_next_change = now + randf_range(0.6, 1.4) / SYLLABLES_PER_SEC
	else:
		_target = 0.0
	_open = move_toward(_open, _target, delta * 14.0)
	if _modifier:
		_modifier.amount = _open
	for f in _faces:
		f.set_shader_parameter("uv_shift", _open_shift if _open > 0.45 else Vector2.ZERO)
