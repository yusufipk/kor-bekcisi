class_name Pickups
extends Node3D
## XP crystals (one MultiMesh), heal fruit, magnets and treasure chests.

# Past the cap new XP folds into existing crystals, which grow and change colour.
const MAX_GEMS := 400
var g_pos := PackedVector3Array()
var g_val := PackedInt32Array()
var g_fly := PackedByteArray()
var g_spd := PackedFloat32Array()
var g_count := 0
var gem_mm: MultiMeshInstance3D
var items: Array = []    # {node, kind, p}
var chests: Array = []   # Node3D with meta
var chest_scene: Node3D = null
var beams_on := true
var pickup_combo := 0
const SCALE := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]
var combo_t := 0.0

func _ready() -> void:
	g_pos.resize(MAX_GEMS); g_val.resize(MAX_GEMS); g_fly.resize(MAX_GEMS); g_spd.resize(MAX_GEMS)
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	var sp := SphereMesh.new()
	sp.radius = 0.22
	sp.height = 0.6
	sp.radial_segments = 4
	sp.rings = 1
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
void vertex() {
	// Idle bob and spin run here, so the CPU only moves crystals in flight.
	float ph = float(INSTANCE_ID);
	float a = TIME * 2.0 + ph;
	VERTEX.xz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xz;
	VERTEX.y += sin(TIME * 3.0 + ph) * 0.08 / max(length(MODEL_MATRIX[1].xyz), 0.01);
}
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = COLOR.rgb * (1.1 + rim * 1.2);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	sp.material = mat
	m.mesh = sp
	m.instance_count = MAX_GEMS
	m.visible_instance_count = 0
	gem_mm = MultiMeshInstance3D.new()
	gem_mm.multimesh = m
	gem_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gem_mm.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 40, 400))
	add_child(gem_mm)

func gem(p: Vector3, value: int) -> void:
	if g_count >= MAX_GEMS:
		# Fold into an existing gem so XP is never lost.
		var k := randi() % g_count
		g_val[k] += value
		_draw_gem(k)
		return
	var i := g_count
	g_count += 1
	g_pos[i] = Vector3(p.x + randf_range(-0.4, 0.4), 0.35, p.z + randf_range(-0.4, 0.4))
	g_val[i] = value
	g_fly[i] = 0
	g_spd[i] = 0.0
	_draw_gem(i)
	gem_mm.multimesh.visible_instance_count = g_count

## Write one crystal's transform and colour; bigger values look bigger.
func _draw_gem(i: int) -> void:
	var v := g_val[i]
	var c := Color(1.0, 0.82, 0.25)
	var s := 1.0
	if v >= 20:
		c = Color(1.0, 0.35, 0.85); s = 1.8
	elif v >= 5:
		c = Color(0.35, 0.95, 1.0); s = 1.35
	var m := gem_mm.multimesh
	m.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), g_pos[i]))
	m.set_instance_color(i, c)

func magnet_all() -> void:
	for i in g_count:
		g_fly[i] = 1

func item(p: Vector3, kind: String) -> void:
	var n := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	if kind == "heal":
		var s := SphereMesh.new()
		s.radius = 0.38
		s.height = 0.7
		s.radial_segments = 8
		s.rings = 4
		n.mesh = s
		mat.albedo_color = Color(1.0, 0.35, 0.3)
		mat.emission = Color(1.0, 0.3, 0.25)
	else:
		var t := TorusMesh.new()
		t.inner_radius = 0.22
		t.outer_radius = 0.5
		t.rings = 12
		t.ring_segments = 6
		n.mesh = t
		n.rotation.x = PI * 0.5
		mat.albedo_color = Color(0.4, 0.9, 1.0)
		mat.emission = Color(0.3, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	n.material_override = mat
	n.position = Vector3(p.x, 0.7, p.z)
	add_child(n)
	items.append({"node": n, "kind": kind, "t": 0.0})

func spawn_chest(p: Vector3, model: Node3D) -> void:
	var root := Node3D.new()
	root.position = p
	if model:
		root.add_child(model)
	else:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4, 1.0, 1.0)
		b.mesh = bm
		b.position.y = 0.5
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.2, 0.6, 0.6)
		b.material_override = mm
		root.add_child(b)
	# A tall light beam so chests can be found from across the island.
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.7
	cm.height = 40.0
	cm.radial_segments = 10
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.position.y = 20.0
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.albedo_color = Color(1.0, 0.8, 0.3, 0.35)
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.name = "beam"
	# No beams in the boss fight: the arena belongs to the giant.
	beam.visible = beams_on
	root.add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.light_energy = 2.0
	light.omni_range = 6.0
	light.position.y = 1.5
	root.add_child(light)
	add_child(root)
	chests.append(root)

