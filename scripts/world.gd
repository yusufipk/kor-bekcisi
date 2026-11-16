class_name World
extends Node3D
## Builds the floating island: ground, cliffs, sky, light, props and obstacles.

var island_radius := 60.0
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var obstacles: Array = []        # [Vector2, radius] for enemies
var shrine_spots: Array = []
var crystal_spots: Array = []    # free spots where amber crystals can grow
var rng := RandomNumberGenerator.new()
var bright := 1.0
var night := 0.0                 # 0 day .. 1 deep night, read by Game for lights and glow
var ember := 0.0                 # 0 .. 1 red ash sky of the boss
var particles: GPUParticles3D    # fireflies at night, embers in the boss fight
var _fx_mat: ParticleProcessMaterial
var _fx_draw: StandardMaterial3D

## Time of day keyed to the run clock: afternoon, sunset, dusk, night, ash night.
## Each key: t, sky top, horizon, below, sun colour, sun energy, sun pitch,
## moon energy, ambient colour, ambient energy, stars, night, ember.
const KEYS := [
	[0.0,   Color(0.36, 0.47, 0.86), Color(1.0, 0.80, 0.64), Color(0.55, 0.45, 0.66), Color(1.0, 0.88, 0.72), 1.5, -46.0, 0.0, Color(0.85, 0.82, 0.95), 0.62, 0.0, 0.0, 0.0],
	[200.0, Color(0.42, 0.40, 0.78), Color(1.0, 0.66, 0.48), Color(0.55, 0.40, 0.60), Color(1.0, 0.76, 0.52), 1.4, -26.0, 0.0, Color(0.95, 0.78, 0.82), 0.6, 0.0, 0.0, 0.0],
	[330.0, Color(0.30, 0.22, 0.52), Color(1.0, 0.46, 0.30), Color(0.45, 0.28, 0.45), Color(1.0, 0.55, 0.32), 1.15, -9.0, 0.0, Color(0.95, 0.72, 0.58), 0.55, 0.05, 0.15, 0.0],
	[420.0, Color(0.10, 0.10, 0.28), Color(0.52, 0.30, 0.46), Color(0.20, 0.15, 0.30), Color(0.9, 0.45, 0.35), 0.25, -2.0, 0.35, Color(0.55, 0.55, 0.85), 0.5, 0.5, 0.6, 0.0],
	[500.0, Color(0.03, 0.04, 0.13), Color(0.16, 0.16, 0.36), Color(0.07, 0.07, 0.16), Color(0.9, 0.45, 0.35), 0.0, -2.0, 0.6, Color(0.42, 0.48, 0.88), 0.44, 1.0, 1.0, 0.0],
	[575.0, Color(0.03, 0.04, 0.13), Color(0.16, 0.16, 0.36), Color(0.07, 0.07, 0.16), Color(0.9, 0.45, 0.35), 0.0, -2.0, 0.6, Color(0.42, 0.48, 0.88), 0.44, 1.0, 1.0, 0.0],
	[600.0, Color(0.10, 0.02, 0.06), Color(0.46, 0.10, 0.12), Color(0.16, 0.04, 0.08), Color(1.0, 0.35, 0.25), 0.0, -2.0, 0.5, Color(0.68, 0.48, 0.58), 0.52, 0.4, 1.0, 1.0],
]
## Sunrise after the boss falls.
const DAWN := [0.0, Color(0.40, 0.52, 0.88), Color(1.0, 0.72, 0.52), Color(0.55, 0.42, 0.62), Color(1.0, 0.8, 0.6), 1.6, -14.0, 0.0, Color(0.95, 0.82, 0.85), 0.65, 0.0, 0.0, 0.0]

const M := "res://art/models/"

static var _globals_added := false

func build() -> void:
	rng.seed = 7331
	_environment()
	_ground()
	_grass()
	_props()
	_paths()
	_far_islands()
	_cloud_sea()
	_particles()
	update_time(0.0, 0.0)

var fade_shader: Shader

