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

var cooldown := 0.0
var warned := 0
var save_timer := 0.0


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
	bench_ui.closed.connect(func(): player.input_enabled = true)

	if Game.load_game() and Game.depth > 0.05:
		player.place_on_surface()
		Game.toast.emit("Spielstand geladen: %s tief, %s in der Kasse." % [Game.fmt_depth(Game.depth), Game.fmt_eur(Game.eur)], "big")
	else:
		Game.toast.emit("Grab los! Klick zum Graben. Ist der Eimer voll, kletterst du mit F hoch.", "big")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	cooldown -= delta
	# Presslufthammer: gedrückt halten hämmert von selbst
	if Game.lv["tool"] == 3 and Input.is_action_pressed("dig") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_on_dig()

	_update_lamp(delta)
	shaft.update_depth(Game.depth)
	_update_light()

	var zone := Game.return_zone(player.position.y, player.state == "surface" or player.position.y > -1.0)
	var p := _prompt(zone)
	hud.refresh(zone, p[0], p[1])

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
	var room := (Game.cap_kg() - Game.load_kg) / Game.KG_PER_M
	if room <= 0.000001:
		cooldown = 1.0
		Game.toast.emit("Der Eimer ist voll. Ab nach oben mit F!", "warn")
		return
	cooldown = COOLDOWN[Game.lv["tool"]]
	var r := Game.dig(0.03 * Game.tier("tool"), room)
	Game.load_kg += r["kg"]
	Game.load_val += r["val"]
	player.do_swing()
	player.shake = 0.02
	var L := Game.current_layer()
	dirt.global_position = _aim_point()
	dirt.color = L["spot"]
	dirt.restart()
	hud.show_gain("+" + Game.fmt_len(r["m"]))
	if Game.load_kg >= Game.cap_kg() - 0.000001:
		Game.toast.emit("Eimer voll! Ab nach oben mit F.", "warn")


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
	Game.sell()
	Game.batt = Game.lamp_max()
	warned = 0


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
	Game.batt = Game.lamp_max()
	warned = 0
	player.place_on_surface()
	Game.toast.emit("Licht aus! Die Nachbarskinder haben dich rausgezogen. Der Eimer ist weg.", "warn")
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
