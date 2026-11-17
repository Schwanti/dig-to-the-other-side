extends Node3D
## Baut die Welt auf und führt die Spielschleife aus:
## graben, hochklettern, verkaufen, an der Werkbank aufrüsten, wieder runter.

const ShaftScript := preload("res://scripts/shaft.gd")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")
const WorkbenchScript := preload("res://scripts/workbench_ui.gd")

const BENCH_POS := Vector3(4.6, 0.0, 2.6)
const COOLDOWN := [0.24, 0.26, 0.32, 0.1]   # Pause zwischen zwei Schlägen je Werkzeug

# Ohne festen Typ, damit die eigenen Eigenschaften der Skripte (state, cam, refresh …) erreichbar sind
var shaft
var player
var hud
var bench_ui
var sun: DirectionalLight3D
var env: Environment
var dirt: CPUParticles3D
var sparks: CPUParticles3D
var gold_disc: MeshInstance3D
var gold_mat: StandardMaterial3D

var cooldown := 0.0
var warned := 0
var save_timer := 0.0
var clock := 0.0            # Spielzeit in Sekunden, für Takt und Goldader

# Takt: wer im Rhythmus gräbt, gräbt schneller (bis ×2,5)
var combo := 0
var last_hit := -10.0
var combo_level := 0
# Tiefenbonus: Zeit unten in diesem Gang
var under_t := 0.0
var last_bonus_step := 0
# Goldader: taucht ab und zu in der Sohle auf
var gold_until := -1.0
var gold_timer := 45.0
# Klumpen, die in der Sohle liegen: {"node": Node3D, "F": Fundstück}
var finds: Array = []
var reveal_queue: Array = []
var revealing := false


func _ready() -> void:
	_build_environment()
	_build_garden()
	shaft = ShaftScript.new()
	add_child(shaft)
	player = PlayerScript.new()
	add_child(player)
	_build_particles()
	hud = HudScript.new()
	add_child(hud)
	bench_ui = WorkbenchScript.new()
	add_child(bench_ui)

	player.dig_pressed.connect(_on_dig)
	player.use_pressed.connect(_on_use)
	player.arrived_surface.connect(_on_arrived_surface)
	player.descend_started.connect(_on_descend)
	bench_ui.closed.connect(func(): player.input_enabled = true)
	_build_gold_disc()

	if Game.load_game() and Game.depth > 0.05:
		player.place_on_surface()
		Game.toast.emit("Spielstand geladen: %s tief, %s in der Kasse." % [Game.fmt_depth(Game.depth), Game.fmt_eur(Game.eur)], "big")
	else:
		Game.toast.emit("Grab los! Klick zum Graben. Ist der Eimer voll, kletterst du mit F hoch.", "big")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	cooldown -= delta
	clock += delta
	# Presslufthammer: gedrückt halten hämmert von selbst
	if Game.lv["tool"] == 3 and Input.is_action_pressed("dig") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_on_dig()

	_update_lamp(delta)
	shaft.update_depth(Game.depth)
	_update_light()
	_update_bonus(delta)
	_update_gold(delta)
	_update_finds()
	if not Game.sonar.is_empty() and Game.depth >= float(Game.sonar["d"]):
		_sonar_reached()
	if clock - last_hit > 0.8:
		combo = 0
		combo_level = 0

	var zone := Game.return_zone(player.position.y, player.state == "surface" or player.position.y > -1.0)
	var p := _prompt(zone)
	var boosts := PackedStringArray()
	if Game.depth_bonus(under_t) > 1.0:
		boosts.append("Tiefenbonus " + Game.fmt_x(Game.depth_bonus(under_t)))
	if Game.streak > 0:
		boosts.append("Serie %d %s" % [Game.streak, Game.fmt_x(Game.streak_mult())])
	if not Game.mod.is_empty():
		boosts.append(Game.mod["name"])
	var sonar_text := ""
	if not Game.sonar.is_empty():
		sonar_text = "Echolot: %s · noch %s" % [Game.sonar_kind()["name"], Game.fmt_len(maxf(0.0, float(Game.sonar["d"]) - Game.depth))]
	hud.refresh(zone, p[0], p[1], {
		"combo": combo, "combo_mult": _combo_mult(), "boosts": " · ".join(boosts),
		"sonar": sonar_text, "aim_find": _aimed_find() >= 0, "bag": Game.bag.size(),
	})

	save_timer += delta
	if save_timer > 5.0:
		save_timer = 0.0
		Game.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save_game()


