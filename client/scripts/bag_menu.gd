class_name BagMenu extends CanvasLayer
## The bag (B): your items and money. Items are only used in battle for now (Poké Balls).

signal closed

const ITEM_INFO := {
	"pokeball": ["Poké Ball", "A device for catching wild Pokémon."],
	"greatball": ["Great Ball", "A good, high-performance Poké Ball."],
	"ultraball": ["Ultra Ball", "An ultra-high-performance Poké Ball."],
	"potion": ["Potion", "Restores 20 HP to one Pokémon."],
}


func _ready() -> void:
	layer = 8
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var w := Ui.window("Bag", close_menu)
	var root: Control = w.root
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(440, 360)
	root.position = Vector2(-220, -180)
	add_child(root)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	w.content.add_child(list)
	var money := Ui.label("", 16, Ui.GOLD)
	w.content.add_child(money)
	var data: Dictionary = await Session.get_party()
	money.text = "Money: " + Ui.money(int(data.get("money", 0)))
	var items: Dictionary = data.get("items", {})
	if items.is_empty():
		list.add_child(Ui.label("Your bag is empty.", 15, Ui.TEXT_DIM))
	for id: String in items:
		var n := int(items[id])
		if n <= 0:
			continue
		var info: Array = ITEM_INFO.get(id, [id.capitalize(), ""])
		var row := Ui.panel(Color(0.14, 0.17, 0.23, 0.9))
		list.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		h.add_child(col)
		col.add_child(Ui.label(info[0], 16))
		if info[1] != "":
			col.add_child(Ui.label(info[1], 12, Ui.TEXT_DIM))
		var count := Ui.label("×%d" % n, 18)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(count)


func close_menu() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_B, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		close_menu()
