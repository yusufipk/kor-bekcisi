class_name Pickups
extends Node3D
## XP crystals (one MultiMesh), heal fruit, magnets and treasure chests.

const MAX_GEMS := 900
var g_pos := PackedVector3Array()
var g_val := PackedInt32Array()
var g_fly := PackedByteArray()
var g_spd := PackedFloat32Array()
var g_count := 0
var gem_mm: MultiMeshInstance3D
var items: Array = []    # {node, kind, p}
var chests: Array = []   # Node3D with meta
var chest_scene: Node3D = null
var pickup_combo := 0
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
		return
	var i := g_count
	g_count += 1
	g_pos[i] = Vector3(p.x + randf_range(-0.4, 0.4), 0.35, p.z + randf_range(-0.4, 0.4))
	g_val[i] = value
	g_fly[i] = 0
	g_spd[i] = 0.0

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
	root.add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.light_energy = 2.0
	light.omni_range = 6.0
	light.position.y = 1.5
	root.add_child(light)
	add_child(root)
	chests.append(root)

func update(dt: float, player) -> void:
	var g = Game.inst
	var pp: Vector3 = player.global_position
	var mr: float = g.st.magnet
	var mr2 := mr * mr
	combo_t -= dt
	if combo_t <= 0.0:
		pickup_combo = 0
	var m := gem_mm.multimesh
	var t := Time.get_ticks_msec() * 0.001
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
				Sfx.play("pickup", Vector3.INF, 0.8, 0.0)
				var pl: AudioStreamPlayer = Sfx.players[(Sfx.voice_i - 1 + Sfx.VOICES) % Sfx.VOICES]
				pl.pitch_scale = 1.0 + minf(pickup_combo, 24) * 0.035
				var last := g_count - 1
				g_pos[i] = g_pos[last]; g_val[i] = g_val[last]; g_fly[i] = g_fly[last]; g_spd[i] = g_spd[last]
				g_count -= 1
				continue
			p += to / l * g_spd[i] * dt
			g_pos[i] = p
		var v := g_val[i]
		var c := Color(1.0, 0.82, 0.25)
		var s := 1.0
		if v >= 20:
			c = Color(1.0, 0.35, 0.85); s = 1.8
		elif v >= 5:
			c = Color(0.35, 0.95, 1.0); s = 1.35
		var bob := sin(t * 3.0 + i) * 0.08
		m.set_instance_transform(i, Transform3D(Basis(Vector3.UP, t * 2.0 + i).scaled(Vector3.ONE * s), p + Vector3(0, bob, 0)))
		m.set_instance_color(i, c)
		i += 1
	m.visible_instance_count = g_count
	var j := 0
	while j < items.size():
		var it: Dictionary = items[j]
		var n: MeshInstance3D = it["node"]
		it["t"] += dt
		n.position.y = 0.8 + sin(it["t"] * 3.0) * 0.15
		n.rotate_y(dt * 2.0)
		var near: bool = Vector2(n.position.x - pp.x, n.position.z - pp.z).length() < 1.4 + (mr * 0.3)
		if near:
			if it["kind"] == "heal":
				player.heal(35.0)
				g.fx.burst(pp + Vector3(0, 1, 0), Color(1.0, 0.4, 0.4), 12, 1.0)
				g.toast("+35 can")
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