# ---------- Graben ----------
func _on_dig() -> void:
	if cooldown > 0.0 or bench_ui.visible:
		return
	if player.state == "surface":
		cooldown = 1.0
		Game.toast.emit("Hier oben wird nicht gegraben. Mit F geht es die Leiter runter.", "")
		return
	if player.state != "bottom":
		return
	var aimed := _aimed_find()
	if aimed >= 0:
		cooldown = 0.15
		_collect(aimed)
		return
	var room := (Game.cap_kg() - Game.load_kg) / Game.KG_PER_M
	if room <= 0.000001:
		cooldown = 1.0
		Game.toast.emit("Der Eimer ist voll. Ab nach oben mit F!", "warn")
		return
	cooldown = COOLDOWN[Game.lv["tool"]]

	# Takt: Schläge innerhalb von 0,8 s bauen ihn auf
	if clock - last_hit < 0.8:
		combo += 2 if Game.mod_is("combo") else 1
	else:
		combo = 0
	last_hit = clock
	var mult := _combo_mult()
	var level := 3 if mult >= 2.5 else (2 if mult >= 2.0 else (1 if mult >= 1.5 else 0))
	if level > combo_level:
		hud.show_takt_level(mult)
	combo_level = level

	var crit := randf() < (0.1 if Game.mod_is("crit") else 0.05)
	var gold := _gold_on()
	var power := 0.03 * Game.tier("tool") * mult * (5.0 if crit else 1.0) * (1.5 if Game.mod_is("soft") else 1.0)
	var r := Game.dig(power, room)
	Game.load_kg += r["kg"]
	Game.load_val += r["val"] * (5.0 if gold else 1.0)

	player.do_swing()
	player.shake = 0.05 if crit else 0.02
	var L := Game.current_layer()
	var at := _aim_point()
	dirt.global_position = at
	dirt.color = L["spot"]
	dirt.restart()
	if crit or gold:
		sparks.global_position = at
		sparks.color = Color.WHITE if crit else Color("#ffcf3f")
		sparks.amount = 30 if crit else 10
		sparks.restart()
	if crit:
		hud.show_gain("GLÜCKSTREFFER +" + Game.fmt_len(r["m"]), Color.WHITE)
	elif gold:
		hud.show_gain("GOLD ×5 +" + Game.fmt_len(r["m"]), Color("#ffcf3f"))
	else:
		hud.show_gain("+" + Game.fmt_len(r["m"]))
	if randf() < Game.FIND_CHANCE * (2.0 if Game.mod_is("finds") else 1.0):
		_spawn_find(_scatter(at), Game.roll_find())
	if Game.load_kg >= Game.cap_kg() - 0.000001:
		Game.toast.emit("Eimer voll! Ab nach oben mit F.", "warn")


# ---------- Klumpen ----------
## Ein Klumpen zeigt nur, wie selten er ist. Was drin ist, sieht man erst oben beim Aufklopfen.
func _spawn_find(at: Vector3, F: Dictionary) -> void:
	var r: int = F["r"]
	var col: Color = Game.RARITY[r]["color"]
	var g := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#6e5a46")
	mat.roughness = 0.95
	if r > 0:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 0.3 + r * 0.35
	for part in [[0.09, Vector3(0, 0.04, 0), Vector3(1.3, 0.8, 1.05)], [0.05, Vector3(0.07, 0.03, 0.03), Vector3.ONE]]:
		var sm := SphereMesh.new()
		sm.radius = part[0]
		sm.height = part[0] * 1.5
		sm.radial_segments = 7
		sm.rings = 3
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = mat
		mi.position = part[1]
		mi.scale = part[2]
		mi.rotation = Vector3(randf(), randf() * TAU, randf())
		g.add_child(mi)
	if r >= 1:
		# Lichtsäule und Schein wie bei einer Belohnung
		var bm := CylinderMesh.new()
		bm.top_radius = 0.025
		bm.bottom_radius = 0.025
		bm.height = 2.4
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(col, 0.5)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var beam := MeshInstance3D.new()
		beam.mesh = bm
		beam.material_override = bmat
		beam.position.y = 1.2
		g.add_child(beam)
		g.set_meta("beam_mat", bmat)
		var glow := OmniLight3D.new()
		glow.light_color = col
		glow.omni_range = 2.2
		glow.light_energy = 0.8
		glow.position.y = 0.2
		g.add_child(glow)
		Game.toast.emit("Da glitzert was: %s!" % Game.RARITY[r]["name"], "big")
	add_child(g)
	g.position = Vector3(at.x, -Game.depth - 0.015, at.z)
	finds.append({"node": g, "F": F})
	# Höchstens vier Klumpen gleichzeitig: der älteste verschwindet
	if finds.size() > 4:
		var old: Dictionary = finds.pop_front()
		old["node"].queue_free()


