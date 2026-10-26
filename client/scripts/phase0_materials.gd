extends Node3D
## Map materials. Chunks exported with the game's material data (<chunk>.pica.json, importer
## Pica.cs) get the game's own 3DS materials (PicaMaterial): the baked vertex-color shading, the
## lighting, blending and alpha tests, so towns look like X/Y instead of flat textures.
## Older asset caches fall back to fixing what the DAE import gets wrong:
## - Textures with an alpha channel get alpha scissor (leaves) or blending (soft edges).
## - Blob shadows (kokage*, *_s) only use the texture's alpha, so their color becomes black.

func _ready() -> void:
	for chunk in get_children():
		var path := chunk.scene_file_path
		var info := PicaMaterial.load_info(path.get_base_dir(), path.get_file().get_basename()) if path != "" else {}
		for mesh in chunk.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i) as StandardMaterial3D
				if mat == null:
					continue
				var mat_name := mat.resource_name.trim_suffix("_mat")
				if info.has(mat_name):
					var own := {}
					if mat.albedo_texture:
						own[mat.albedo_texture.resource_path.get_file().get_basename()] = mat.albedo_texture
					mi.set_surface_override_material(i, PicaMaterial.build(info[mat_name], path.get_base_dir(), own))
				else:
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
