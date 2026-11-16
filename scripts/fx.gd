class_name Fx
extends Node3D
## Pooled hit feedback: shard bursts, floating damage numbers, expanding rings,
## lightning segments. All pools are fixed-size so heavy fights do not allocate.

const MAX_SHARDS := 700
const NUM_POOL := 70
const RING_POOL := 24
const BOLT_POOL := 48

var s_pos := PackedVector3Array()
var s_vel := PackedVector3Array()
var s_life := PackedFloat32Array()
var s_max := PackedFloat32Array()
var s_size := PackedFloat32Array()
var s_col := PackedColorArray()
var s_count := 0
var shard_mm: MultiMeshInstance3D

var nums: Array = []
var num_i := 0
var rings: Array = []
var ring_i := 0
var bolts: Array = []
var bolt_i := 0

func _ready() -> void:
	s_pos.resize(MAX_SHARDS); s_vel.resize(MAX_SHARDS); s_life.resize(MAX_SHARDS)
	s_max.resize(MAX_SHARDS); s_size.resize(MAX_SHARDS); s_col.resize(MAX_SHARDS)
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	m.mesh = box
	m.instance_count = MAX_SHARDS
	m.visible_instance_count = 0
	shard_mm = MultiMeshInstance3D.new()
	shard_mm.multimesh = m
	shard_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shard_mm.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 60, 400))
	add_child(shard_mm)
	for i in NUM_POOL:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font_size = 30
		l.outline_size = 10
		l.outline_modulate = Color(0.15, 0.05, 0.1, 1)
		l.render_priority = 10
		l.outline_render_priority = 9
		l.visible = false
		l.set_meta("life", 0.0)
		add_child(l)
		nums.append(l)
	var ring_shader := Shader.new()
	ring_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float alpha = 1.0;
