extends Node
## Background music and jingles (autoload "Music"), from the player's own soundtrack: the importer
## converts romfs/sound/*.aac to asset-cache/music/<name>.mp3.
##   Music.play_map("route2")    the map's theme (fades over from whatever is playing)
##   Music.play("bgm_xy_vs_norapoke")
##   await Music.jingle("me_xy_kaifuku")   plays once over a paused theme, which then carries on
## Volume is saved in user://settings.cfg (Settings menu).

const DIR := "res://asset-cache/music/"
const SETTINGS_PATH := "user://settings.cfg"

## Each zone's music number (zone table, a/0/1/2 entry 360, u16 @0x08) is an index into a table in
## code.bin (0x44eacc) of sound IDs in xy_sound.bcsar: 5 = T_01, 6 = T_02, 11 = R_A, 12 = R_B.
const MAP_THEMES := {
	"vaniville": "bgm_xy_t_01",
	"route1": "bgm_xy_r_a",
	"aquacorde": "bgm_xy_t_02",
	"route2": "bgm_xy_r_b",
}
const TITLE := "bgm_xy_title_01"
const INTRO := "bgm_xy_starting"
const WILD_BATTLE := "bgm_xy_vs_norapoke"
const TRAINER_BATTLE := "bgm_xy_vs_trainer"
const WILD_WIN := "bgm_xy_win1"
const TRAINER_WIN := "bgm_xy_win2"
const HEAL := "me_xy_kaifuku"
const LEVEL_UP := "me_xy_lvup"

var volume := 0.6: # 0..1
	set(v):
		volume = clampf(v, 0.0, 1.0)
		_apply_volume()
var current := "" # the track playing (or fading in)

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _jingle: AudioStreamPlayer
var _streams := {} # name -> AudioStream
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_jingle = AudioStreamPlayer.new()
	add_child(_jingle)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = cfg.get_value("audio", "music", volume)
	_apply_volume()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music", volume)
	cfg.save(SETTINGS_PATH)


func play_map(map_id: String) -> void:
	play(MAP_THEMES.get(map_id, current))


## Fades the current track out and `track` in. Playing the same track again does nothing.
func play(track: String, fade := 0.8) -> void:
	if track == current or track == "":
		return
	var stream := _load(track, true)
	current = track
	var old := _players[_active]
	_active = 1 - _active
	var new := _players[_active]
	if _fade:
		_fade.kill()
	_fade = create_tween().set_parallel()
	_fade.tween_property(old, "volume_db", -80.0, fade)
	_fade.chain().tween_callback(old.stop)
	if stream == null:
		return # not imported (older asset cache): silence rather than an error
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	_fade.parallel().tween_property(new, "volume_db", _db(), fade * 0.6)


func stop(fade := 0.8) -> void:
	current = ""
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_players[_active], "volume_db", -80.0, fade)
	_fade.tween_callback(_players[_active].stop)


## Plays a short tune once while the theme waits, as X/Y does after healing or a level up.
func jingle(track: String) -> void:
	var stream := _load(track, false)
	if stream == null:
		return
	var theme := _players[_active]
	theme.stream_paused = true
	_jingle.stream = stream
	_jingle.volume_db = _db()
	_jingle.play()
	await _jingle.finished
	theme.stream_paused = false


func has_track(track: String) -> bool:
	return FileAccess.file_exists(DIR + track + ".mp3")


func _load(track: String, loop: bool) -> AudioStream:
	if _streams.has(track):
		return _streams[track]
	var path := DIR + track + ".mp3"
	var stream: AudioStreamMP3
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStreamMP3
	elif FileAccess.file_exists(path):
		# Not imported by the editor yet: read the file as it is.
		stream = AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes(path)
	if stream == null:
		return null
	stream.loop = loop
	_streams[track] = stream
	return stream


func _db() -> float:
	return linear_to_db(maxf(volume, 0.0001))


func _apply_volume() -> void:
	if _players.is_empty():
		return
	if not (_fade and _fade.is_running()):
		_players[_active].volume_db = _db()
	_jingle.volume_db = _db()