func _scatter(p: Vector3) -> Vector3:
	var q := p + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	var r := Vector2(q.x, q.z).length()
	if r > Game.R - 0.25:
		q.x *= (Game.R - 0.25) / r
		q.z *= (Game.R - 0.25) / r
	return q


## Liegt ein Klumpen unter dem Fadenkreuz (höchstens 3,2 m entfernt)?
func _aimed_find() -> int:
	if player.state != "bottom" or finds.is_empty():
		return -1
	var cam: Camera3D = player.cam
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var best := -1
	var best_t := 3.2
	for i in finds.size():
		var c: Vector3 = finds[i]["node"].global_position + Vector3(0, 0.05, 0)
		var t := (c - o).dot(d)
		if t < 0.0 or t > best_t:
			continue
		if (o + d * t).distance_to(c) < 0.17:
			best = i
			best_t = t
	return best


func _collect(i: int) -> void:
	var f: Dictionary = finds[i]
	finds.remove_at(i)
	var F: Dictionary = f["F"]
	var r: int = F["r"]
	Game.bag.append(F["id"])
	Game.found_total += 1
	Game.best_rarity = maxi(Game.best_rarity, r)
	Game.toast.emit("Klumpen eingesammelt. Er %s (%s). Was drin ist, siehst du oben." % [Game.RARITY[r]["glow"], Game.RARITY[r]["name"]], "big" if r >= 2 else "")
	# Der Klumpen fliegt in die Hand
	var node: Node3D = f["node"]
	for c in node.get_children():
		if c is OmniLight3D or (c is MeshInstance3D and (c as MeshInstance3D).position.y > 1.0):
			c.visible = false
	var target: Vector3 = player.cam.global_position + Vector3(0, -0.3, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "global_position", target, 0.35)
	tw.tween_property(node, "scale", Vector3.ONE * 0.05, 0.35)
	tw.chain().tween_callback(node.queue_free)


## Klumpen liegen in der Sohle und wandern mit ihr nach unten. Lichtsäulen pulsieren.
func _update_finds() -> void:
	for f in finds:
		var node: Node3D = f["node"]
		node.position.y = -Game.depth - 0.015
		if node.has_meta("beam_mat"):
			var bm: StandardMaterial3D = node.get_meta("beam_mat")
			bm.albedo_color.a = 0.35 + 0.25 * sin(clock * 5.0)


func _sonar_reached() -> void:
	var k := Game.sonar_kind()
	var F := Game.pick_sonar_find()
	Game.sonar = {}
	var at := _scatter(_aim_point()) if player.state == "bottom" else Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
	_spawn_find(at, F)
	Game.toast.emit("Echolot-Ziel erreicht: %s! Der Klumpen liegt in der Sohle." % k["name"], "big")


## Oben werden die Klumpen einzeln aufgeklopft: erst Klopfen und Spannung, dann der Inhalt.
func _queue_reveal(items: Array) -> void:
	reveal_queue.append_array(items)
	if revealing:
		return
	revealing = true
	while not reveal_queue.is_empty():
		var id: String = reveal_queue.pop_front()
		var F := Game.find_by_id(id)
		var fast := reveal_queue.size() > 3
		hud.show_reveal_start(Game.RARITY[F["r"]], reveal_queue.size() + 1)
		await get_tree().create_timer(0.45 if fast else 0.85).timeout
		var res := Game.reveal(id)
		hud.show_reveal_result(res, Game.RARITY[F["r"]])
		await get_tree().create_timer(0.7 if fast else 1.4).timeout
	hud.hide_reveal()
	revealing = false


func _combo_mult() -> float:
	return 1.0 + minf(float(combo), 30.0) / 20.0


func _gold_on() -> bool:
	return clock < gold_until