func set_beams(on: bool) -> void:
	beams_on = on
	for ch in chests:
		var b: Node3D = ch.get_node_or_null("beam")
		if b:
			b.visible = on

func update(dt: float, player) -> void:
	var g = Game.inst
	var pp: Vector3 = player.global_position
	var mr: float = g.st.magnet
	var mr2 := mr * mr
	combo_t -= dt
	if combo_t <= 0.0:
		pickup_combo = 0
	var m := gem_mm.multimesh
	var i := 0
	while i < g_count:
		var p := g_pos[i]
		var dx := pp.x - p.x
		var dz := pp.z - p.z
		var d2 := dx * dx + dz * dz
		if g_fly[i] == 0 and d2 < mr2:
			g_fly[i] = 1
		if g_fly[i] == 1:
			g_spd[i] = minf(g_spd[i] + dt * 45.0, 40.0)
			var to := (pp + Vector3(0, 0.9, 0)) - p
			var l := to.length()
			if l < 0.9 or l < g_spd[i] * dt:
				g.add_xp(g_val[i])
				pickup_combo += 1
				combo_t = 0.4
				# A streak climbs a pentatonic scale, two pickups per step.
				var step: int = SCALE[mini(pickup_combo / 2, SCALE.size() - 1)]
				Sfx.play("pickup", Vector3.INF, 0.8, 0.0, pow(2.0, step / 12.0))
				var last := g_count - 1
				g_pos[i] = g_pos[last]; g_val[i] = g_val[last]; g_fly[i] = g_fly[last]; g_spd[i] = g_spd[last]
				g_count -= 1
				if i < g_count:
					_draw_gem(i)
				continue
			p += to / l * g_spd[i] * dt
			g_pos[i] = p
			_draw_gem(i)
		i += 1
	m.visible_instance_count = g_count
	var j := 0
	while j < items.size():
		var it: Dictionary = items[j]
		var n: MeshInstance3D = it["node"]
		it["t"] += dt
		n.position.y = 0.8 + sin(it["t"] * 3.0) * 0.15
		n.rotate_y(dt * 2.0)
		var fd := Vector2(n.position.x - pp.x, n.position.z - pp.z).length()
		# Fruit and magnets drift to you from a little past the crystal reach,
		# so a player who is busy running still picks them up.
		if fd < mr + 3.0 and fd > 0.01:
			var pull := Vector3(pp.x - n.position.x, 0, pp.z - n.position.z) / fd
			n.position += pull * minf(fd, dt * 9.0)
		var near: bool = fd < 1.4 + (mr * 0.3)
		if near:
			if it["kind"] == "heal":
				player.heal(35.0)
				g.fx.burst(pp + Vector3(0, 1, 0), Color(1.0, 0.4, 0.4), 12, 1.0)
				g.fx.float_text(g.player.global_position + Vector3(0, 2.4, 0), "+35", Color(0.5, 1.0, 0.55))
			else:
				magnet_all()
				g.toast("Bütün kristaller sana geliyor!")
			Sfx.play("pickup", Vector3.INF, 1.0, 0.0)
			n.queue_free()
			items.remove_at(j)
			continue
		if it["t"] > 45.0:
			n.queue_free()
			items.remove_at(j)
			continue
		j += 1
	var k := 0
	while k < chests.size():
		var ch: Node3D = chests[k]
		if Vector2(ch.position.x - pp.x, ch.position.z - pp.z).length() < 2.0:
			g.open_chest(ch.position)
			ch.queue_free()
			chests.remove_at(k)
			continue
		k += 1