func _environment() -> void:
	# Globals survive scene reloads (and so does this static), so add them once.
	if not _globals_added:
		_globals_added = true
		RenderingServer.global_shader_parameter_add("player_screen", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(0.5, 0.5))
		RenderingServer.global_shader_parameter_add("player_depth", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 12.0)
		RenderingServer.global_shader_parameter_add("night", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	fade_shader = Shader.new()
	fade_shader.code = """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
global uniform vec2 player_screen;
global uniform float player_depth;
void fragment() {
	ALBEDO = texture(tex, UV).rgb * tint.rgb;
	ROUGHNESS = 0.9;
	// Dither out props that stand between the camera and the hero.
	float depth = -VERTEX.z;
	vec2 d = (SCREEN_UV - player_screen) * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	float r = length(d);
	float fade = (1.0 - smoothstep(0.12, 0.3, r)) * step(depth, player_depth - 1.5);
	// Anything right in front of the lens thins out too, so a trunk never fills the screen.
	fade = max(fade, 1.0 - smoothstep(3.5, 7.0, depth));
	float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (fade * 0.85 > n) discard;
}
"""
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var ssh := Shader.new()
	ssh.code = """
shader_type sky;
uniform vec3 top_col : source_color = vec3(0.36, 0.47, 0.86);
uniform vec3 hor_col : source_color = vec3(1.0, 0.8, 0.64);
uniform vec3 bot_col : source_color = vec3(0.55, 0.45, 0.66);
uniform vec3 sun_col : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform float sun_vis = 1.0;
uniform vec3 moon_dir = vec3(-0.4, 0.55, 0.7);
uniform float moon_vis = 0.0;
uniform float stars = 0.0;
uniform float ember = 0.0;
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 c = y > 0.0 ? mix(hor_col, top_col, pow(clamp(y, 0.0, 1.0), 0.55)) : mix(hor_col, bot_col, pow(clamp(-y * 3.0, 0.0, 1.0), 0.6));
	float sd = dot(d, normalize(sun_dir));
	c += sun_col * sun_vis * (smoothstep(0.9975, 0.9985, sd) * 5.0 + pow(max(sd, 0.0), 10.0) * 0.45);
	float md = dot(d, normalize(moon_dir));
	c += vec3(0.85, 0.9, 1.0) * moon_vis * (smoothstep(0.9988, 0.9993, md) * 2.5 + pow(max(md, 0.0), 60.0) * 0.3);
	if (stars > 0.0 && y > 0.0) {
		vec3 g = floor(d * 260.0);
		float h = hash(g);
		float tw = 0.6 + 0.4 * sin(TIME * 2.0 + h * 90.0);
		c += vec3(0.9, 0.92, 1.0) * step(0.9972, h) * tw * stars * smoothstep(0.02, 0.3, y) * 1.4;
	}
	// Ash night: slow red veils across the sky.
	if (ember > 0.0) {
		float v = sin(d.x * 6.0 + TIME * 0.3) * sin(d.z * 5.0 - TIME * 0.2) * 0.5 + 0.5;
		c += vec3(0.5, 0.08, 0.05) * ember * v * smoothstep(-0.1, 0.4, y) * 0.5;
	}
	COLOR = c;
}
"""
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = ssh
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Ambient comes from an explicit colour, so night stays readable (no black-out).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.82, 0.95)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.6, 0.78)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.4
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.0
	moon.rotation_degrees = Vector3(-50, 145, 0)
	moon.shadow_enabled = false
	add_child(moon)
	apply_brightness(Settings.brightness)

func apply_brightness(b: float) -> void:
	bright = b
	env.adjustment_brightness = b

