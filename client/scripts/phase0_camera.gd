extends Camera3D
## Phase 0 viewer: X/Y-style overworld camera orbiting a target.
## Right-drag to orbit, mouse wheel to zoom, WASD to move the target.

@export var target := Vector3.ZERO
@export var distance := 1400.0
@export var pitch_deg := 40.0
@export var yaw_deg := 0.0
@export var move_speed := 400.0
## Degrees per second of automatic orbit (the login screen background uses this).
@export var auto_orbit := 0.0

func _ready() -> void:
	_update()

func _process(delta: float) -> void:
	if auto_orbit != 0.0:
		yaw_deg += auto_orbit * delta
		_update()
	var dir := Vector3(
		Input.get_axis(&"ui_left", &"ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0.0,
		Input.get_axis(&"ui_up", &"ui_down") + float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if dir != Vector3.ZERO:
		target += dir.normalized().rotated(Vector3.UP, deg_to_rad(yaw_deg)) * move_speed * delta
		_update()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		yaw_deg -= event.relative.x * 0.3
		pitch_deg = clampf(pitch_deg + event.relative.y * 0.3, 5.0, 85.0)
		_update()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance * 0.9, 100.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance * 1.1, 10000.0)
		_update()

func _update() -> void:
	var offset := Vector3(0, 0, distance).rotated(Vector3.RIGHT, -deg_to_rad(pitch_deg)).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	global_position = target + offset
	look_at(target)
