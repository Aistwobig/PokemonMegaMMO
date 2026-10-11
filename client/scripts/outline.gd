class_name Outline extends RefCounted
## Adds X/Y's black outline (shaders/outline.gdshader) to every opaque surface under a node:
## characters, NPCs and Pokémon. Cut-out surfaces (hair cards, grass) are left alone, since a hull
## around their quads would outline the invisible parts too.

const SHADER := preload("res://shaders/outline.gdshader")
static var _material: ShaderMaterial


static func apply(root: Node) -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat == null or _is_cutout(mat):
				continue
			mat = mat.duplicate()
			mat.next_pass = _material
			mi.set_surface_override_material(s, mat)


static func _is_cutout(mat: Material) -> bool:
	if mat.has_meta("cutout"):
		return true
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	return false