## Blend the sky, lights and ambient for run time t. dawn_k (0..1) pulls
## everything toward sunrise after the boss falls.
func update_time(t: float, dawn_k: float) -> void:
	var a: Array = KEYS[0]
	var b: Array = KEYS[0]
	var k := 0.0
	for i in KEYS.size():
		if t >= KEYS[i][0]:
			a = KEYS[i]
			b = KEYS[mini(i + 1, KEYS.size() - 1)]
	if b[0] > a[0]:
		k = clampf((t - a[0]) / (b[0] - a[0]), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
	var v: Array = []
	for j in a.size():
		if a[j] is Color:
			v.append((a[j] as Color).lerp(b[j], k))
		else:
			v.append(lerpf(a[j], b[j], k))
	if dawn_k > 0.0:
		for j in v.size():
			if v[j] is Color:
				v[j] = (v[j] as Color).lerp(DAWN[j], dawn_k)
			else:
				v[j] = lerpf(v[j], DAWN[j], dawn_k)
	sky_mat.set_shader_parameter("top_col", v[1])
	sky_mat.set_shader_parameter("hor_col", v[2])
	sky_mat.set_shader_parameter("bot_col", v[3])
	sky_mat.set_shader_parameter("sun_col", v[4])
	sun.light_color = v[4]
	sun.light_energy = v[5]
	sun.visible = v[5] > 0.01
	sun.rotation_degrees = Vector3(v[6], -35.0, 0.0)
	sky_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
	sky_mat.set_shader_parameter("sun_vis", clampf(v[5], 0.0, 1.0))
	moon.light_energy = v[7]
	moon.visible = v[7] > 0.01
	moon.light_color = Color(0.6, 0.7, 1.0).lerp(Color(1.0, 0.45, 0.4), v[12])
	sky_mat.set_shader_parameter("moon_dir", moon.global_transform.basis.z)
	sky_mat.set_shader_parameter("moon_vis", clampf(v[7] * 1.6, 0.0, 1.0))
	env.ambient_light_color = v[8]
	env.ambient_light_energy = v[9] * bright
	sky_mat.set_shader_parameter("stars", v[10])
	sky_mat.set_shader_parameter("ember", v[12])
	env.fog_light_color = (v[2] as Color).lerp(v[3], 0.4)
	night = v[11]
	ember = v[12]
	RenderingServer.global_shader_parameter_set("night", night)
	_update_particles()

func _ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = island_radius + 6.0
	cyl.height = 8.0
	cs.shape = cyl
	cs.position.y = -4.0
	body.add_child(cs)
	add_child(body)
	var top := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = island_radius + 2.0
	cm.bottom_radius = island_radius - 6.0
	cm.height = 6.0
	cm.radial_segments = 48
	cm.rings = 1
	top.mesh = cm
	top.position.y = -3.0
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back;
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (wp.y > -0.2) {
		// Faceted grass: hash per triangle-sized cell reads as low-poly facets.
		vec2 cell = floor(wp.xz / 1.6 + vec2(floor(wp.z / 1.6) * 0.5, 0.0));
		float f = h(cell) * 0.025;
		float big = n(wp.xz * 0.05);
		vec3 a = vec3(0.075, 0.26, 0.12);
		vec3 b = vec3(0.15, 0.40, 0.13);
		ALBEDO = mix(a, b, big) + f;
		ROUGHNESS = 0.95;
	} else {
		float band = n(vec2(atan(wp.z, wp.x) * 8.0, wp.y * 0.5));
		ALBEDO = mix(vec3(0.15, 0.11, 0.15), vec3(0.26, 0.19, 0.22), band);
		ROUGHNESS = 1.0;
	}
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	top.material_override = mat
	add_child(top)
	var under := MeshInstance3D.new()
	var um := CylinderMesh.new()
	um.top_radius = island_radius - 6.0
	um.bottom_radius = 4.0
	um.height = 28.0
	um.radial_segments = 14
	um.rings = 3
	under.mesh = um
	under.position.y = -20.0
	var umat := StandardMaterial3D.new()
	umat.albedo_color = Color(0.45, 0.37, 0.45)
	umat.roughness = 1.0
	under.material_override = umat
	add_child(under)

func _grass() -> void:
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	var pm := PrismMesh.new()
	pm.size = Vector3(0.18, 0.55, 0.05)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.material = mat
	m.mesh = pm
	var n := 3200
	m.instance_count = n
	for i in n:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (island_radius - 1.0)
		var p := Vector3(cos(a) * r, 0.22, sin(a) * r)
		var s := rng.randf_range(0.7, 1.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.25, 0.25)).scaled(Vector3(s, s, s))
		m.set_instance_transform(i, Transform3D(b, p * Vector3(1, s, 1)))
		var g := rng.randf_range(0.0, 1.0)
		m.set_instance_color(i, Color(0.28, 0.5, 0.3).lerp(Color(0.5, 0.72, 0.38), g))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Pale stepping stones and flowers
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_colors = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.7
	cyl.height = 0.12
	cyl.radial_segments = 6
	cyl.rings = 1
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.vertex_color_is_srgb = true
	smat.roughness = 1.0
	cyl.material = smat
	sm.mesh = cyl
	sm.instance_count = 120
	for i in 120:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (island_radius - 2.0)
		var s := rng.randf_range(0.5, 1.4)
		sm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1, s * rng.randf_range(0.6, 1.0))), Vector3(cos(a) * r, 0.03, sin(a) * r)))
		sm.set_instance_color(i, Color(0.8, 0.8, 0.78) if i < 90 else Color(1.0, 0.95, 0.85))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = sm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)

