class_name BlobShadow
## The soft round shadow X/Y draws under characters and Pokémon, projected onto the ground below
## (a Decal, so it follows slopes and steps). Add it as a child of the character.

static var _texture: Texture2D


## Puts a shadow under `character`. Its meshes move to render layer 2, so the shadow (which only
## lands on layer 1: the ground) doesn't darken the character's own feet.
static func attach(character: Node3D, radius := 11.0, strength := 0.55) -> Decal:
	for c in character.find_children("*", "VisualInstance3D", true, false):
		(c as VisualInstance3D).layers = 2
	var d := create(radius, strength)
	character.add_child(d)
	return d


static func create(radius := 11.0, strength := 0.55) -> Decal:
	if _texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.55, Color(0, 0, 0, 0.85))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_texture = t
	var d := Decal.new()
	d.texture_albedo = _texture
	d.size = Vector3(radius * 2.0, 30.0, radius * 2.0)
	d.position.y = 6.0
	d.modulate = Color(1, 1, 1, strength)
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.cull_mask = 1
	return d
