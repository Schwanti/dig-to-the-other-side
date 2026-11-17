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
var streak := 0          # Gänge in Folge ohne Ohnmacht
var best_trip := 0.0

# Gang-Karte: jeder Gang hat einen eigenen Dreh (wird nicht gespeichert)
var mod: Dictionary = {}
var MODS: Array = [
	{"id": "soft", "name": "Weicher Boden", "desc": "Graben ×1,5"},
	{"id": "lamp", "name": "Frische Batterien", "desc": "Lampe +30 %"},
	{"id": "combo", "name": "Rhythmus im Blut", "desc": "Der Takt baut sich doppelt so schnell auf"},
	{"id": "gold", "name": "Goldene Stunde", "desc": "Eine Goldader nach 10 Sekunden"},
	{"id": "crit", "name": "Glückspilz", "desc": "Glückstreffer doppelt so oft"},
	{"id": "finds", "name": "Fundreiche Schicht", "desc": "Doppelt so viele Klumpen"},
	{"id": "mole", "name": "Maulwurf-Party", "desc": "Alle Helfer ×3"},
]

# ---------- Helfer ----------
# Sie graben selbstständig und bringen ihren Aushub selbst hoch.
var HELPERS: Array = [
	{"id": "mole", "name": "Maulwurf", "rate": 0.01, "cost": 15, "growth": 1.35, "desc": "Wühlt unten mit und bringt seinen Aushub selbst hoch."},
	{"id": "kid", "name": "Nachbarskind", "rate": 0.04, "cost": 80, "growth": 1.35, "desc": "Gräbt neben dir. Wird mit Eis bezahlt."},
]
var EXTRAS: Array = [
	{"id": "coffee", "name": "Kaffeemaschine", "cost": 300, "desc": "Alle Helfer graben 1,5× so schnell."},
]
var n: Dictionary = {"mole": 0, "kid": 0}
var ex: Dictionary = {}

# ---------- Aufträge ----------
var best_mult := 1.0
var best_load := 0.0
var q_done: Dictionary = {}
var QUESTS: Array = [
	{"id": "d1", "t": "Grab 1 m tief", "r": 15},
	{"id": "trip", "t": "Bring den ersten Eimer hoch", "r": 15},
	{"id": "spade", "t": "Kauf einen Spaten", "r": 20},
	{"id": "finds3", "t": "Sammle 3 Klumpen", "r": 30},
	{"id": "takt2", "t": "Schaffe einen Takt von ×2", "r": 40},
	{"id": "d10", "t": "Erreiche 10 m Tiefe", "r": 60},
	{"id": "kid", "t": "Heuere ein Nachbarskind an", "r": 50},
	{"id": "load40", "t": "Bring 40 kg auf einmal hoch", "r": 80},
	{"id": "rare", "t": "Finde etwas Seltenes", "r": 80},
	{"id": "d30", "t": "Erreiche 30 m: Sandstein", "r": 150},
	{"id": "winch", "t": "Kauf die Seilwinde", "r": 150},
	{"id": "epic", "t": "Finde etwas Episches", "r": 250},
	{"id": "book5", "t": "Fülle 5 Seiten im Sammelbuch", "r": 300},
	{"id": "d100", "t": "Erreiche 100 m Tiefe", "r": 400},
]

func quest_ok(id: String) -> bool:
	match id:
		"d1": return depth >= 1.0
		"trip": return trips >= 1
		"spade": return lv["tool"] >= 1
		"finds3": return found_total >= 3
		"takt2": return best_mult >= 2.0
		"d10": return depth >= 10.0
		"kid": return n["kid"] >= 1
		"load40": return best_load >= 40.0
		"rare": return best_rarity >= 1
		"d30": return depth >= 30.0
		"winch": return lv["climb"] >= 2
		"epic": return best_rarity >= 2
		"book5": return book.size() >= 5
		"d100": return depth >= 100.0
	return false

