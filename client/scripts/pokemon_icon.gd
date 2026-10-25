class_name PokemonIcon extends Control
## A Pokémon's menu icon, pixel-sharp and scaled up. `hop` makes it bounce like the selected
## Pokémon in X/Y's party screen; fainted Pokémon are greyed out.

var species := "":
	set(v):
		species = v
		texture = Ui.icon_texture(v) if v != "" else null
var texture: Texture2D:
	set(v):
		texture = v
		queue_redraw()
var hop := false:
	set(v):
		hop = v
		set_process(v)
		if not v:
			_offset = 0.0
			queue_redraw()
var fainted := false:
	set(v):
		fainted = v
		modulate = Color(0.45, 0.45, 0.5, 0.8) if v else Color.WHITE

var _t := 0.0
var _offset := 0.0


func _init(species_id := "", scale_factor := 2.0) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(40, 30) * scale_factor
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	species = species_id
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	# Two-frame hop, 4 times a second: up a few pixels, then back down.
	var target := -size.y * 0.08 if fmod(_t, 0.25) < 0.125 else 0.0
	if target != _offset:
		_offset = target
		queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	var tex_size := texture.get_size()
	var k := minf(size.x / tex_size.x, size.y / tex_size.y)
	var draw_size := tex_size * k
	draw_texture_rect(texture, Rect2((size - draw_size) / 2 + Vector2(0, _offset), draw_size), false)