func _free_spot(min_center: float, min_gap: float) -> Vector3:
	for tries in 60:
		var a := rng.randf() * TAU
		var r := rng.randf_range(min_center, island_radius - 5.0)
		var p := Vector2(cos(a) * r, sin(a) * r)
		var ok := true
		for o in obstacles:
			if p.distance_to(o[0]) < o[1] + min_gap:
				ok = false
				break
		if ok:
			return Vector3(p.x, 0, p.y)
	return Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30))

func _add_obstacle(node: Node3D, p: Vector3, r: float, h: float) -> void:
	node.position = p
	add_child(node)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	body.position = p
	add_child(body)
	obstacles.append([Vector2(p.x, p.z), r])

func _props() -> void:
	# The first lantern stands in view of the start (the camera looks down -Z), so
	# a new player lights it in the first minute; the rest ring the island.
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		var r := 34.0 + (i % 2) * 8.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if i == 0:
			p = Vector3(3.0, 0, -13.0)
		shrine_spots.append(p)
		obstacles.append([Vector2(p.x, p.z), 0.9])
	for i in 22:
		var p := _free_spot(9.0, 4.0)
		var h := rng.randf_range(5.0, 7.5)
		var t := Models.prop(M + "agac.glb", h)
		if t == null:
			t = _placeholder_tree(h)
		else:
			apply_fade(t)
		t.rotation.y = rng.randf() * TAU
		_add_obstacle(t, p, 0.7, 3.0)
	for i in 26:
		var p := _free_spot(7.0, 3.0)
		var h := rng.randf_range(1.2, 2.8)
		var k := Models.prop(M + "kaya.glb", h)
		if k == null:
			k = _placeholder_rock(h)
		else:
			apply_fade(k)
		k.rotation.y = rng.randf() * TAU
		_add_obstacle(k, p, h * 0.75, h)
	# Ruins from the style frame: arches you can run through, broken columns.
	for i in 6:
		var p := _free_spot(12.0, 6.0)
		var arch := Models.prop(M + "kemer.glb", 5.2)
		if arch == null:
			break
		apply_fade(arch)
		var yaw := rng.randf() * TAU
		arch.rotation.y = yaw
		arch.position = p
		add_child(arch)
		# Two legs block, the opening between them stays free.
		var side := Vector3(cos(yaw), 0, -sin(yaw)) * 1.55
		for sgn in [-1.0, 1.0]:
			var q: Vector3 = p + side * sgn
			_leg_obstacle(q, 0.75, 5.0)
	for i in 8:
		var p := _free_spot(10.0, 4.0)
		var ru := Models.prop(M + "sutun.glb", rng.randf_range(3.4, 4.6))
		if ru == null:
			break
		apply_fade(ru)
		ru.rotation.y = rng.randf() * TAU
		_add_obstacle(ru, p, 1.4, 3.0)
	for i in 14:
		crystal_spots.append(_free_spot(8.0, 3.0))