## Tiefenbonus wächst, solange man unten gräbt.
func _update_bonus(delta: float) -> void:
	if player.state != "bottom" or Game.depth <= 1.0 or bench_ui.visible:
		return
	under_t += delta
	var step := int(minf(15.0, floorf(under_t / 10.0)))
	if step > last_bonus_step:
		last_bonus_step = step
		if step % 5 == 0:
			Game.toast.emit("Tiefenbonus %s! Je länger du unten bleibst, desto mehr ist der Eimer wert." % Game.fmt_x(Game.depth_bonus(under_t)), "gold")


## Goldader: etwa alle ein bis zwei Minuten leuchtet die Sohle 10 Sekunden lang golden.
func _update_gold(delta: float) -> void:
	if player.state == "bottom" and not _gold_on() and not bench_ui.visible:
		gold_timer -= delta
		if gold_timer <= 0.0:
			gold_timer = 50.0 + randf() * 60.0
			gold_until = clock + 10.0
			Game.toast.emit("GOLDADER! 10 Sekunden lang ist jeder Schlag 5× so viel wert.", "gold")
	gold_disc.visible = _gold_on()
	if gold_disc.visible:
		gold_disc.position.y = -Game.depth + 0.012
		gold_mat.albedo_color.a = 0.25 + 0.15 * sin(clock * 9.0)


func _on_descend() -> void:
	var m := Game.roll_mod()
	if m["id"] == "gold":
		gold_timer = 10.0
	hud.show_mod_card("Gang %d%s" % [Game.trips + 1, ("  ·  Serie %d" % Game.streak) if Game.streak > 0 else ""], m["name"], m["desc"])


## Wo trifft der Blick die Sohle?
func _aim_point() -> Vector3:
	var cam: Camera3D = player.cam
	var dir := -cam.global_transform.basis.z
	var origin := cam.global_position
	var fy := -Game.depth
	var t := 0.8
	if dir.y < -0.05:
		t = minf((fy - origin.y) / dir.y, 2.2)
	var p := origin + dir * t
	p.y = fy
	var r := Vector2(p.x, p.z).length()
	if r > Game.R - 0.25:
		p.x *= (Game.R - 0.25) / r
		p.z *= (Game.R - 0.25) / r
	return p


# ---------- Hochkommen, Verkaufen, Ohnmacht ----------
func _on_arrived_surface() -> void:
	var items: Array = Game.bag.duplicate()
	Game.bag.clear()
	var knapp := Game.batt / Game.lamp_max() < 0.1 and Game.depth > 3.0 and (Game.load_kg > 0.0 or not items.is_empty())
	Game.sell(knapp, under_t)
	_end_trip()
	if not items.is_empty():
		get_tree().create_timer(0.7).timeout.connect(_queue_reveal.bind(items))
	if Game.sonar.is_empty():
		get_tree().create_timer(1.5 + items.size() * 0.4).timeout.connect(Game.new_sonar)


func _end_trip() -> void:
	Game.batt = Game.lamp_max()
	Game.mod = {}
	warned = 0
	under_t = 0.0
	last_bonus_step = 0
	gold_until = -1.0


func _update_lamp(delta: float) -> void:
	if player.position.y >= -1.0 or bench_ui.visible:
		return
	Game.batt -= delta
	var ratio := Game.batt / Game.lamp_max()
	if ratio < 0.3 and warned < 1:
		warned = 1
		Game.toast.emit("Die Lampe wird schwach!", "warn")
	if ratio < 0.1 and warned < 2:
		warned = 2
		Game.toast.emit("Gleich ist es dunkel! Hoch, sofort!", "warn")
	if Game.batt <= 0.0:
		_faint()


func _faint() -> void:
	Game.load_kg = 0.0
	Game.load_val = 0.0
	# Die Hälfte der Klumpen geht verloren
	var lost := Game.bag.size() / 2
	for i in lost:
		Game.bag.remove_at(randi() % Game.bag.size())
	var items: Array = Game.bag.duplicate()
	Game.bag.clear()
	if not items.is_empty():
		get_tree().create_timer(1.5).timeout.connect(_queue_reveal.bind(items))
	if lost > 0:
		Game.toast.emit("%d Klumpen sind beim Rausziehen verloren gegangen." % lost, "warn")
	var had_streak := Game.streak
	Game.streak = 0
	_end_trip()
	player.place_on_surface()
	Game.toast.emit("Licht aus! Die Nachbarskinder haben dich rausgezogen. Der Eimer ist weg.", "warn")
	if had_streak > 1:
		Game.toast.emit("Deine Serie von %d Gängen ist gerissen." % had_streak, "warn")
	Game.save_game()


