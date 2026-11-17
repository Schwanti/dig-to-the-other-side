extends CanvasLayer
## Werkbank im Garten: Ausrüstung kaufen. Öffnet sich mit E in der Nähe der Werkbank.

signal closed

var list: VBoxContainer
var money_l: Label


func _ready() -> void:
	layer = 10
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.02, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#211913")
	sb.border_color = Color("#3d2f25")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = "WERKBANK"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#a99686"))
	v.add_child(title)
	money_l = Label.new()
	money_l.add_theme_font_size_override("font_size", 28)
	money_l.add_theme_color_override("font_color", Color("#a8d672"))
	v.add_child(money_l)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	v.add_child(list)
	var close := Button.new()
	close.text = "Weiter graben  (E)"
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(close_ui)
	v.add_child(close)


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild()


func close_ui() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _rebuild() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	money_l.text = "Kasse: " + Game.fmt_eur(Game.eur)
	for k in Game.TRACKS.keys():
		var T: Dictionary = Game.TRACKS[k]
		var cur: Dictionary = T["tiers"][Game.lv[k]]
		var n := Game.next_tier(k)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 52)
		if n.is_empty():
			b.text = "%s: %s  ·  höchste Stufe" % [T["label"], cur["name"]]
			b.disabled = true
		else:
			var effect := (T["unit"] as String) % Game.fmt_num(float(n["v"]), 1)
			b.text = "%s: %s  →  %s\n%s  ·  %s" % [T["label"], cur["name"], n["name"], effect, Game.fmt_eur(float(n["cost"]))]
			b.disabled = Game.eur < float(n["cost"])
			b.pressed.connect(_buy.bind(k))
		list.add_child(b)


func _buy(k: String) -> void:
	if Game.buy(k):
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("use") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close_ui()
