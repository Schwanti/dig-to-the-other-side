extends Node
## Spielregeln und Spielstand. Als Autoload "Game" von überall erreichbar.
## Werte stammen aus dem Browser-Prototyp (Version 9) und dem Design-Dokument.

signal toast(text: String, kind: String)

const R := 1.6              # Radius des Lochs in m
const EYE := 1.7            # Augenhöhe in m
const KG_PER_M := 10.0      # so viel Aushub wiegt ein Meter Loch
const EARTH_PATH := 12738000.0
const SAVE_PATH := "user://spielstand.json"

# Schichten von oben nach unten. "to" = Ende der Schicht in m.
var LAYERS: Array = [
	{"name": "Mutterboden", "to": 1.0, "hard": 1.0, "price": 1.0, "base": Color("#4b3322"), "spot": Color("#6e4c31")},
	{"name": "Lehm & Kies", "to": 30.0, "hard": 1.5, "price": 1.5, "base": Color("#8a6943"), "spot": Color("#b9a184")},
	{"name": "Sandstein", "to": 800.0, "hard": 2.5, "price": 3.0, "base": Color("#c49a62"), "spot": Color("#e3c08a")},
	{"name": "Granit", "to": 1.0e9, "hard": 4.0, "price": 5.0, "base": Color("#8d8782"), "spot": Color("#e9e4dc")},
]

# Ausrüstung in Kapitel 1 (Garten). Stufe 0 besitzt man von Anfang an.
var TRACKS: Dictionary = {
	"tool": {"label": "Werkzeug", "unit": "Klickkraft ×%s", "tiers": [
		{"name": "Kinderschaufel", "v": 1.0},
		{"name": "Spaten", "cost": 25, "v": 3.0},
		{"name": "Spitzhacke", "cost": 220, "v": 7.5},
		{"name": "Presslufthammer", "cost": 1200, "v": 15.0}]},
	"cap": {"label": "Behälter", "unit": "%s kg pro Gang", "tiers": [
		{"name": "Kindereimer", "v": 20.0},
		{"name": "Zinkeimer", "cost": 40, "v": 40.0},
		{"name": "Schubkarre", "cost": 180, "v": 100.0},
		{"name": "Big Bag", "cost": 700, "v": 300.0},
		{"name": "Förderkorb", "cost": 2500, "v": 1000.0}]},
	"lamp": {"label": "Lampe", "unit": "%s s Licht", "tiers": [
		{"name": "Taschenlampe", "v": 60.0},
		{"name": "Stirnlampe", "cost": 70, "v": 150.0},
		{"name": "Grubenlampe", "cost": 400, "v": 300.0},
		{"name": "Akku-Strahler", "cost": 1500, "v": 900.0}]},
	"climb": {"label": "Aufstieg", "unit": "%s m/s hoch", "tiers": [
		{"name": "Holzleiter", "v": 1.0},
		{"name": "Kletterhandschuhe", "cost": 90, "v": 1.8},
		{"name": "Seilwinde", "cost": 450, "v": 4.0},
		{"name": "Bauaufzug", "cost": 2000, "v": 10.0}]},
}

# ---------- Spielstand ----------
var depth := 0.0
var eur := 0.0
var total_eur := 0.0
var load_kg := 0.0
var load_val := 0.0
var batt := 60.0
var lv: Dictionary = {"tool": 0, "cap": 0, "lamp": 0, "climb": 0}
var trips := 0
var sold_kg := 0.0


func _ready() -> void:
	_setup_input()
	batt = lamp_max()


# ---------- Regeln ----------
func tier(k: String) -> float:
	return float(TRACKS[k]["tiers"][lv[k]]["v"])

func cap_kg() -> float:
	return tier("cap")

func lamp_max() -> float:
	return tier("lamp")

func climb_v() -> float:
	return tier("climb")

func layer_idx(d: float) -> int:
	for i in LAYERS.size():
		if d < float(LAYERS[i]["to"]):
			return i
	return LAYERS.size() - 1

func layer_from(i: int) -> float:
	return 0.0 if i == 0 else float(LAYERS[i - 1]["to"])

func current_layer() -> Dictionary:
	return LAYERS[layer_idx(depth)]