func _on_use() -> void:
	if player.state == "surface" and Vector2(player.position.x - BENCH_POS.x, player.position.z - BENCH_POS.z).length() < 2.6:
		player.input_enabled = false
		bench_ui.open()
	elif player.state == "surface":
		Game.toast.emit("Geh zur Werkbank neben dem Schuppen.", "")
	else:
		Game.toast.emit("Die Werkbank steht oben im Garten. Mit F geht es die Leiter hoch.", "")


func _prompt(zone: String) -> Array:
	match player.state:
		"bottom":
			if Game.load_kg >= Game.cap_kg() - 0.000001:
				return ["F  Eimer voll. Hochklettern und verkaufen!", true]
			if zone == "riskant":
				return ["F  Riskant! Jetzt hoch, sonst wird es dunkel!", true]
			if zone == "knapp":
				return ["F  Die Lampe wird knapp. Bald hochklettern!", true]
			if _aimed_find() >= 0:
				return ["Klick  Klumpen aufheben", false]
			if _gold_on():
				return ["Klick  GOLDADER! Schnell graben, jeder Schlag ×5", true]
			return ["Klick  graben   ·   F  hochklettern", false]
		"climb":
			return ["Klettert %s …   F  umkehren" % ("hoch" if player.climb_dir > 0 else "runter"), false]
		_:
			if Vector2(player.position.x - BENCH_POS.x, player.position.z - BENCH_POS.z).length() < 2.6:
				return ["E  Werkbank öffnen", false]
			return ["F  Sofort wieder runter in Gang %d" % (Game.trips + 1), true]


# ---------- Licht ----------
func _update_light() -> void:
	var under := maxf(0.0, -player.position.y)
	var day := clampf(1.0 - under / 7.0, 0.0, 1.0)
	sun.light_energy = 1.2 * day
	env.ambient_light_energy = 0.04 + 0.96 * day
	var ratio := clampf(Game.batt / Game.lamp_max(), 0.0, 1.0)
	var flick := 1.0
	if ratio < 0.25 and randf() < (0.25 - ratio) * 1.2:
		flick = 0.15
	var on := 1.0 if Game.batt > 0.0 else 0.0
	player.lamp.light_energy = (1.8 + Game.lv["lamp"] * 0.5) * flick * on
	player.lamp.spot_range = 18.0 + Game.lv["lamp"] * 8.0
	player.near_light.light_energy = 0.35 * flick * on
	player.lamp.visible = under > 0.5
	player.near_light.visible = under > 0.5


# ---------- Welt aufbauen ----------
func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#5d9ed6")
	sky_mat.sky_horizon_color = Color("#bfe0f2")
	sky_mat.ground_horizon_color = Color("#bfe0f2")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)


