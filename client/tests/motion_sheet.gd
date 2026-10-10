extends Control
## Dev tool: a grid of one trainer showing motions side by side, frozen at 30%, to find
## which motion is idle/walk/run. Pass the first motion index after "--":
##   godot --path client res://tests/motion_sheet.tscn -- 0

const COLS := 8
const ROWS := 4


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 0
	var trainer := args[1] if args.size() > 1 else "serena"
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grid)
	var source := TrainerModel.create(trainer)
	for i in source.motions.slice(first, first + COLS * ROWS):
		grid.add_child(_cell(trainer, source, i))
	source.free()


func _cell(trainer: String, source: TrainerModel, index: int) -> Control:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(1280.0 / COLS, 720.0 / ROWS)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	box.add_child(vp)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	vp.add_child(env)

	var t := TrainerModel.create(trainer, false)
	t.player.add_animation_library("", source.player.get_animation_library(""))
	vp.add_child(t)
	var anim := "mot%02d" % index
	var length := t.player.get_animation(anim).length
	t.ready.connect(func() -> void:
		t.player.play(anim)
		t.player.seek(length * 0.3, true)
		t.player.speed_scale = 0.0)

	var cam := Camera3D.new()
	cam.fov = 40
	cam.look_at_from_position(Vector3(120, 70, 150), Vector3(0, 38, 0)) # three-quarter view shows legs
	vp.add_child(cam)

	var label := Label.new()
	label.text = "%d  (%.1fs)" % [index, length]
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	box.add_child(label)
	return box
