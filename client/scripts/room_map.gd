class_name RoomMap extends RefCounted
## Loading helpers for map chunks exported from the RomFS: the 3D model (with the material fixes
## the DAE import needs) and the tile grid (`importer/tools/tiles.py json`).

const BLOCKED := 0x01000021
const FLOOR := 0x00000020
const TILE := 18.0 # a 720-unit chunk is 40 x 40 tiles
const HALF := 360.0 # chunk models are centered: tile (0, 0) starts at model (-360, -360)


static func load_model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if String(mi.name).begins_with("black"):
			mi.material_override = _black() # wall tops and the void around rooms are plain black
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat:
				_fix(mat)
	return model


## {width, height, tiles: Array of u32}; tile (x, y) covers model x in [18x - 360, 18x - 342), same for z.
static func load_tiles(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (data is Dictionary):
		return {"width": 0, "height": 0, "tiles": []}
	var tiles: Array = data.tiles.map(func(t: float) -> int: return int(t))
	return {"width": int(data.width), "height": int(data.height), "tiles": tiles}


static func tile_at(grid: Dictionary, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= grid.width or y >= grid.height:
		return BLOCKED
	return grid.tiles[y * grid.width + x]


static func tile_center(x: int, y: int, height := 0.0) -> Vector3:
	return Vector3((x + 0.5) * TILE - HALF, height, (y + 0.5) * TILE - HALF)


static func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x + HALF) / TILE), floori((p.z + HALF) / TILE))


static var _black_mat: StandardMaterial3D

static func _black() -> StandardMaterial3D:
	if _black_mat == null:
		_black_mat = StandardMaterial3D.new()
		_black_mat.albedo_color = Color.BLACK
		_black_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _black_mat


## Same fixes as the Phase 0 town: alpha cut-outs, soft edges, and blob shadows.
static func _fix(mat: StandardMaterial3D) -> void:
	var tex := mat.albedo_texture
	if tex == null:
		return
	var tex_name := tex.resource_path.get_file().get_basename()
	var is_shadow := tex_name.begins_with("kokage") or tex_name.ends_with("_s") or tex_name.contains("kage")
	var img := tex.get_image()
	if img and img.is_compressed():
		img.decompress()
	var alpha := img.detect_alpha() if img else Image.ALPHA_NONE
	if is_shadow:
		mat.albedo_color = Color(0, 0, 0, 0.5)
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
