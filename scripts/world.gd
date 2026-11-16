class_name World
extends Node3D
## Builds the floating island: ground, cliffs, sky, light, props and obstacles.

var island_radius := 60.0
var env: Environment
var sun: DirectionalLight3D
var obstacles: Array = []        # [Vector2, radius] for enemies
var shrine_spots: Array = []
var rng := RandomNumberGenerator.new()

const M := "res://art/models/"

func build() -> void:
	rng.seed = 7331
	_environment()
	_ground()
	_grass()
	_props()
	_far_islands()

var fade_shader: Shader

func _environment() -> void:
	RenderingServer.global_shader_parameter_add("player_screen", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(0.5, 0.5))
	RenderingServer.global_shader_parameter_add("player_depth", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 12.0)
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
	float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (fade * 0.85 > n) discard;
}
"""
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.55, 0.5, 0.82)
	sm.sky_horizon_color = Color(1.0, 0.72, 0.6)
	sm.ground_horizon_color = Color(0.95, 0.68, 0.62)
	sm.ground_bottom_color = Color(0.42, 0.36, 0.6)
	sm.sun_angle_max = 20.0
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
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
	apply_brightness(Settings.brightness)

func apply_brightness(b: float) -> void:
	env.adjustment_brightness = b
	env.ambient_light_energy = 0.55 * b

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
	sm.instance_count = 260
	for i in 260:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (island_radius - 2.0)
		var s := rng.randf_range(0.5, 1.4)
		sm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1, s * rng.randf_range(0.6, 1.0))), Vector3(cos(a) * r, 0.03, sin(a) * r)))
		sm.set_instance_color(i, Color(0.8, 0.8, 0.78) if i < 200 else Color(1.0, 0.95, 0.85))
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
	# Shrines on a ring, so every direction has something to run to.
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		var r := 34.0 + (i % 2) * 8.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
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