uniform float thickness = 0.12;
uniform float fill = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = smoothstep(1.0, 1.0 - thickness, r) * smoothstep(1.0 - thickness * 2.5, 1.0 - thickness, r);
	float inner = (1.0 - smoothstep(0.98, 1.0, r)) * fill;
	ALBEDO = col.rgb;
	ALPHA = clamp((edge + inner) * alpha, 0.0, 1.0);
}
"""
	for i in RING_POOL:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		q.orientation = PlaneMesh.FACE_Y
		mi.mesh = q
		var sm := ShaderMaterial.new()
		sm.shader = ring_shader
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.set_meta("life", 0.0)
		add_child(mi)
		rings.append(mi)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.75, 0.95, 1.0)
	bmat.emission_enabled = true
	bmat.emission = Color(0.5, 0.85, 1.0)
	bmat.emission_energy_multiplier = 4.0
	for i in BOLT_POOL:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.12, 0.12, 1.0)
		b.material = bmat
		mi.mesh = b
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.set_meta("life", 0.0)
		add_child(mi)
		bolts.append(mi)

func burst(p: Vector3, col: Color, n: int, power := 1.0) -> void:
	for i in n:
		if s_count >= MAX_SHARDS:
			return
		var k := s_count
		s_count += 1
		s_pos[k] = p
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.4), randf_range(-1, 1)).normalized()
		s_vel[k] = dir * randf_range(3.0, 8.0) * power
		var life := randf_range(0.35, 0.7)
		s_life[k] = life
		s_max[k] = life
		s_size[k] = randf_range(0.6, 1.3) * (0.8 + power * 0.3)
		s_col[k] = col

func dust(p: Vector3, n: int) -> void:
	for i in n:
		if s_count >= MAX_SHARDS:
			return
		var k := s_count
		s_count += 1
		s_pos[k] = p + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
		s_vel[k] = Vector3(randf_range(-2, 2), randf_range(0.5, 2.0), randf_range(-2, 2))
		s_life[k] = 0.35
		s_max[k] = 0.35
		s_size[k] = 0.8
		s_col[k] = Color(0.85, 0.9, 0.8)

func damage_number(p: Vector3, amount: float, crit: bool) -> void:
	var l: Label3D = nums[num_i]
	num_i = (num_i + 1) % NUM_POOL
	l.text = str(int(round(amount)))
	l.position = p + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	l.modulate = Color(1.0, 0.9, 0.3) if crit else Color(1, 1, 1)
	l.font_size = 46 if crit else 30
	l.visible = true
	l.set_meta("life", 0.7)
	l.set_meta("vy", 2.6 if crit else 1.8)

func ring(p: Vector3, radius: float, col: Color, dur := 0.4, fill := 0.0, thick := 0.12) -> void:
	var mi: MeshInstance3D = rings[ring_i]
	ring_i = (ring_i + 1) % RING_POOL
	mi.position = p + Vector3(0, 0.08, 0)
	mi.visible = true
	mi.set_meta("life", dur)
	mi.set_meta("dur", dur)
	mi.set_meta("r", radius)
	mi.set_meta("grow", true)
	var sm: ShaderMaterial = mi.material_override
	sm.set_shader_parameter("col", col)
	sm.set_shader_parameter("fill", fill)
	sm.set_shader_parameter("thickness", thick)

## Static telegraph disc that does not grow (boss slams).
func telegraph(p: Vector3, radius: float, dur: float) -> void:
	ring(p, radius, Color(1.0, 0.2, 0.25), dur, 0.25, 0.06)
	var mi: MeshInstance3D = rings[(ring_i - 1 + RING_POOL) % RING_POOL]
	mi.set_meta("grow", false)
	mi.scale = Vector3.ONE * radius

func bolt(a: Vector3, b: Vector3) -> void:
	# Two jagged segments per link read as lightning.
	var mid := (a + b) * 0.5 + Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.6), randf_range(-0.6, 0.6))
	_seg(a, mid)
	_seg(mid, b)

func _seg(a: Vector3, b: Vector3) -> void:
	var mi: MeshInstance3D = bolts[bolt_i]
	bolt_i = (bolt_i + 1) % BOLT_POOL
	var len := a.distance_to(b)
	if len < 0.01:
		return
	mi.visible = true
	mi.set_meta("life", 0.14)
	var t := Transform3D()
	t.origin = (a + b) * 0.5
	t = t.looking_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT)
	t.basis = t.basis.scaled(Vector3(1, 1, len))
	mi.transform = t

func _process(dt: float) -> void:
	var m := shard_mm.multimesh
	var i := 0
	while i < s_count:
		s_life[i] -= dt
		if s_life[i] <= 0.0:
			var last := s_count - 1
			s_pos[i] = s_pos[last]; s_vel[i] = s_vel[last]; s_life[i] = s_life[last]
			s_max[i] = s_max[last]; s_size[i] = s_size[last]; s_col[i] = s_col[last]
			s_count -= 1
			continue
		var v := s_vel[i]
		v.y -= 16.0 * dt
		var p := s_pos[i] + v * dt
		if p.y < 0.05:
			p.y = 0.05
			v *= 0.5
		s_vel[i] = v
		s_pos[i] = p
		var k := s_life[i] / s_max[i]
		var sz := s_size[i] * k
		m.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(k * 7.0, k * 5.0, 0)).scaled(Vector3.ONE * sz), p))
		m.set_instance_color(i, s_col[i])
		i += 1
	m.visible_instance_count = s_count
	for l in nums:
		if not l.visible:
			continue
		var life: float = l.get_meta("life") - dt
		l.set_meta("life", life)
		if life <= 0.0:
			l.visible = false
			continue
		l.position.y += float(l.get_meta("vy")) * dt
		l.modulate.a = clampf(life / 0.3, 0.0, 1.0)
	for mi in rings:
		if not mi.visible:
			continue
		var life: float = mi.get_meta("life") - dt
		mi.set_meta("life", life)
		if life <= 0.0:
			mi.visible = false
			continue
		var dur: float = mi.get_meta("dur")
		var k := 1.0 - life / dur
		var sm: ShaderMaterial = mi.material_override
		if mi.get_meta("grow"):
			var r: float = mi.get_meta("r")
			mi.scale = Vector3.ONE * maxf(0.01, r * ease(k, 0.4))
			sm.set_shader_parameter("alpha", 1.0 - k)
		else:
			sm.set_shader_parameter("alpha", 0.35 + 0.65 * k)
	for mi in bolts:
		if not mi.visible:
			continue
		var life: float = mi.get_meta("life") - dt
		mi.set_meta("life", life)
		if life <= 0.0:
			mi.visible = false