func _leg_obstacle(p: Vector3, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	body.position = p
	add_child(body)
	obstacles.append([Vector2(p.x, p.z), r])

## Flagstone paths from the centre to every lantern, flowers along the edges.
func _paths() -> void:
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_colors = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.62
	cyl.bottom_radius = 0.7
	cyl.height = 0.14
	cyl.radial_segments = 6
	cyl.rings = 1
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.vertex_color_is_srgb = true
	smat.roughness = 1.0
	cyl.material = smat
	sm.mesh = cyl
	var slabs: Array = []
	for sp: Vector3 in shrine_spots:
		var end := Vector3(sp.x, 0, sp.z)
		var dist := end.length()
		var dir := end / dist
		var perp := Vector3(-dir.z, 0, dir.x)
		var d := 4.0
		while d < dist - 2.5:
			var bend: float = sin(d * 0.12 + sp.x) * 2.2
			for side: float in [-0.75, 0.75]:
				var q: Vector3 = dir * d + perp * (bend + side + rng.randf_range(-0.2, 0.2))
				slabs.append(q)
			d += 1.5
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.use_colors = true
	var fl := SphereMesh.new()
	fl.radius = 0.11
	fl.height = 0.12
	fl.radial_segments = 5
	fl.rings = 2
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.vertex_color_is_srgb = true
	fmat.emission_enabled = true
	fmat.emission = Color(0.5, 0.45, 0.3)
	fmat.emission_energy_multiplier = 0.3
	fl.material = fmat
	fm.mesh = fl
	var flowers: Array = []
	for q in slabs:
		if rng.randf() < 0.55:
			flowers.append(q + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.8, 1.8)))
	for i in 500:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (island_radius - 2.0)
		flowers.append(Vector3(cos(a) * r, 0, sin(a) * r))
	sm.instance_count = slabs.size()
	for i in slabs.size():
		var s := rng.randf_range(0.85, 1.15)
		sm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1, s)), slabs[i] + Vector3(0, 0.04, 0)))
		sm.set_instance_color(i, Color(0.82, 0.8, 0.78).lerp(Color(0.7, 0.68, 0.72), rng.randf()))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = sm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)
	fm.instance_count = flowers.size()
	var cols := [Color(1, 1, 1), Color(1.0, 0.92, 0.5), Color(1.0, 0.75, 0.85)]
	for i in flowers.size():
		fm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), flowers[i] + Vector3(0, 0.3, 0)))
		fm.set_instance_color(i, cols[i % 3])
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = fm
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmi)

## A soft sea of clouds under the island, the way the style frame has it.
func _cloud_sea() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	mi.mesh = pm
	mi.position.y = -38.0
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
global uniform float night;
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * 0.012 + vec2(TIME * 0.004, TIME * 0.002);
	float c = n(p) * 0.55 + n(p * 2.3) * 0.3 + n(p * 5.1) * 0.15;
	float d = length(wp.xz);
	vec3 day = mix(vec3(0.95, 0.72, 0.75), vec3(1.0, 0.9, 0.85), c);
	vec3 nite = mix(vec3(0.08, 0.08, 0.2), vec3(0.2, 0.2, 0.36), c);
	ALBEDO = mix(day, nite, night);
	ALPHA = smoothstep(0.35, 0.7, c) * (1.0 - smoothstep(380.0, 680.0, d)) * 0.9;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Fireflies drift around the hero at night; in the boss fight they turn to embers.
func _particles() -> void:
	particles = GPUParticles3D.new()
	particles.amount = 160
	particles.lifetime = 5.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 30, 80))
	_fx_mat = ParticleProcessMaterial.new()
	_fx_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_fx_mat.emission_box_extents = Vector3(24, 2, 24)
	_fx_mat.direction = Vector3(0, 1, 0)
	_fx_mat.spread = 180.0
	_fx_mat.initial_velocity_min = 0.2
	_fx_mat.initial_velocity_max = 0.8
	_fx_mat.gravity = Vector3(0, 0.15, 0)
	_fx_mat.turbulence_enabled = true
	_fx_mat.turbulence_noise_strength = 0.6
	particles.process_material = _fx_mat
	var q := SphereMesh.new()
	q.radius = 0.05
	q.height = 0.1
	q.radial_segments = 6
	q.rings = 3
	_fx_draw = StandardMaterial3D.new()
	_fx_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fx_draw.albedo_color = Color(0.75, 1.0, 0.55)
	_fx_draw.emission_enabled = true
	_fx_draw.emission = Color(0.6, 1.0, 0.45)
	_fx_draw.emission_energy_multiplier = 4.0
	q.material = _fx_draw
	particles.draw_pass_1 = q
	particles.emitting = false
	add_child(particles)

func _update_particles() -> void:
	if particles == null:
		return
	var on := night > 0.35 or ember > 0.1
	particles.emitting = on
	if ember > 0.1:
		_fx_draw.albedo_color = Color(1.0, 0.45, 0.2)
		_fx_draw.emission = Color(1.0, 0.35, 0.1)
		_fx_mat.gravity = Vector3(0, 1.2, 0)
		particles.amount_ratio = 1.0
	else:
		_fx_draw.albedo_color = Color(0.75, 1.0, 0.55)
		_fx_draw.emission = Color(0.6, 1.0, 0.45)
		_fx_mat.gravity = Vector3(0, 0.15, 0)
		particles.amount_ratio = 0.6