## Setzt Grabkraft in Tiefe um, auch über Schichtgrenzen hinweg.
## max_m begrenzt, wie viele Meter höchstens gegraben werden (Platz im Eimer).
func dig(power: float, max_m: float = INF) -> Dictionary:
	var rest := power
	var m := 0.0
	var val := 0.0
	while rest > 1e-9 and m < max_m - 1e-9:
		var L: Dictionary = LAYERS[layer_idx(depth)]
		var hard := float(L["hard"])
		var step := minf(rest / hard, minf(float(L["to"]) - depth, max_m - m))
		if step <= 0.0:
			break
		depth += step
		m += step
		val += step * KG_PER_M * float(L["price"])
		rest -= step * hard
	return {"m": m, "kg": m * KG_PER_M, "val": val}

func next_tier(k: String) -> Dictionary:
	var tiers: Array = TRACKS[k]["tiers"]
	if lv[k] + 1 < tiers.size():
		return tiers[lv[k] + 1]
	return {}

func buy(k: String) -> bool:
	var n := next_tier(k)
	if n.is_empty() or eur < float(n["cost"]):
		return false
	eur -= float(n["cost"])
	lv[k] += 1
	if k == "lamp":
		batt = lamp_max()
	toast.emit("%s gekauft!" % n["name"], "big")
	save_game()
	return true

func sell() -> void:
	if load_kg <= 0.0:
		return
	var total := roundf(load_val)
	eur += total
	total_eur += total
	trips += 1
	sold_kg += load_kg
	toast.emit("Gang %d: %s kg Aushub = %s" % [trips, fmt_num(load_kg, 1), fmt_eur(total)], "money")
	load_kg = 0.0
	load_val = 0.0
	save_game()

## Wie gut reicht das Licht für den Rückweg? Bewusst unscharf, ohne Sekunden.
func return_zone(player_y: float, at_base: bool) -> String:
	if at_base:
		return "bereit"
	var need := maxf(0.0, -player_y) / climb_v()
	var margin := batt - need
	if margin > need * 0.8 + 10.0:
		return "sicher"
	if margin > 2.0:
		return "knapp"
	return "riskant"


# ---------- Speichern ----------
func save_game() -> void:
	var data := {
		"depth": depth, "eur": eur, "total_eur": total_eur, "load_kg": load_kg, "load_val": load_val,
		"lv": lv, "trips": trips, "sold_kg": sold_kg,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	depth = float(data.get("depth", 0.0))
	eur = float(data.get("eur", 0.0))
	total_eur = float(data.get("total_eur", 0.0))
	load_kg = float(data.get("load_kg", 0.0))
	load_val = float(data.get("load_val", 0.0))
	trips = int(data.get("trips", 0))
	sold_kg = float(data.get("sold_kg", 0.0))
	var saved_lv: Dictionary = data.get("lv", {})
	for k in lv.keys():
		lv[k] = int(saved_lv.get(k, 0))
	batt = lamp_max()
	return true

func reset_game() -> void:
	depth = 0.0; eur = 0.0; total_eur = 0.0; load_kg = 0.0; load_val = 0.0
	trips = 0; sold_kg = 0.0
	for k in lv.keys():
		lv[k] = 0
	batt = lamp_max()
	save_game()


# ---------- Formatierung (deutsch) ----------
func fmt_num(v: float, decimals: int = 0) -> String:
	var s := ("%." + str(decimals) + "f") % v
	var parts := s.split(".")
	var int_part: String = parts[0]
	var neg := int_part.begins_with("-")
	if neg:
		int_part = int_part.substr(1)
	var out := ""
	var count := 0
	for i in range(int_part.length() - 1, -1, -1):
		out = int_part[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	if neg:
		out = "-" + out
	if parts.size() > 1:
		out += "," + parts[1]
	return out

func fmt_eur(v: float) -> String:
	return fmt_num(floorf(v)) + " €"

func fmt_len(m: float) -> String:
	if m < 1.0:
		return fmt_num(m * 100.0, 1) + " cm"
	if m < 1000.0:
		return fmt_num(m, 2 if m < 10.0 else 1) + " m"
	return fmt_num(m / 1000.0, 2) + " km"

func fmt_depth(m: float) -> String:
	if m < 1000.0:
		return fmt_num(m, 2) + " m"
	return fmt_num(m / 1000.0, 3) + " km"


# ---------- Steuerung ----------
func _setup_input() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("climb", KEY_F)
	_add_key("use", KEY_E)
	_add_key("dig_key", KEY_SPACE)
	_add_mouse("dig", MOUSE_BUTTON_LEFT)

func _add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
