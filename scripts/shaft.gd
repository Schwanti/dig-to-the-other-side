extends Node3D
## Das Loch: eine Wand pro Gesteinsschicht, die Sohle und die Leiter.
## Die Wände werden nur in der Höhe skaliert. Weil die Texturen in Weltkoordinaten
## liegen (triplanar), verzerren sie dabei nicht und wandern nicht mit.

const RUNG_STEP := 0.33
const LADDER_TOP := 1.2

var walls: Array[MeshInstance3D] = []
var layer_mats: Array[StandardMaterial3D] = []
var floor_mesh: MeshInstance3D
var rails: Array[MeshInstance3D] = []
var rungs: MultiMeshInstance3D
var rung_count := -1


func _ready() -> void:
	for i in Game.LAYERS.size():
		var mat := _rock_material(Game.LAYERS[i], i)
		layer_mats.append(mat)
		var cyl := CylinderMesh.new()
		cyl.top_radius = Game.R
		cyl.bottom_radius = Game.R
		cyl.height = 1.0
		cyl.radial_segments = 48
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false
		var wall := MeshInstance3D.new()
		wall.mesh = cyl
		wall.material_override = mat
		wall.visible = false
		add_child(wall)
		walls.append(wall)

	var fc := CylinderMesh.new()
	fc.top_radius = Game.R + 0.02
	fc.bottom_radius = Game.R + 0.02
	fc.height = 0.1
	fc.radial_segments = 48
	floor_mesh = MeshInstance3D.new()
	floor_mesh.mesh = fc
	add_child(floor_mesh)

	_build_ladder()


## Erzeugt ein Gesteinsmaterial aus Rauschen in den Farben der Schicht.
func _rock_material(L: Dictionary, i: int) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = 11 + i * 17
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	var grad := Gradient.new()
	grad.set_color(0, (L["base"] as Color).darkened(0.3))
	grad.set_color(1, L["spot"])
	grad.add_point(0.55, L["base"])
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	var nrm := NoiseTexture2D.new()
	nrm.width = 256
	nrm.height = 256
	nrm.seamless = true
	nrm.noise = noise
	nrm.as_normal_map = true
	nrm.bump_strength = 6.0
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.normal_enabled = true
	mat.normal_texture = nrm
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.4, 0.4, 0.4)
	return mat


func _build_ladder() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#7a5530")
	wood.roughness = 0.9
	for z in [-0.28, 0.28]:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 1.0, 0.06)
		var rail := MeshInstance3D.new()
		rail.mesh = bm
		rail.material_override = wood
		rail.position = Vector3(Game.R - 0.08, 0, z)
		add_child(rail)
		rails.append(rail)
	var rung_mesh := BoxMesh.new()
	rung_mesh.size = Vector3(0.05, 0.05, 0.56)
	rung_mesh.material = wood
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rung_mesh
	rungs = MultiMeshInstance3D.new()
	rungs.multimesh = mm
	add_child(rungs)


## Passt Wände, Sohle und Leiter an die aktuelle Tiefe an.
func update_depth(d: float) -> void:
	var bottom := d + 0.02
	for i in walls.size():
		var a := Game.layer_from(i)
		var b := minf(float(Game.LAYERS[i]["to"]), bottom)
		var wall := walls[i]
		if b <= a + 0.0001:
			wall.visible = false
			continue
		wall.visible = true
		wall.scale = Vector3(1.0, b - a, 1.0)
		wall.position.y = -(a + b) / 2.0
	floor_mesh.position.y = -d - 0.05
	floor_mesh.material_override = layer_mats[Game.layer_idx(maxf(0.0, d - 0.000001))]
	_update_ladder(d)


func _update_ladder(d: float) -> void:
	var h := d + LADDER_TOP
	for rail in rails:
		rail.scale = Vector3(1.0, h, 1.0)
		rail.position.y = LADDER_TOP - h / 2.0
	var n := int(h / RUNG_STEP)
	if n == rung_count:
		return
	rung_count = n
	var mm := rungs.multimesh
	mm.instance_count = n
	for j in n:
		mm.set_instance_transform(j, Transform3D(Basis(), Vector3(Game.R - 0.08, LADDER_TOP - 0.15 - j * RUNG_STEP, 0)))


func set_ladder_visible(v: bool) -> void:
	for rail in rails:
		rail.visible = v
	rungs.visible = v
