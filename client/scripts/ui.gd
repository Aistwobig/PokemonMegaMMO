class_name Ui
## The game's UI look, shared by the HUD, menus and battles: dark translucent panels with a thin
## light edge (PokeMMO-like), small title bars, HP bars that go green → yellow → red, and the
## Pokémon menu icons from the player's own game (asset-cache/icons, made by the importer).

const ICONS := "res://asset-cache/icons/%s.png"
const BG := Color(0.09, 0.11, 0.15, 0.92)
const BG_LIGHT := Color(0.15, 0.18, 0.24, 0.95)
const EDGE := Color(1, 1, 1, 0.14)
const ACCENT := Color(0.35, 0.62, 0.95)
const TEXT := Color(0.93, 0.94, 0.96)
const TEXT_DIM := Color(0.62, 0.66, 0.74)
const GOLD := Color(1.0, 0.82, 0.35)
const HP_GREEN := Color(0.33, 0.85, 0.42)
const HP_YELLOW := Color(0.98, 0.78, 0.2)
const HP_RED := Color(0.93, 0.27, 0.22)
const EXP_BLUE := Color(0.3, 0.7, 1.0)
const TYPE_COLORS := {
	"Normal": Color("a8a77a"), "Fire": Color("ee8130"), "Water": Color("6390f0"), "Electric": Color("f7d02c"),
	"Grass": Color("7ac74c"), "Ice": Color("96d9d6"), "Fighting": Color("c22e28"), "Poison": Color("a33ea1"),
	"Ground": Color("e2bf65"), "Flying": Color("a98ff3"), "Psychic": Color("f95587"), "Bug": Color("a6b91a"),
	"Rock": Color("b6a136"), "Ghost": Color("735797"), "Dragon": Color("6f35fc"), "Dark": Color("705746"),
	"Steel": Color("b7b7ce"), "Fairy": Color("d685ad"),
}
const STATUS_COLORS := {
	"brn": Color("ee8130"), "par": Color("d8b81c"), "psn": Color("a33ea1"), "tox": Color("7a2a78"),
	"slp": Color("8c8c9c"), "frz": Color("6cc6d8"), "fnt": Color("c0392b"),
}

static var _icons := {}


static func panel_style(bg := BG, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = EDGE
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(10)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	return s


static func panel(bg := BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg))
	return p


static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A flat button in the panel style; `color` tints it (type colors for moves, etc.).
static func button(text: String, action: Callable, color := Color(0.22, 0.26, 0.34), size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = {"normal": color, "hover": color.lightened(0.15), "pressed": color.darkened(0.2),
			"disabled": color.darkened(0.55)}[state]
		s.border_color = Color(1, 1, 1, 0.3 if state == "hover" else 0.14)
		s.set_border_width_all(1)
		s.set_corner_radius_all(5)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, s)
	if action.is_valid():
		b.pressed.connect(action)
	return b


## A window: title bar with a close button, then `content` (a VBoxContainer) under it.
## Returns {root, content, close}. Put `root` in a CanvasLayer and place it.
static func window(title: String, on_close: Callable) -> Dictionary:
	var root := PanelContainer.new()
	var style := panel_style()
	style.set_content_margin_all(0)
	root.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)
	var bar := PanelContainer.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = BG_LIGHT
	bar_style.corner_radius_top_left = 6
	bar_style.corner_radius_top_right = 6
	bar_style.content_margin_left = 12
	bar_style.content_margin_right = 6
	bar_style.content_margin_top = 4
	bar_style.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", bar_style)
	col.add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var t := label(title, 16, TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var close := button("✕", on_close, Color(0.6, 0.2, 0.2, 0.0), 14)
	row.add_child(close)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	return {"root": root, "content": content, "close": close, "title": t}


## The menu icon of a Pokémon (40×30), or null when the asset cache has none.
static func icon_texture(species: String) -> Texture2D:
	if _icons.has(species):
		return _icons[species]
	var path := ICONS % species
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img:
			tex = ImageTexture.create_from_image(img)
	_icons[species] = tex
	return tex


static func hp_color(ratio: float) -> Color:
	return HP_GREEN if ratio > 0.5 else HP_YELLOW if ratio > 0.2 else HP_RED


## A small rounded badge (types, status conditions).
static func badge(text: String, color: Color, size := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(4)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	var l := label(text, size, Color.WHITE)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


static func status_badge(status: Variant, hp: int) -> Control:
	var s := "fnt" if hp <= 0 else str(status) if status else ""
	if s == "" or s == "<null>":
		return null
	return badge(s.to_upper(), STATUS_COLORS.get(s, Color(0.4, 0.4, 0.45)), 11)


static func gender_symbol(g: Variant) -> String:
	return {"M": "♂", "F": "♀"}.get(str(g), "")


static func gender_color(g: Variant) -> Color:
	return Color(0.45, 0.7, 1.0) if str(g) == "M" else Color(1.0, 0.5, 0.65)


static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "₽" + s + out
