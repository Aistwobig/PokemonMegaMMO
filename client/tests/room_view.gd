extends Node3D
## Dev tool: a map chunk seen from above with its tile grid drawn over it (red = blocked,
## yellow = special tile), to line up the 3D model with the collision data.
##   godot --path client res://tests/room_view.tscn -- t01r01/bedroom_f1 [x0 y0 x1 y1]

const TILE := 18.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map: String = args[0] if args.size() > 0 else "t01r01/bedroom_f1"
	var rect := Rect2i(0, 0, 40, 40)
	if args.size() >= 5:
		rect = Rect2i(int(args[1]), int(args[2]), int(args[3]) - int(args[1]) + 1, int(args[4]) - int(args[2]) + 1)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.1, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	add_child(env)
	var base := map if map.begins_with("res://") else "res://asset-cache/maps/" + map
	add_child(RoomMap.load_model(base + ".dae"))

	var grid := RoomMap.load_tiles(base + ".tiles.json")
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var t: int = grid.tiles[y * grid.width + x]
			if t == RoomMap.FLOOR:
				continue
			var quad := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(TILE - 2, TILE - 2)
			quad.mesh = plane
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.no_depth_test = true
			mat.albedo_color = Color(1, 0, 0, 0.25) if t == RoomMap.BLOCKED else Color(1, 1, 0, 0.6)
			quad.material_override = mat
			quad.position = RoomMap.tile_center(x, y, 200)
			add_child(quad)
			if t != RoomMap.BLOCKED:
				var l := Label3D.new()
				l.text = "%02X" % (t >> 24)
				l.pixel_size = 0.1
				l.font_size = 64
				l.no_depth_test = true
				l.rotation_degrees.x = -90
				l.position = quad.position + Vector3(0, 1, 0)
				add_child(l)
	var cam := Camera3D.new()
	add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = max(rect.size.y, rect.size.x * 9.0 / 16.0) * TILE
	var center := Vector3((rect.position.x + rect.size.x / 2.0) * TILE - RoomMap.HALF, 1000, (rect.position.y + rect.size.y / 2.0) * TILE - RoomMap.HALF)
	cam.look_at_from_position(center, center - Vector3(0, 1000, 0), Vector3(0, 0, -1))
	await get_tree().create_timer(0.5).timeout
	var out := OS.get_environment("SHEET_OUT")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()
