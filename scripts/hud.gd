extends CanvasLayer
## Anzeige über dem Spiel: Tiefe, Kasse, Eimer, Lampe, Hinweise und Meldungen.

const C_TEXT := Color("#f2e7d9")
const C_MUTED := Color("#a99686")
const C_ACCENT := Color("#ff8a3d")
const C_GOOD := Color("#a8d672")
const C_WARN := Color("#ff5d4f")
const C_CAUTION := Color("#f2c14e")
const C_SKY := Color("#7fd0ff")

var depth_l: Label
var layer_l: Label
var money_l: Label
var load_l: Label
var load_bar: ProgressBar
var lamp_l: Label
var lamp_bar: ProgressBar
var journey_l: Label
var prompt_l: Label
var gain_l: Label
var cross: ColorRect
var toast_box: VBoxContainer


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.add_theme_stylebox_override("panel", _plate())
	add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(250, 0)
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	depth_l = _label(v, 30, C_TEXT)
	layer_l = _label(v, 15, C_TEXT)
	money_l = _label(v, 22, C_GOOD)
	load_l = _label(v, 13, C_MUTED)
	load_bar = _bar(v, C_ACCENT)
	lamp_l = _label(v, 13, C_MUTED)
	lamp_bar = _bar(v, C_GOOD)
	journey_l = _label(v, 12, C_SKY)

	prompt_l = Label.new()
	prompt_l.add_theme_font_size_override("font_size", 17)
	prompt_l.add_theme_stylebox_override("normal", _plate())
	add_child(prompt_l)

	cross = ColorRect.new()
	cross.color = Color.WHITE
	cross.size = Vector2(6, 6)
	add_child(cross)

	gain_l = Label.new()
	gain_l.add_theme_font_size_override("font_size", 16)
	gain_l.add_theme_color_override("font_color", C_ACCENT)
	gain_l.modulate.a = 0.0
	add_child(gain_l)

	toast_box = VBoxContainer.new()
	toast_box.add_theme_constant_override("separation", 8)
	add_child(toast_box)

	Game.toast.connect(show_toast)


func _plate() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.055, 0.045, 0.82)
	sb.border_color = Color("#3d2f25")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _bar(parent: Control, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(250, 8)
	b.show_percentage = false
	b.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#2b2119")
	bg.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	b.set_meta("fill", fill)
	parent.add_child(b)
	return b


## Wird jedes Bild von main.gd aufgerufen.
func refresh(zone: String, prompt: String, urgent: bool) -> void:
	var L := Game.current_layer()
	depth_l.text = Game.fmt_depth(Game.depth)
	layer_l.text = L["name"]
	money_l.text = Game.fmt_eur(Game.eur)
	var cap := Game.cap_kg()
	load_l.text = "Eimer  %s / %s kg" % [Game.fmt_num(Game.load_kg, 1), Game.fmt_num(cap)]
	load_bar.value = clampf(Game.load_kg / cap, 0.0, 1.0)
	var load_fill: StyleBoxFlat = load_bar.get_meta("fill")
	load_fill.bg_color = C_CAUTION if Game.load_kg >= cap - 0.000001 else C_ACCENT
	# Lampe: bewusst keine Sekunden, nur eine Einschätzung des Rückwegs
	lamp_l.text = "Lampe  " + ("voll" if zone == "bereit" else "Rückweg " + zone)
	lamp_bar.value = clampf(Game.batt / Game.lamp_max(), 0.0, 1.0)
	var lamp_color := C_GOOD
	if zone == "knapp":
		lamp_color = C_CAUTION
	elif zone == "riskant":
		lamp_color = C_WARN
	var lamp_fill: StyleBoxFlat = lamp_bar.get_meta("fill")
	lamp_fill.bg_color = lamp_color
	lamp_l.add_theme_color_override("font_color", lamp_color if zone != "bereit" else C_MUTED)
	var pct := Game.depth / Game.EARTH_PATH * 100.0
	journey_l.text = "Bis zum Südpazifik: %s %%" % Game.fmt_num(pct, 6 if pct < 0.001 else 4)

	var vp := get_viewport().get_visible_rect().size
	prompt_l.text = prompt
	prompt_l.visible = prompt != ""
	prompt_l.add_theme_color_override("font_color", C_CAUTION if urgent else C_TEXT)
	prompt_l.reset_size()
	prompt_l.position = Vector2((vp.x - prompt_l.size.x) / 2.0, vp.y - prompt_l.size.y - 22.0)
	cross.position = vp / 2.0 - Vector2(3, 3)
	cross.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	gain_l.position = vp / 2.0 + Vector2(14, -34)
	toast_box.position = Vector2(vp.x - 396.0, 16.0)


func show_gain(text: String) -> void:
	gain_l.text = text
	gain_l.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(gain_l, "modulate:a", 0.0, 0.6)


func show_toast(text: String, kind: String = "") -> void:
	var p := PanelContainer.new()
	var sb := _plate()
	sb.border_width_left = 3
	match kind:
		"money": sb.border_color = C_GOOD
		"warn": sb.border_color = C_WARN
		"big": sb.border_color = C_SKY
		_: sb.border_color = C_ACCENT
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(350, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", C_TEXT)
	p.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 4:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	get_tree().create_timer(6.0 if kind == "big" else 4.5).timeout.connect(_expire.bind(p))


func _expire(p: Node) -> void:
	if is_instance_valid(p):
		p.queue_free()
