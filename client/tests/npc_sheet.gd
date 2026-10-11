extends Node3D
## Dev tool: every exported NPC in a grid with its id, to find who is who.
##   godot --path client res://tests/npc_sheet.tscn [-- tr0003 tr0004 ...]

const COLS := 9


func _ready() -> void:
	var ids := Array(OS.get_cmdline_user_args())
	var pokemon := OS.get_environment("POKEMON") != "" # POKEMON=1: the Pokémon folder instead
	var root := "res://asset-cache/pokemon" if pokemon else "res://asset-cache/npc"
	if ids.is_empty():
		for d in DirAccess.get_directories_at(root):
			ids.append(d)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	add_child(env)
	var rows := ceili(ids.size() / float(COLS))
	for i in ids.size():
		var n := NpcModel.create(ids[i], NpcModel.POKEMON if pokemon else NpcModel.FOLDER)
		if n == null:
			continue
		var pos := Vector3((i % COLS - (COLS - 1) / 2.0) * 60.0, -(i / COLS) * 120.0, 0)
		n.position = pos
		add_child(n)
		n.play_motion(int(OS.get_environment("MOTION")) if OS.get_environment("MOTION") != "" else 0)
		var label := Label3D.new()
		label.text = ids[i]
		label.position = pos + Vector3(0, -12, 0)
		label.font_size = 64
		label.pixel_size = 0.15
		add_child(label)
	var cam := Camera3D.new()
	add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = max(rows * 120.0, COLS * 60.0 * 9.0 / 16.0) + 20
	cam.position = Vector3(0, 50 - (rows - 1) * 60.0, 500)
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("SHEET_OUT")
	if out != "":
		img.save_png(out)
		get_tree().quit()