# ---------- Fundstücke ----------
const FIND_CHANCE := 0.035   # pro Schlag
var RARITY: Array = [
	{"name": "Gewöhnlich", "color": Color("#c9c1b6"), "w": 70, "glow": "ist matt und schwer"},
	{"name": "Selten", "color": Color("#7fd0ff"), "w": 22, "glow": "schimmert blau"},
	{"name": "Episch", "color": Color("#c58bff"), "w": 7, "glow": "leuchtet violett"},
	{"name": "Legendär", "color": Color("#ffcf3f"), "w": 1, "glow": "glüht golden"},
]
# layers = in welchen Schichten (Index in LAYERS) das Stück vorkommt
var FINDS: Array = [
	{"id": "kiesel", "name": "Kieselstein", "r": 0, "val": 3, "layers": [0, 1, 2, 3]},
	{"id": "scherbe", "name": "Glasscherbe", "r": 0, "val": 4, "layers": [0, 1]},
	{"id": "muenze", "name": "Alte Münze", "r": 1, "val": 25, "layers": [0, 1]},
	{"id": "hufeisen", "name": "Hufeisen", "r": 1, "val": 30, "layers": [0, 1]},
	{"id": "achat", "name": "Achat", "r": 1, "val": 45, "layers": [1, 2]},
	{"id": "haizahn", "name": "Haizahn", "r": 2, "val": 120, "layers": [1, 2]},
	{"id": "ammonit", "name": "Ammonit", "r": 2, "val": 160, "layers": [2]},
	{"id": "kristall", "name": "Bergkristall", "r": 2, "val": 200, "layers": [2, 3]},
	{"id": "gold", "name": "Goldnugget", "r": 3, "val": 600, "layers": [1, 2, 3]},
	{"id": "dino", "name": "Dinosaurier-Knochen", "r": 3, "val": 900, "layers": [2]},
]
var SONAR_KINDS: Array = [
	{"id": "metall", "name": "Metallsignal", "pool": ["muenze", "hufeisen", "gold"]},
	{"id": "fossil", "name": "Fossilien-Echo", "pool": ["haizahn", "ammonit", "dino"]},
	{"id": "hohl", "name": "Kristall-Hohlraum", "pool": ["achat", "kristall", "gold"]},
]
var bag: Array = []            # eingesammelte, noch nicht aufgeklopfte Klumpen (IDs)
var book: Dictionary = {}      # Sammelbuch: ID -> Anzahl
var found_total := 0
var best_rarity := -1
var sonar: Dictionary = {}     # aktuelles Echolot-Ziel: {"d": Tiefe, "k": Art}


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

func mod_is(id: String) -> bool:
	return not mod.is_empty() and mod["id"] == id

func roll_mod() -> Dictionary:
	mod = MODS[randi() % MODS.size()]
	if mod["id"] == "lamp":
		batt = lamp_max() * 1.3
	return mod

## Je länger man unten gräbt, desto mehr ist der Eimer wert (bis ×2,5).
func depth_bonus(under_t: float) -> float:
	return 1.0 + minf(15.0, floorf(under_t / 10.0)) * 0.1

## Gänge in Folge ohne Ohnmacht (bis ×1,5).
func streak_mult() -> float:
	return 1.0 + minf(float(streak), 10.0) * 0.05

func fmt_x(v: float) -> String:
	return "×" + fmt_num(v, 1)

## Verkauft den Eimer mit allen Boni. knapp = mit fast leerer Lampe oben angekommen.
func sell(knapp: bool = false, under_t: float = 0.0) -> void:
	if load_kg <= 0.0:
		return
	var mults := PackedStringArray()
	var m := 1.0
	var deep := depth_bonus(under_t)
	if deep > 1.0:
		m *= deep
		mults.append("Tiefenbonus " + fmt_x(deep))
	if streak > 0:
		m *= streak_mult()
		mults.append("Serie " + fmt_x(streak_mult()))
	if knapp:
		m *= 1.5
		mults.append("Knapp ×1,5")
	var total := roundf(load_val * m)
	eur += total
	total_eur += total
	trips += 1
	streak += 1
	sold_kg += load_kg
	best_load = maxf(best_load, load_kg)
	var extra := "" if mults.is_empty() else "  (" + " · ".join(mults) + ")"
	toast.emit("Gang %d: %s kg Aushub = %s%s" % [trips, fmt_num(load_kg, 1), fmt_eur(total), extra], "money")
	if knapp:
		toast.emit("KNAPP GESCHAFFT! Der ganze Gang zählt ×1,5.", "gold")
	if total > best_trip:
		if trips > 1:
			toast.emit("Neuer Rekord-Gang: %s!" % fmt_eur(total), "money")
		best_trip = total
	load_kg = 0.0
	load_val = 0.0
	save_game()

func helper_rate() -> float:
	var sum := 0.0
	for h in HELPERS:
		sum += float(h["rate"]) * int(n[h["id"]])
	return sum * (1.5 if ex.has("coffee") else 1.0) * (3.0 if mod_is("mole") else 1.0)

func helper_cost(h: Dictionary) -> float:
	return ceilf(float(h["cost"]) * pow(float(h["growth"]), int(n[h["id"]])))

func buy_helper(h: Dictionary) -> bool:
	var c := helper_cost(h)
	if eur < c:
		return false
	eur -= c
	n[h["id"]] += 1
	if n[h["id"]] == 1:
		toast.emit("%s packt mit an!" % h["name"], "big")
	save_game()
	return true

func buy_extra(e: Dictionary) -> bool:
	if ex.has(e["id"]) or eur < float(e["cost"]):
		return false
	eur -= float(e["cost"])
	ex[e["id"]] = true
	toast.emit("%s gekauft!" % e["name"], "big")
	save_game()
	return true

func open_quests() -> Array:
	var out: Array = []
	for i in QUESTS.size():
		if not q_done.has(QUESTS[i]["id"]):
			out.append(i)
		if out.size() == 3:
			break
	return out