## Keep the particle box centred on the hero.
func follow(p: Vector3) -> void:
	if particles:
		# Above head height, so they never read as crystals on the ground.
		particles.global_position = Vector3(p.x, 4.0, p.z)

## Swap imported materials for the occlusion-fade shader, keeping the texture.
func apply_fade(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for si in mi.mesh.get_surface_count():
			var src = mi.get_active_material(si)
			var sm := ShaderMaterial.new()
			sm.shader = fade_shader
			if src is BaseMaterial3D and src.albedo_texture:
				sm.set_shader_parameter("tex", src.albedo_texture)
			mi.set_surface_override_material(si, sm)
	for c in n.get_children():
		apply_fade(c)

func _far_islands() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.45, 0.6)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.45, 0.62, 0.48)
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf() * 0.3
		var d := rng.randf_range(130, 220)
		var r := rng.randf_range(8, 22)
		var y := rng.randf_range(-25, 25)
		var top := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r * 0.85
		cm.height = 2.0
		cm.radial_segments = 9
		top.mesh = cm
		top.material_override = gmat
		top.position = Vector3(cos(a) * d, y, sin(a) * d)
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(top)
		var under := MeshInstance3D.new()
		var um := CylinderMesh.new()
		um.top_radius = r * 0.85
		um.bottom_radius = 1.0
		um.height = r * 1.4
		um.radial_segments = 7
		under.mesh = um
		under.material_override = mat
		under.position = top.position - Vector3(0, r * 0.7 + 1.0, 0)
		under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(under)
		# Dress the far islands: trees and ruins on top, a waterfall off the edge.
		var deco := ["agac.glb", "kemer.glb", "sutun.glb", "agac.glb"]
		for k in 2 + i % 2:
			var pr := Models.prop(M + deco[(i + k) % deco.size()], r * rng.randf_range(0.35, 0.6))
			if pr == null:
				continue
			var ang := rng.randf() * TAU
			pr.position = top.position + Vector3(cos(ang) * r * 0.45, 1.0, sin(ang) * r * 0.45)
			pr.rotation.y = rng.randf() * TAU
			add_child(pr)
		if i % 3 != 1:
			_waterfall(top.position, r, a + PI)

func _waterfall(island: Vector3, r: float, toward: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var h := r * 2.6
	q.size = Vector2(r * 0.22, h)
	mi.mesh = q
	var dir := Vector3(cos(toward), 0, sin(toward))
	mi.position = island + dir * (r * 0.9) + Vector3(0, -h * 0.5 + 0.8, 0)
	mi.rotation.y = -toward + PI * 0.5
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
global uniform float night;
void fragment() {
	float streak = 0.6 + 0.4 * sin(UV.x * 40.0 + sin(UV.x * 7.0) * 3.0);
	float flow = fract(UV.y * 3.0 - TIME * 0.9 + sin(UV.x * 23.0) * 0.2);
	vec3 c = mix(vec3(0.75, 0.9, 1.0), vec3(1.0), flow * streak);
	ALBEDO = c * mix(1.0, 0.35, night);
	ALPHA = (0.55 + 0.35 * flow) * smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x) * smoothstep(1.0, 0.55, UV.y);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _placeholder_tree(h: float) -> Node3D:
	var n := Node3D.new()
	var trunk := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.25
	c.bottom_radius = 0.4
	c.height = h * 0.5
	trunk.mesh = c
	trunk.position.y = h * 0.25
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.5, 0.33, 0.2)
	trunk.material_override = tm
	n.add_child(trunk)
	var crown := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = h * 0.3
	s.height = h * 0.55
	s.radial_segments = 8
	s.rings = 4
	crown.mesh = s
	crown.position.y = h * 0.68
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.95, 0.6, 0.2)
	crown.material_override = cmat
	n.add_child(crown)
	return n

func _placeholder_rock(h: float) -> Node3D:
	var n := Node3D.new()
	var r := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = h * 0.6
	s.height = h
	s.radial_segments = 6
	s.rings = 3
	r.mesh = s
	r.position.y = h * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.76, 0.74)
	r.material_override = m
	n.add_child(r)
	return n
