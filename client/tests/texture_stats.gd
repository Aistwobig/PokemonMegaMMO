extends SceneTree
## Dev tool: the dominant skin color of each face texture (most common bright, warm pixel color).
##   godot --headless --path client -s res://tests/texture_stats.gd


func _init() -> void:
	for g in ["f1", "f2"]:
		for f in ["face00_off", "face01_on", "face02_on"]:
			var img := Image.load_from_file(ProjectSettings.globalize_path("res://asset-cache/trainers/%s/%s_%s.png" % [g, g, f]))
			if img == null:
				print(g, f, " missing")
				continue
			var counts := {}
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					if c.a < 0.9 or c.r < c.b: # skip transparent and cool colors (eyes, outlines)
						continue
					var key := Color(snappedf(c.r, 0.05), snappedf(c.g, 0.05), snappedf(c.b, 0.05))
					counts[key] = counts.get(key, 0) + 1
			var best: Color
			var best_n := 0
			for k: Color in counts:
				if counts[k] > best_n:
					best = k
					best_n = counts[k]
			print("%s_%s skin ≈ %s (%s)" % [g, f, best, best.to_html(false)])
	quit()