## Prüft die drei offenen Aufträge und zahlt erledigte aus.
func check_quests() -> void:
	for i in open_quests():
		var q: Dictionary = QUESTS[i]
		if quest_ok(q["id"]):
			q_done[q["id"]] = true
			eur += float(q["r"])
			total_eur += float(q["r"])
			toast.emit("Auftrag erledigt: %s  ·  +%s" % [q["t"], fmt_eur(q["r"])], "big")

func quest_lines() -> Array:
	var out: Array = []
	for i in open_quests():
		out.append("%s  (+%d €)" % [QUESTS[i]["t"], QUESTS[i]["r"]])
	return out

func find_by_id(id: String) -> Dictionary:
	for F in FINDS:
		if F["id"] == id:
			return F
	return FINDS[0]

## Zieht ein zufälliges Fundstück passend zur Schicht. Seltenes ist selten.
func roll_find() -> Dictionary:
	var li := layer_idx(depth)
	var roll := randf() * 100.0
	var r := 0
	var cum := 0.0
	for i in range(RARITY.size() - 1, -1, -1):
		cum += float(RARITY[i]["w"])
		if roll < cum:
			r = i
			break
	while r >= 0:
		var opts: Array = FINDS.filter(func(F): return F["r"] == r and li in F["layers"])
		if not opts.is_empty():
			return opts[randi() % opts.size()]
		r -= 1
	return FINDS[0]

## Echolot: setzt ein Ziel knapp unter der Sohle, erreichbar in einem Gang.
func new_sonar() -> void:
	if not sonar.is_empty():
		return
	var k: Dictionary = SONAR_KINDS[randi() % SONAR_KINDS.size()]
	var reach := cap_kg() / KG_PER_M
	var d := depth + minf(reach * 0.85, 1.2 + randf() * maxf(1.0, reach * 0.7))
	sonar = {"d": d, "k": k["id"]}
	toast.emit("Echolot: %s %s unter der Sohle!" % [k["name"], fmt_len(d - depth)], "big")

func sonar_kind() -> Dictionary:
	for k in SONAR_KINDS:
		if k["id"] == sonar.get("k", ""):
			return k
	return SONAR_KINDS[0]

## Wählt das Fundstück für ein erreichtes Echolot-Ziel. Bevorzugt, was im Sammelbuch fehlt.
func pick_sonar_find() -> Dictionary:
	var k := sonar_kind()
	var li := layer_idx(depth)
	var pool: Array = FINDS.filter(func(F): return F["id"] in k["pool"])
	var fits: Array = pool.filter(func(F): return li in F["layers"])
	if not fits.is_empty():
		pool = fits
	var unknown: Array = pool.filter(func(F): return not book.has(F["id"]))
	var from: Array = unknown if (not unknown.is_empty() and randf() < 0.7) else pool
	return from[randi() % from.size()]

## Klopft einen Klumpen auf: trägt ihn ins Sammelbuch ein und zahlt aus.
func reveal(id: String) -> Dictionary:
	var F := find_by_id(id)
	var first := not book.has(id)
	book[id] = int(book.get(id, 0)) + 1
	var val := float(F["val"]) * (2.0 if first else 1.0)
	eur += val
	total_eur += val
	save_game()
	return {"F": F, "val": val, "first": first}

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
		"lv": lv, "trips": trips, "sold_kg": sold_kg, "streak": streak, "best_trip": best_trip,
		"bag": bag, "book": book, "found_total": found_total, "best_rarity": best_rarity, "sonar": sonar,
		"n": n, "ex": ex, "q_done": q_done, "best_mult": best_mult, "best_load": best_load,
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
	streak = int(data.get("streak", 0))
	best_trip = float(data.get("best_trip", 0.0))
	bag = Array(data.get("bag", []))
	found_total = int(data.get("found_total", 0))
	best_rarity = int(data.get("best_rarity", -1))
	sonar = data.get("sonar", {})
	best_mult = float(data.get("best_mult", 1.0))
	best_load = float(data.get("best_load", 0.0))
	ex = data.get("ex", {})
	q_done = data.get("q_done", {})
	var saved_n: Dictionary = data.get("n", {})
	for k in n.keys():
		n[k] = int(saved_n.get(k, 0))
	book = {}
	var saved_book: Dictionary = data.get("book", {})
	for id in saved_book.keys():
		book[id] = int(saved_book[id])
	var saved_lv: Dictionary = data.get("lv", {})
	for k in lv.keys():
		lv[k] = int(saved_lv.get(k, 0))
	batt = lamp_max()
	return true

func reset_game() -> void:
	depth = 0.0; eur = 0.0; total_eur = 0.0; load_kg = 0.0; load_val = 0.0
	trips = 0; sold_kg = 0.0; streak = 0; best_trip = 0.0; mod = {}
	bag = []; book = {}; found_total = 0; best_rarity = -1; sonar = {}
	n = {"mole": 0, "kid": 0}; ex = {}; q_done = {}; best_mult = 1.0; best_load = 0.0
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
