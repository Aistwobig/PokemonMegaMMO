extends Node3D
## Dev tool: a trainer playing several motions side by side, seen from the side.
##   godot --path client res://tests/trainer_check.tscn -- serena 25 2 3


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var trainer := args[0] if args.size() > 0 else "serena"
	var motions := Array(args.slice(1)).map(func(a: String) -> int: return int(a))
	if motions.is_empty():
		motions = [25, 2, 3]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	add_child(env)

	for i in motions.size():
		var t := TrainerModel.create(trainer)
		t.position.x = (i - (motions.size() - 1) / 2.0) * 70.0
		t.rotation_degrees.y = 90 # walking to the right, seen from the side
		add_child(t)
		t.play_motion(motions[i])
		var label := Label3D.new()
		label.text = "mot%02d" % motions[i]
		label.position = Vector3(t.position.x, 95, 0)
		label.font_size = 64
		add_child(label)

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.look_at_from_position(Vector3(0, 45, 300), Vector3(0, 45, 0))
