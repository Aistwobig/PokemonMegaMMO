extends Node3D
## Phase 0: fix materials the DAE import gets wrong.
## - Textures with an alpha channel get alpha scissor (leaves) or blending (soft edges).
## - Blob shadows (kokage*, *_s) only use the texture's alpha, so their color becomes black.

func _ready() -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat:
				_fix(mat)

func _fix(mat: StandardMaterial3D) -> void:
	var tex := mat.albedo_texture
	if tex == null:
		return
	var tex_name := tex.resource_path.get_file().get_basename()
	var is_shadow := tex_name.begins_with("kokage") or tex_name.ends_with("_s")
	var img := tex.get_image()
	if img and img.is_compressed():
		img.decompress()
	var alpha := img.detect_alpha() if img else Image.ALPHA_NONE
	if is_shadow:
		mat.albedo_color = Color(0, 0, 0, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.render_priority = 1
	elif alpha == Image.ALPHA_BIT:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif alpha == Image.ALPHA_BLEND:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
