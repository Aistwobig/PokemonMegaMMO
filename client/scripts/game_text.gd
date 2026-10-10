class_name GameText extends RefCounted
## Dialogue from the player's RomFS, exported by `importer/tools/text.py json` to
## asset-cache/text/game/<n>.json (a/0/7/4) and asset-cache/text/story/<n>.json (a/0/8/2).
## Lines keep the game's codes: \c = next box, \r = scroll to the next box, [VAR ...] = variables.

const FOLDER := "res://asset-cache/text/%s/%d.json"
## Text files used by the intro.
const INTRO := ["game", 100] # Professor Sycamore's welcome
const HOME := ["story", 55] # the player's house (Mom)
const NEIGHBORS := ["story", 57] # Serena/Calem and Shauna outside

static var _cache := {}
static var _var := RegEx.create_from_string("\\[VAR ([0-9A-F]{4})(?:\\(([0-9A-F,]*)\\))?\\]")


## One raw line, or "" when the text isn't in the asset cache.
static func line(file: Array, index: int) -> String:
	var key := FOLDER % [file[0], file[1]]
	if not _cache.has(key):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(key)) if FileAccess.file_exists(key) else null
		_cache[key] = data if data is Array else []
	var lines: Array = _cache[key]
	return lines[index] if index >= 0 and index < lines.size() else ""


## A line ready to show, split into boxes (pages).
static func pages(file: Array, index: int, player_name: String, gender: String) -> PackedStringArray:
	return format(line(file, index), player_name, gender)


## Fills in variables and splits a line into boxes.
##   [VAR 0100(...)]  the player's name
##   [VAR 1100(00FF,LLHH)]  boy/girl text: the next LL characters are the boy's version, then HH
##                          characters for the girl's ("h" + "is"/"er" → "his"/"her")
static func format(text: String, player_name: String, gender: String) -> PackedStringArray:
	var out := ""
	var pos := 0
	while true:
		var m := _var.search(text, pos)
		if m == null:
			out += text.substr(pos)
			break
		out += text.substr(pos, m.get_start() - pos)
		pos = m.get_end()
		var args := m.get_string(2).split(",", false)
		match m.get_string(1):
			"0100":
				out += player_name
			"1100":
				var lens := args[1].hex_to_int() if args.size() > 1 else 0
				var boy_len := lens & 0xFF
				var girl_len := lens >> 8
				var boy := text.substr(pos, boy_len)
				var girl := text.substr(pos + boy_len, girl_len)
				out += girl if gender == "f1" else boy
				pos += boy_len + girl_len
			_:
				pass # colors, waits and the rest only change how the text is drawn
	var boxes := PackedStringArray()
	for box in out.replace("\\r", "\\c").split("\\c"):
		box = box.strip_edges()
		if box != "":
			boxes.append(box)
	return boxes
