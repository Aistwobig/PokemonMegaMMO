class_name CutsceneCamera extends Camera3D
## Plays one of X/Y's cutscene cameras exactly as the game does: position, aim, roll and field of
## view on every frame (30 fps), from <name>.camera.json written by the importer (BchTool camera,
## from the scene's CGFX file). The game's three camera kinds:
##   Aim     look from pos at target, rolled by twist
##   LookAt  look from pos at target with the given up vector
##   Rotate  pos plus Euler angles (X, then Y, then Z)
##   await cam.play("res://asset-cache/cutscenes/hakase/cam440.camera.json")

signal finished

const FPS := 30.0

var data := {}
var frame := 0.0
var playing := false
var speed := 1.0
var offset := Transform3D.IDENTITY # where the cutscene's origin sits in our world


static func load_file(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return d if d is Dictionary else {}


## Starts a camera; resolves when its last frame has played (cameras hold their last frame after).
func play(path: String, from_frame := 0.0) -> void:
	data = load_file(path)
	if data.is_empty():
		return
	frame = from_frame
	_end = -1.0
	playing = true
	make_current()
	_apply(frame)
	await finished


## Plays only frames `from`–`to` of the camera in `path` (a scene uses parts of one long camera).
func play_range(path: String, from: float, to: float) -> void:
	if data.is_empty() or data.get("_path", "") != path:
		data = load_file(path)
		data["_path"] = path
	if data.is_empty():
		return
	frame = from
	_end = to
	playing = true
	make_current()
	_apply(frame)
	await finished


var _end := -1.0


func length() -> float:
	return float(data.get("frames", 0)) / FPS


func _process(delta: float) -> void:
	if not playing:
		return
	frame += delta * FPS * speed
	var last := float(data.get("frames", 0)) if _end < 0 else minf(_end, float(data.get("frames", 0)))
	if frame >= last:
		frame = last
		playing = false
		_apply(frame)
		finished.emit()
		return
	_apply(frame)


func _apply(f: float) -> void:
	var pos := _vec("pos", f)
	match str(data.get("view", "")):
		"Aim":
			var target := _vec("target", f)
			var t := Transform3D.IDENTITY.looking_at(target - pos, Vector3.UP)
			t = t.rotated_local(Vector3.FORWARD, _num("twist", f))
			t.origin = pos
			global_transform = offset * t
		"LookAt":
			var target := _vec("target", f)
			var up := _vec("up", f)
			global_transform = offset * Transform3D(Basis.looking_at(target - pos, up if up.length() > 0.01 else Vector3.UP), pos)
		_:
			var r := _vec("rot", f)
			# The 3DS stores the view rotation (world → camera), with its view looking down +Z: turn it
			# half way round, then invert (checked: the intro's first frame is Sycamore's face).
			var b := Basis.from_euler(Vector3(r.x, r.y + PI, r.z), EULER_ORDER_ZYX).inverse()
			global_transform = offset * Transform3D(b, pos)
	fov = rad_to_deg(_num("fovy", f))


func _vec(key: String, f: float) -> Vector3:
	var arr: Array = data.get(key, [])
	if arr.is_empty():
		return Vector3.ZERO
	var i := clampi(int(f), 0, arr.size() - 1)
	var j := mini(i + 1, arr.size() - 1)
	var a: Array = arr[i]
	var b: Array = arr[j]
	return Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), f - floorf(f))


func _num(key: String, f: float) -> float:
	var arr: Array = data.get(key, [])
	if arr.is_empty():
		return 0.0
	var i := clampi(int(f), 0, arr.size() - 1)
	var j := mini(i + 1, arr.size() - 1)
	return lerpf(float(arr[i]), float(arr[j]), f - floorf(f))
