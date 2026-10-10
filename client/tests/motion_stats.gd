extends Node
## Dev tool: measures each motion's foot swing and loop length, to find idle/walk/run.
##   godot --headless --path client res://tests/motion_stats.tscn -- f1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var t := TrainerModel.from_look(TrainerModel.default_look(args[0] if args.size() > 0 else "f1"))
	add_child(t)
	var skel := t.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var lfoot := skel.find_bone("LFoot")
	var rfoot := skel.find_bone("RFoot")
	var rows: Array[String] = []
	for m in t.motions:
		var anim := "mot%02d" % m
		var length := t.player.get_animation(anim).length
		if length < 0.2:
			continue
		t.player.play(anim)
		var min_d := INF
		var max_d := -INF
		var min_h := INF
		var max_h := -INF
		for s in 12:
			t.player.seek(length * s / 12.0, true)
			var l := skel.get_bone_global_pose(lfoot).origin
			var r := skel.get_bone_global_pose(rfoot).origin
			var d := l.z - r.z # one foot ahead of the other
			min_d = minf(min_d, d)
			max_d = maxf(max_d, d)
			min_h = minf(min_h, minf(l.y, r.y))
			max_h = maxf(max_h, maxf(l.y, r.y))
		rows.append("mot%02d  len=%.2fs  stride=%5.1f  lift=%5.1f" % [m, length, max_d - min_d, max_h - min_h])
	print("\n".join(rows))
	get_tree().quit()