func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _box(size: Vector3, color: Color, pos: Vector3, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	return mi


func _sign(text: String, pos: Vector3, color := Color("#ff8a3d")) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	add_child(l)


func _build_garden() -> void:
	# Rasen mit einem runden Loch in der Mitte
	var csg := CSGCombiner3D.new()
	add_child(csg)
	var ground := CSGBox3D.new()
	ground.size = Vector3(120.0, 0.2, 120.0)
	ground.position.y = -0.1
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var grad := Gradient.new()
	grad.set_color(0, Color("#3f6b2a"))
	grad.set_color(1, Color("#6a9a45"))
	var tex := NoiseTexture2D.new()
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	var grass := StandardMaterial3D.new()
	grass.albedo_texture = tex
	grass.uv1_triplanar = true
	grass.uv1_world_triplanar = true
	grass.uv1_scale = Vector3(0.3, 0.3, 0.3)
	grass.roughness = 1.0
	ground.material = grass
	csg.add_child(ground)
	var hole := CSGCylinder3D.new()
	hole.radius = Game.R + 0.02
	hole.height = 2.0
	hole.sides = 48
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	csg.add_child(hole)

	# Haus
	_box(Vector3(9, 5, 7), Color("#e8dcc8"), Vector3(-4, 2.5, -16))
	var roof := MeshInstance3D.new()
	var rm := PrismMesh.new()
	rm.size = Vector3(9.6, 3.0, 7.4)
	roof.mesh = rm
	roof.material_override = _mat(Color("#9b3a2a"))
	roof.position = Vector3(-4, 6.5, -16)
	add_child(roof)
	_box(Vector3(1.2, 2.2, 0.1), Color("#4a3223"), Vector3(-4, 1.1, -12.45))

	# Bäume
	for t in [[-7.0, -5.0, 1.1], [-9.0, -12.0, 1.4], [14.0, 8.0, 1.2], [-16.0, 10.0, 1.5], [10.0, -9.0, 1.3]]:
		var s: float = t[2]
		var trunk := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18 * s
		cm.bottom_radius = 0.25 * s
		cm.height = 2.2 * s
		trunk.mesh = cm
		trunk.material_override = _mat(Color("#5a3d26"))
		trunk.position = Vector3(t[0], 1.1 * s, t[1])
		add_child(trunk)
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.5 * s
		sm.height = 3.0 * s
		crown.mesh = sm
		crown.material_override = _mat(Color("#3f6b2a"))
		crown.position = Vector3(t[0], 2.9 * s, t[1])
		add_child(crown)

	# Gartenzaun
	for i in range(-14, 15, 2):
		_box(Vector3(0.12, 1.0, 0.12), Color("#d8cbb3"), Vector3(i, 0.5, 9))
	_box(Vector3(28.4, 0.1, 0.06), Color("#d8cbb3"), Vector3(0, 0.8, 9))

	# Werkbank mit Schuppen
	var face := atan2(-BENCH_POS.x, -BENCH_POS.z)
	var bench := Node3D.new()
	bench.position = BENCH_POS
	bench.rotation.y = face
	add_child(bench)
	for part in [
		[Vector3(1.8, 0.08, 0.8), Color("#8b5e34"), Vector3(0, 0.92, 0)],
		[Vector3(0.08, 0.9, 0.08), Color("#5e3f22"), Vector3(-0.8, 0.45, -0.32)],
		[Vector3(0.08, 0.9, 0.08), Color("#5e3f22"), Vector3(0.8, 0.45, -0.32)],
		[Vector3(0.08, 0.9, 0.08), Color("#5e3f22"), Vector3(-0.8, 0.45, 0.32)],
		[Vector3(0.08, 0.9, 0.08), Color("#5e3f22"), Vector3(0.8, 0.45, 0.32)],
		[Vector3(2.6, 2.3, 1.6), Color("#7a6a55"), Vector3(0, 1.15, -1.3)],
		[Vector3(2.9, 0.1, 2.0), Color("#4b4e52"), Vector3(0, 2.4, -1.2)],
		[Vector3(0.5, 0.12, 0.3), Color("#c0392b"), Vector3(-0.4, 1.02, 0)],
	]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		mi.mesh = bm
		mi.material_override = _mat(part[1])
		mi.position = part[2]
		bench.add_child(mi)
	_sign("WERKBANK", BENCH_POS + Vector3(0, 2.0, 0))


func _build_particles() -> void:
	dirt = CPUParticles3D.new()
	dirt.emitting = false
	dirt.one_shot = true
	dirt.amount = 12
	dirt.lifetime = 0.9
	dirt.explosiveness = 1.0
	dirt.direction = Vector3.UP
	dirt.spread = 55.0
	dirt.initial_velocity_min = 1.5
	dirt.initial_velocity_max = 3.0
	dirt.gravity = Vector3(0, -9.8, 0)
	dirt.scale_amount_min = 0.5
	dirt.scale_amount_max = 1.4
	var pm := BoxMesh.new()
	pm.size = Vector3(0.05, 0.05, 0.05)
	var pmat := StandardMaterial3D.new()
	pmat.vertex_color_use_as_albedo = true
	pm.material = pmat
	dirt.mesh = pm
	add_child(dirt)

	# Funken für Glückstreffer und Goldader: leuchten von selbst
	sparks = dirt.duplicate() as CPUParticles3D
	var sm := BoxMesh.new()
	sm.size = Vector3(0.035, 0.035, 0.035)
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	sparks.mesh = sm
	sparks.initial_velocity_max = 4.0
	add_child(sparks)


func _build_gold_disc() -> void:
	gold_mat = StandardMaterial3D.new()
	gold_mat.albedo_color = Color(1.0, 0.81, 0.25, 0.3)
	gold_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gold_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var cm := CylinderMesh.new()
	cm.top_radius = Game.R - 0.05
	cm.bottom_radius = Game.R - 0.05
	cm.height = 0.01
	cm.radial_segments = 40
	gold_disc = MeshInstance3D.new()
	gold_disc.mesh = cm
	gold_disc.material_override = gold_mat
	gold_disc.visible = false
	add_child(gold_disc)
