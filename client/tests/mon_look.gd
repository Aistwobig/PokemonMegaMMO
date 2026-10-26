extends Node3D
## Pokémon side by side, front view, battle idle: to compare looks. SHOT=<png>, MONS=a,b,c
func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	add_child(env)
	var mons := OS.get_environment("MONS").split(",") if OS.get_environment("MONS") != "" else PackedStringArray(["chespin", "fennekin", "froakie"])
	for i in mons.size():
		var n := NpcModel.create(mons[i], NpcModel.POKEMON)
		if n == null: continue
		add_child(n)
		var box := AABB(); var first := true
		for c in n.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (c as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b); first = false
		n.scale = Vector3.ONE * (40.0 / maxf(box.size.y, 1.0))
		n.position.x = (i - (mons.size() - 1) / 2.0) * 50.0
		n.play_motion(0)
	var cam := Camera3D.new(); add_child(cam); cam.fov = 30
	cam.look_at_from_position(Vector3(0, 30, 50.0 * mons.size() + 40), Vector3(0, 20, 0))
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT"))
	get_tree().quit()
