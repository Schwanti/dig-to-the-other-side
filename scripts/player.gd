extends Node3D
## Spielfigur in der Ich-Perspektive: umschauen, laufen, Leiter klettern.
## Zustände: "surface" (Garten), "bottom" (Sohle des Lochs), "climb" (auf der Leiter).

signal dig_pressed
signal use_pressed
signal arrived_surface
signal arrived_bottom
signal descend_started

const LOOK_SPEED := 0.0022
const RUNG_STEP := 0.33

var state := "bottom"
var climb_dir := 0
var yaw := 0.0
var pitch := -1.0
var shake := 0.0
var input_enabled := true
var obstacles: Array = []   # [Mitte, Radius] von Dingen im Garten, durch die man nicht läuft

var cam: Camera3D
var lamp: SpotLight3D
var near_light: OmniLight3D
var tool: Node3D
var _swing := 1.0
var _rung_acc := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 5000.0
	cam.position.y = Game.EYE
	add_child(cam)

	lamp = SpotLight3D.new()
	lamp.spot_range = 22.0
	lamp.spot_angle = 38.0
	lamp.light_energy = 2.0
	lamp.light_color = Color(1.0, 0.94, 0.84)
	cam.add_child(lamp)

	near_light = OmniLight3D.new()
	near_light.omni_range = 4.0
	near_light.light_energy = 0.35
	near_light.light_color = Color(1.0, 0.89, 0.75)
	cam.add_child(near_light)

	tool = _make_tool()
	tool.position = Vector3(0.34, -0.36, -0.62)
	cam.add_child(tool)

	position = Vector3(0, 0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * LOOK_SPEED
		pitch = clampf(pitch - motion.relative.y * LOOK_SPEED, -1.55, 1.55)
	elif event.is_action_pressed("dig") or event.is_action_pressed("dig_key"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		dig_pressed.emit()
	elif event.is_action_pressed("climb"):
		toggle_climb()
	elif event.is_action_pressed("use"):
		use_pressed.emit()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if state != "climb" and input_enabled:
		var fwd := Input.get_axis("move_forward", "move_back")
		var side := Input.get_axis("move_left", "move_right")
		if fwd != 0.0 or side != 0.0:
			var dir := Vector2(side, fwd).normalized()
			var speed := (3.2 if state == "surface" else 2.0) * delta
			position.x += (dir.x * cos(yaw) + dir.y * sin(yaw)) * speed
			position.z += (dir.y * cos(yaw) - dir.x * sin(yaw)) * speed
	_keep_inside()

	match state:
		"bottom":
			position.y = -Game.depth
		"surface":
			position.y = 0.0
		"climb":
			_climb_step(delta)

	# Kamera, Wackeln beim Graben und Werkzeug-Schwung
	shake *= pow(0.001, delta)
	var bob := sin(position.y / RUNG_STEP * PI) * 0.03 if state == "climb" else 0.0
	cam.position = Vector3(randf_range(-shake, shake), Game.EYE + bob + randf_range(-shake, shake), 0.0)
	cam.rotation = Vector3(pitch, yaw, 0.0)
	_swing = minf(1.0, _swing + delta * 4.2)
	var s := sin(_swing * PI)
	tool.rotation = Vector3(-s * 0.9, 0.0, s * 0.15)
	tool.visible = state != "climb"


func _keep_inside() -> void:
	var r := Vector2(position.x, position.z).length()
	if state == "bottom" and r > Game.R - 0.35:
		var f := (Game.R - 0.35) / r
		position.x *= f
		position.z *= f
	elif state == "surface":
		if r < Game.R + 0.35:
			var f := (Game.R + 0.35) / maxf(r, 0.001)
			position.x *= f
			position.z *= f
		elif r > 22.0:
			position.x *= 22.0 / r
			position.z *= 22.0 / r
		if position.z > 8.6 and absf(position.x) < 14.6:
			position.z = 8.6   # Gartenzaun
		for o in obstacles:
			var c: Vector3 = o[0]
			var rad: float = o[1]
			var dv := Vector2(position.x - c.x, position.z - c.z)
			if dv.length() < rad and dv.length() > 0.001:
				var push := dv.normalized() * rad
				position.x = c.x + push.x
				position.z = c.z + push.y


func toggle_climb() -> void:
	match state:
		"bottom":
			start_climb(1)
		"surface":
			start_climb(-1)
			descend_started.emit()
		"climb":
			climb_dir = -climb_dir


func start_climb(dir: int) -> void:
	state = "climb"
	climb_dir = dir
	position.x = Game.R - 0.5
	position.z = 0.0
	yaw = -PI / 2.0
	pitch = 0.35 if dir > 0 else -0.35


func _climb_step(delta: float) -> void:
	var v := Game.climb_v() * (3.0 if climb_dir < 0 else 1.0)  # runter geht schneller
	var before := position.y
	position.y += climb_dir * v * delta
	_rung_acc += absf(position.y - before)
	if _rung_acc > RUNG_STEP:
		_rung_acc = 0.0
	if climb_dir > 0 and position.y >= 0.0:
		place_on_surface()
		arrived_surface.emit()
	elif climb_dir < 0 and position.y <= -Game.depth:
		state = "bottom"
		position = Vector3(Game.R - 0.7, -Game.depth, 0.0)
		yaw = PI / 2.0
		pitch = -0.7
		arrived_bottom.emit()


func place_on_surface() -> void:
	state = "surface"
	climb_dir = 0
	position = Vector3(Game.R + 1.1, 0.0, 0.3)
	yaw = -PI / 2.0
	pitch = -0.1


func do_swing() -> void:
	_swing = 0.0


## Ein einfaches Werkzeug in der Hand. Wird später gegen echte Modelle getauscht.
func _make_tool() -> Node3D:
	var g := Node3D.new()
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color("#a0763f")
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color("#9aa0a6")
	blade_mat.metallic = 0.8
	blade_mat.roughness = 0.35
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.02
	hm.bottom_radius = 0.02
	hm.height = 0.7
	handle.mesh = hm
	handle.material_override = handle_mat
	handle.position = Vector3(0, 0.12, 0.05)
	handle.rotation.x = 0.45
	g.add_child(handle)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.17, 0.006, 0.22)
	blade.mesh = bm
	blade.material_override = blade_mat
	blade.position = Vector3(0, -0.2, -0.13)
	blade.rotation.x = 0.45
	g.add_child(blade)
	return g
