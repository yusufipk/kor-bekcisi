class_name Game
extends Node3D
## Run controller: director (spawns, events, boss), XP and level-ups, camera,
## music and records.

static var inst: Game

enum { S_TITLE, S_PLAY, S_LEVELUP, S_PAUSE, S_END }
const BOSS_TIME := 600.0
const RECORD_PATH := "user://rekor.cfg"
const DEMO_PATH := "user://demo.cfg"

class Stats:
	var dmg := 1.0
	var cd := 1.0
	var area := 1.0
	var area_range := 1.0
	var amount := 0
	var speed := 1.0
	var magnet := 3.2
	var regen := 0.0
	var xp := 1.0
	var crit := 0.04
	var armor := 1.0
	var air_jumps := 0
	var slide_cd := 1.0

var st := Stats.new()
var passives := {}
var state := S_TITLE
var t := 0.0
var level := 1
var xp := 0.0
var xp_next := 4.0
var pending_levels := 0
var pending_chest := 0
var kills := 0
var stats_total_damage := 0.0
var stats_damage_taken := 0.0
var chests_opened := 0
var shrines_lit := 0
var enemy_dmg_mult := 1.0
var won := false
var demo := false
var demo_cfg := {}
var prof := [0, 0, 0, 0, 0, 0]

var world: World
var player
var em: EnemyManager
var weapons: Weapons
var fx: Fx
var pickups: Pickups
var ui
var bot

# Camera
var cam_rig: Node3D
var cam_pitch_node: Node3D
var spring: SpringArm3D
var cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := -0.62
var trauma := 0.0
var hitstop_t := 0.0

# Director
var spawn_t := 0.0
var events_done := {}
var elite_t := 80.0
var chest_t := 25.0

# Boss
var boss_state := "walk"
var boss_timer := 4.0
var boss_attack_t := 0.0
var boss_target := Vector3.ZERO
var boss_spawned := false
var boss_dead_t := -1.0

# Shrines
var shrines: Array = []   # {node, p, lit, charge, light}
var chest_model_path := "res://art/models/sandik.glb"


func _enter_tree() -> void:
	inst = self

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_demo_cfg()
	world = World.new()
	add_child(world)
	world.build()
	fx = Fx.new()
	add_child(fx)
	em = EnemyManager.new()
	add_child(em)
	em.set_obstacles(world.obstacles)
	_setup_enemy_visuals()
	pickups = Pickups.new()
	add_child(pickups)
	weapons = Weapons.new()
	add_child(weapons)
	weapons.setup(em, fx)
	_setup_player()
	_setup_camera()
	_setup_shrines()
	for n in [world, fx, em, pickups, weapons, player]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	ui = preload("res://scripts/ui.gd").new()
	add_child(ui)
	Settings.changed.connect(func(): world.apply_brightness(Settings.brightness))
	if demo:
		bot = preload("res://scripts/bot.gd").new()
		add_child(bot)
		start_run()
	else:
		state = S_TITLE
		get_tree().paused = true
		ui.show_title(_load_record())
		_play_music("early")

func _load_demo_cfg() -> void:
	var c := ConfigFile.new()
	if OS.is_debug_build() and c.load(DEMO_PATH) == OK and c.get_value("demo", "enabled", false):
		demo = true
		for k in c.get_section_keys("demo"):
			demo_cfg[k] = c.get_value("demo", k)

# ---------------------------------------------------------------- setup

func _enemy_material(tex: Texture2D, rim: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool has_tex = false;
uniform vec3 base_col : source_color = vec3(0.35, 0.28, 0.42);
uniform vec3 rim_col : source_color = vec3(1.0, 0.25, 0.85);
varying vec4 cd;
void vertex() {
	cd = INSTANCE_CUSTOM;
	// Small idle wobble so static meshes feel alive.
	VERTEX.x += sin(TIME * 6.0 + cd.w + VERTEX.y * 3.0) * 0.03 * VERTEX.y;
}
void fragment() {
	vec3 c = has_tex ? texture(tex, UV).rgb : base_col;
	if (cd.y > 0.5) c = mix(c, vec3(1.0, 0.55, 0.15), 0.35);
	if (cd.z > 0.5) c = mix(c, vec3(0.5, 0.8, 1.0), 0.45);
	ALBEDO = mix(c, vec3(1.0), cd.x * 0.85);
	ROUGHNESS = 0.85;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = rim_col * rim * (0.9 + cd.y * 2.0) + vec3(1.0) * cd.x * 0.8;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	if tex:
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("has_tex", true)
	m.set_shader_parameter("rim_col", rim)
	return m

func _setup_enemy_visuals() -> void:
	var files := ["bocek", "guve", "hantal", "tukurgec"]
	var heights := [0.9, 0.8, 2.3, 1.5]
	var rims := [Color(1.0, 0.3, 0.85), Color(1.0, 0.35, 0.95), Color(0.9, 0.3, 0.8), Color(1.0, 0.45, 0.6)]
	var meshes: Array = []
	var mats: Array = []
	for i in 4:
		var r := Models.merged_mesh("res://art/models/%s.glb" % files[i], heights[i], PI if i == 1 else 0.0)
		if r.is_empty():
			var pm: Mesh
			match i:
				0:
					pm = SphereMesh.new(); pm.radius = 0.5; pm.height = 0.8; pm.radial_segments = 7; pm.rings = 3
				1:
					pm = PrismMesh.new(); pm.size = Vector3(1.4, 0.3, 0.6)
				2:
					pm = BoxMesh.new(); pm.size = Vector3(1.8, 2.0, 1.4)
				3:
					pm = CylinderMesh.new(); pm.top_radius = 0.3; pm.bottom_radius = 0.7; pm.height = 1.4
			# Placeholder meshes are centred; lift so the base sits on the ground.
			var stf := SurfaceTool.new()
			stf.append_from(pm, 0, Transform3D(Basis(), Vector3(0, pm.get_aabb().size.y * 0.5, 0)))
			meshes.append(stf.commit())
			mats.append(_enemy_material(null, rims[i]))
		else:
			meshes.append(r[0])
			mats.append(_enemy_material(r[1], rims[i]))
	em.setup(meshes, mats, [1.0, 1.0, 1.0, 1.0])

func _setup_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(preload("res://scripts/player.gd"))
	player.position = Vector3(0, 0.5, 0)
	add_child(player)
	var hero := Models.hero()
	var model: Node3D = hero[0]
	var anim: AnimationPlayer = hero[1]
	var names: Dictionary = hero[2]
	if model == null:
		model = Node3D.new()
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = 1.6
		body.mesh = cap
		body.position.y = 0.8
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.55, 0.15)
		body.material_override = m
		model.add_child(body)
	model.set_meta("base_scale", 1.0)
	# Warm lantern light that travels with the hero keeps them readable.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	lamp.position = Vector3(0, 1.5, 0)
	lamp.shadow_enabled = false
	player.add_child(lamp)
	player.set_model(model, anim, names)
	Models.fit_skinned(model, 1.75)

func _setup_camera() -> void:
	cam_rig = Node3D.new()
	add_child(cam_rig)
	cam_pitch_node = Node3D.new()
	cam_rig.add_child(cam_pitch_node)
	spring = SpringArm3D.new()
	spring.spring_length = 11.0
	spring.collision_mask = 2
	spring.margin = 0.3
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	spring.shape = sph
	cam_pitch_node.add_child(spring)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 600.0
	spring.add_child(cam)
	spring.add_excluded_object(player.get_rid())
	cam_rig.position = player.position

func _setup_shrines() -> void:
	var i := 0
	for p in world.shrine_spots:
		var node := Models.prop("res://art/models/fener.glb", 4.2)
		if node == null:
			node = Node3D.new()
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.0, 4.0, 1.0)
			mi.mesh = bm
			mi.position.y = 2.0
			node.add_child(mi)
		node.position = p
		world.apply_fade(node)
		world.add_child(node)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.75, 0.35)
		light.light_energy = 0.4
		light.omni_range = 5.0
		light.position = p + Vector3(0, 3.4, 0)
		world.add_child(light)
		var body := StaticBody3D.new()
		body.collision_layer = 2
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.7
		cyl.height = 4.0
		cs.shape = cyl
		cs.position = p + Vector3(0, 2, 0)
		body.add_child(cs)
		world.add_child(body)
		shrines.append({"p": p, "lit": false, "charge": 0.0, "light": light, "idx": i})
		i += 1

func _play_music(id: String) -> void:
	Music.play(id)

# ---------------------------------------------------------------- run flow

func start_run() -> void:
	state = S_PLAY
	get_tree().paused = false
	weapons.add_weapon("bolt")
	if not demo:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.show_hud()
	ui.hint("WASD koş  ·  Boşluk zıpla  ·  Shift kay  ·  Silahlar kendiliğinden ateş eder", 7.0)
	_play_music("early")
	if demo and demo_cfg.has("start_time"):
		var skip: float = demo_cfg["start_time"]
		t = skip
		# Simulate the upgrades a player would have by then.
		var n := int(skip / 18.0)
		for i in n:
			var ch := roll_choices()
			if ch.size() > 0:
				apply_choice(ch[randi() % ch.size()])
		level += n
		xp_next = xp_needed(level)
		for id in ["tip_shrine", "tip_jump", "ring1", "ring2", "ring3", "swarm1", "swarm2", "swarm3", "music_late"]:
			events_done[id] = true
		if skip > 270.0:
			_play_music("late")
	if demo and demo_cfg.has("time_scale"):
		Engine.time_scale = float(demo_cfg["time_scale"])

func restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and state == S_PLAY and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := 0.0024 * Settings.mouse_sens
		cam_yaw -= ev.relative.x * s
		cam_pitch -= ev.relative.y * s * (-1.0 if Settings.invert_y else 1.0)
		cam_pitch = clampf(cam_pitch, -1.25, -0.12)
	if ev.is_action_pressed("pause"):
		if state == S_PLAY:
			pause()
		elif state == S_PAUSE:
			resume()
	if ev.is_action_pressed("restart") and state == S_END:
		restart()
	if ev is InputEventMouseButton and ev.pressed and state == S_PLAY and not demo:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func pause() -> void:
	state = S_PAUSE
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_pause()

func resume() -> void:
	state = S_PLAY
	get_tree().paused = false
	ui.hide_pause()
	if not demo:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(dt: float) -> void:
	# Hit stop runs in real time, independent of Engine.time_scale.
	if hitstop_t > 0.0:
		hitstop_t -= dt / maxf(Engine.time_scale, 0.01)
		if hitstop_t <= 0.0:
			Engine.time_scale = float(demo_cfg.get("time_scale", 1.0)) if demo else 1.0
	_update_camera(dt)
	Sfx.listener_pos = player.global_position
	if state != S_PLAY:
		return
	t += dt
	if demo and demo_cfg.has("pause_at") and t >= float(demo_cfg["pause_at"]) and not events_done.has("demo_pause"):
		events_done["demo_pause"] = true
		pause()
		return
	enemy_dmg_mult = 1.0 + t / 420.0
	em.hp_mult = 1.0 + t / 130.0 + pow(t / 300.0, 2.0)
	var t0 := Time.get_ticks_usec()
	_director(dt)
	var t1 := Time.get_ticks_usec()
	em.update(dt, player.global_position, player)
	var t2 := Time.get_ticks_usec()
	weapons.update(dt, player)
	var t3 := Time.get_ticks_usec()
	pickups.update(dt, player)
	var t4 := Time.get_ticks_usec()
	_update_shrines(dt)
	if demo:
		prof[0] += t1 - t0; prof[1] += t2 - t1; prof[2] += t3 - t2; prof[3] += t4 - t3
		prof[5] += 1
		if prof[5] >= 120:
			print("PROF us/frame dir=%d em=%d weap=%d pick=%d gems=%d alive=%d fx=%d" % [prof[0] / 120, prof[1] / 120, prof[2] / 120, prof[3] / 120, pickups.g_count, em.alive_count(), fx.s_count])
			prof = [0, 0, 0, 0, 0, 0]
	if boss_dead_t >= 0.0:
		boss_dead_t -= dt
		if boss_dead_t < 0.0:
			_end_run(true)
	ui.update_hud()

func _update_camera(dt: float) -> void:
	player.cam_yaw = cam_yaw
	var target: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	cam_rig.position = cam_rig.position.lerp(target, minf(1.0, dt * 12.0))
	cam_rig.rotation.y = cam_yaw
	cam_pitch_node.rotation.x = cam_pitch
	trauma = maxf(0.0, trauma - dt * 1.6)
	var sh := trauma * trauma
	var tt := Time.get_ticks_msec() * 0.001
	cam.h_offset = sin(tt * 37.0) * sh * 0.6
	cam.v_offset = cos(tt * 41.0) * sh * 0.5
	cam.rotation.z = sin(tt * 29.0) * sh * 0.03
	var head: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	if not cam.is_position_behind(head):
		var vp := get_viewport().get_visible_rect().size
		RenderingServer.global_shader_parameter_set("player_screen", cam.unproject_position(head) / vp)
		RenderingServer.global_shader_parameter_set("player_depth", cam.global_position.distance_to(head))

func shake(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)

func hitstop(d: float) -> void:
	if hitstop_t > 0.0 or state != S_PLAY:
		return
	hitstop_t = d
	Engine.time_scale = 0.05

# ---------------------------------------------------------------- director

func _target_alive() -> float:
	var pts := [[0.0, 8.0], [45.0, 24.0], [120.0, 55.0], [240.0, 110.0], [360.0, 190.0], [480.0, 280.0], [570.0, 360.0], [600.0, 380.0]]
	for i in pts.size() - 1:
		if t < pts[i + 1][0]:
			var k: float = (t - pts[i][0]) / (pts[i + 1][0] - pts[i][0])
			return lerpf(pts[i][1], pts[i + 1][1], k)
	return 70.0  # during the boss: thinner support waves

func _pick_type() -> int:
	var w := [1.0, 0.0, 0.0, 0.0]
	if t > 50.0: w[1] = 0.45
	if t > 140.0: w[2] = 0.14 + minf(t / 3000.0, 0.12)
	if t > 230.0: w[3] = 0.14
	var tot := 0.0
	for x in w: tot += x
	var r := randf() * tot
	for i in 4:
		r -= w[i]
		if r <= 0.0:
			return i
	return 0

func _spawn_pos(dist_min := 22.0, dist_max := 30.0) -> Vector3:
	var pp: Vector3 = player.global_position
	# Bias spawns ahead of the camera view direction a bit so they are seen coming.
	for tries in 8:
		var a := randf() * TAU
		var d := randf_range(dist_min, dist_max)
		var p := pp + Vector3(cos(a) * d, 0, sin(a) * d)
		if Vector2(p.x, p.z).length() < world.island_radius - 2.0:
			return p
	var dir := -Vector3(pp.x, 0, pp.z).normalized()
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	return pp + dir * dist_min

func _director(dt: float) -> void:
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = 0.25
		var target := _target_alive()
		var deficit := int(target) - em.alive_count()
		# Throughput must outpace a strong build, or the horde never piles up.
		var burst := mini(deficit, 3 + int(t / 14.0))
		for i in burst:
			em.spawn(_pick_type(), _spawn_pos())
	# Elites
	elite_t -= dt
	if elite_t <= 0.0 and t < BOSS_TIME - 10.0:
		elite_t = 70.0
		var et := 0 if t < 150.0 else (2 if randf() < 0.6 else 3)
		em.spawn(et, _spawn_pos(18.0, 22.0), true)
		toast("Parlayan bir düşman geliyor. Onu yen, sandık düşürür!")
	# Chests on the map
	chest_t -= dt
	if chest_t <= 0.0:
		chest_t = 55.0
		if pickups.chests.size() < 2:
			var p := _chest_spot()
			pickups.spawn_chest(p, Models.prop(chest_model_path, 1.1))
			toast("Adada bir sandık belirdi. Işık sütununu takip et!")
	_event(150.0, "ring1")
	_event(300.0, "ring2")
	_event(450.0, "ring3")
	_event(240.0, "swarm1")
	_event(420.0, "swarm2")
	_event(540.0, "swarm3")
	_event(14.0, "tip_shrine")
	_event(40.0, "tip_jump")
	_event(270.0, "music_late")
	_event(BOSS_TIME - 20.0, "boss_warn")
	_event(BOSS_TIME, "boss")

func _chest_spot() -> Vector3:
	var pp: Vector3 = player.global_position
	for tries in 30:
		var a := randf() * TAU
		var r := sqrt(randf()) * (world.island_radius - 6.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.distance_to(pp) < 22.0:
			continue
		var ok := true
		for o in world.obstacles:
			if Vector2(p.x, p.z).distance_to(o[0]) < o[1] + 2.0:
				ok = false
				break
		if ok:
			return p
	return Vector3(0, 0, 0)

func _event(at: float, id: String) -> void:
	if t < at or events_done.has(id):
		return
	events_done[id] = true
	var pp: Vector3 = player.global_position
	if id.begins_with("ring"):
		toast("Halka kapanıyor! Boşluk bul ya da üstünden zıpla!")
		var n := 36 + int(t / 12.0)
		for i in n:
			var a := TAU * i / n
			em.spawn(0, pp + Vector3(cos(a), 0, sin(a)) * 15.0)
	elif id.begins_with("swarm"):
		toast("Güve sürüsü!")
		var a := randf() * TAU
		var base := pp + Vector3(cos(a), 0, sin(a)) * 26.0
		for i in 30 + int(t / 20.0):
			em.spawn(1, base + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
	elif id == "tip_shrine":
		toast("✦ işaretli fenerin yanında 2 saniye dur: yanınca kalıcı güç verir.", 5.0)
	elif id == "tip_jump":
		toast("Sıkıştın mı? Shift ile kay, kayarken hasar almazsın.", 4.5)
	elif id == "music_late":
		_play_music("late")
	elif id == "boss_warn":
		toast("Yer titriyor... Kül Devi uyanıyor!", 4.0)
		shake(0.4)
		_play_music("boss")
	elif id == "boss":
		_spawn_boss()

func _spawn_boss() -> void:
	boss_spawned = true
	var p := _spawn_pos(20.0, 24.0)
	var e = em.spawn(EnemyManager.BOSS, p)
	e.max_hp = 14000.0 * (1.0 + 0.03 * maxi(0, level - 30))
	e.hp = e.max_hp
	var node := Models.prop("res://art/models/boss.glb", 7.5)
	if node == null:
		node = Node3D.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4, 7, 3)
		mi.mesh = bm
		mi.position.y = 3.5
		node.add_child(mi)
	# Additive overlay that flashes white on hits, like the horde shader does.
	var ov := ShaderMaterial.new()
	var osh := Shader.new()
	osh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never;
uniform float flash = 0.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = vec3(1.0) * flash * 0.7 + vec3(1.0, 0.25, 0.6) * rim * 0.5;
}
"""
	ov.shader = osh
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = ov
	node.set_meta("overlay", ov)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.35, 0.6)
	glow.light_energy = 3.0
	glow.omni_range = 10.0
	glow.position.y = 4.0
	node.add_child(glow)
	add_child(node)
	em.boss_node = node
	ui.show_boss_bar(true)
	Sfx.play("roar", Vector3.INF, 1.0, 0.0)
	shake(0.8)
	toast("KÜL DEVİ", 3.0)

## Called by EnemyManager for the boss each frame. Returns a move speed factor.
func boss_ai(e, dt: float, dist: float, dx: float, dz: float) -> float:
	var enraged: bool = e.hp < e.max_hp * 0.5
	boss_timer -= dt
	match boss_state:
		"walk":
			if dist > 17.0 and boss_timer <= 1.5:
				# Gap closer: flash as a warning, then lunge at the hero.
				boss_state = "charge_wind"
				boss_attack_t = 0.7
				toast("Kül Devi hamle yapıyor! Yana kay!", 1.5)
				return 0.0
			if boss_timer <= 0.0:
				var r := randf()
				if dist < 14.0 and r < 0.5:
					boss_state = "slam"
					boss_attack_t = 1.15
					boss_target = player.global_position
					boss_target.y = 0
					fx.telegraph(boss_target, 6.5, 1.15)
				elif r < 0.8:
					boss_state = "volley"
					boss_attack_t = 1.6
					boss_timer = 0.0
				else:
					boss_state = "summon"
					boss_attack_t = 0.6
			return 1.9 if enraged else 1.45
		"slam":
			boss_attack_t -= dt
			if boss_attack_t <= 0.0:
				Sfx.play("slam", Vector3.INF, 1.0, 0.05)
				shake(0.7)
				fx.ring(boss_target, 6.5, Color(1.0, 0.4, 0.3), 0.45, 0.4, 0.25)
				fx.burst(boss_target + Vector3(0, 0.5, 0), Color(0.6, 0.5, 0.6), 30, 2.0)
				var pp: Vector3 = player.global_position
				if Vector2(pp.x - boss_target.x, pp.z - boss_target.z).length() < 6.5 and pp.y < 1.0:
					player.hurt(30.0, boss_target)
				_boss_next(enraged)
			return 0.0
		"volley":
			boss_attack_t -= dt
			boss_timer -= dt
			if boss_timer <= 0.0:
				boss_timer = 0.4 if not enraged else 0.28
				var n := 14 if not enraged else 20
				var off := randf() * TAU
				for i in n:
					var a := off + TAU * i / n
					em.bullets.append([e.pos + Vector3(0, 1.2, 0), Vector3(cos(a), 0, sin(a)) * 8.0, 5.0])
			if boss_attack_t <= 0.0:
				_boss_next(enraged)
			return 0.3
		"charge_wind":
			boss_attack_t -= dt
			e.flash = 1.0
			if Engine.get_process_frames() % 4 == 0:
				fx.burst(e.pos + Vector3(0, 3.0, 0), Color(1.0, 0.3, 0.5), 3, 1.0)
			if boss_attack_t <= 0.0:
				boss_state = "charge"
				boss_attack_t = 1.1
				boss_target = Vector3(dx, 0, dz)
				Sfx.play("roar", Vector3.INF, 0.6, 0.1)
			return 0.0
		"charge":
			boss_attack_t -= dt
			if Engine.get_process_frames() % 3 == 0:
				fx.dust(e.pos, 4)
			# Committed direction: a side slide dodges it.
			e.vel = boss_target * 20.0
			if boss_attack_t <= 0.0:
				e.vel = Vector3.ZERO
				shake(0.3)
				_boss_next(enraged)
			return 0.0
		"summon":
			boss_attack_t -= dt
			if boss_attack_t <= 0.0:
				for i in 10:
					var a := TAU * i / 10.0
					em.spawn(0 if i % 2 == 0 else 1, e.pos + Vector3(cos(a), 0, sin(a)) * 5.0)
				fx.ring(e.pos, 6.0, Color(0.8, 0.3, 1.0), 0.5, 0.2, 0.2)
				_boss_next(enraged)
			return 0.0
	return 1.0

func _boss_next(enraged: bool) -> void:
	boss_state = "walk"
	boss_timer = randf_range(2.0, 3.0) if enraged else randf_range(3.0, 4.2)

# ---------------------------------------------------------------- shrines

func _update_shrines(dt: float) -> void:
	var pp: Vector3 = player.global_position
	for s in shrines:
		if s["lit"]:
			continue
		var d := Vector2(pp.x - s["p"].x, pp.z - s["p"].z).length()
		if d < 3.4:
			s["charge"] += dt
			s["light"].light_energy = 0.4 + s["charge"] * 2.0
			if Engine.get_process_frames() % 6 == 0:
				fx.burst(s["p"] + Vector3(0, 3.4, 0), Color(1.0, 0.8, 0.4), 2, 0.5)
			if s["charge"] >= 2.0:
				_light_shrine(s)
		else:
			s["charge"] = maxf(0.0, s["charge"] - dt)
			s["light"].light_energy = 0.4 + s["charge"] * 2.0

func _light_shrine(s: Dictionary) -> void:
	s["lit"] = true
	shrines_lit += 1
	s["light"].light_energy = 5.0
	s["light"].omni_range = 9.0
	var p: Vector3 = s["p"]
	fx.ring(p, 12.0, Color(1.0, 0.8, 0.35), 0.6, 0.25, 0.2)
	fx.burst(p + Vector3(0, 3.4, 0), Color(1.0, 0.85, 0.4), 30, 2.0)
	Sfx.play("shrine", Vector3.INF, 1.0, 0.0)
	shake(0.25)
	for e in em.query(p, 12.0):
		if e.type != EnemyManager.BOSS:
			em.damage(e, 9999.0)
	var msg := ""
	match shrines_lit:
		1:
			st.air_jumps += 1
			msg = "Rüzgâr Feneri: havada bir kez daha zıplayabilirsin!"
		2:
			st.dmg *= 1.15
			msg = "Kor Feneri: +%15 hasar"
		3:
			st.slide_cd *= 0.6
			msg = "Akış Feneri: kayma çok daha sık"
		4:
			st.magnet *= 1.5
			st.xp *= 1.1
			msg = "Çekim Feneri: +%50 toplama menzili, +%10 tecrübe"
		_:
			st.dmg *= 1.15
			st.cd *= 0.9
			msg = "Son Fener: +%15 hasar, -%10 bekleme"
	player.heal(40.0)
	toast("Fener yandı! " + msg, 4.0)

# ---------------------------------------------------------------- xp, level-ups

func on_enemy_killed(e) -> void:
	if e.type == EnemyManager.BOSS:
		kills += 1
		boss_dead_t = 3.0
		em.clear_all()
		won = true
		ui.show_boss_bar(false)
		for i in 6:
			fx.burst(e.pos + Vector3(randf_range(-2, 2), randf_range(1, 6), randf_range(-2, 2)), Color(1.0, 0.5, 0.8), 40, 3.0)
		Sfx.play("roar", Vector3.INF, 1.0, 0.0)
		Sfx.play("slam", Vector3.INF, 1.0, 0.0)
		shake(1.0)
		if em.boss_node:
			var tw := create_tween()
			tw.tween_property(em.boss_node, "scale", Vector3(1.3, 0.05, 1.3), 1.2)
		return
	kills += 1
	var v: int = em.TYPES[e.type]["xp"]
	if e.elite:
		pickups.spawn_chest(e.pos, Models.prop(chest_model_path, 1.1))
		v *= 5
	pickups.gem(e.pos, v)
	var r := randf()
	if r < 0.009 or e.elite:
		pickups.item(e.pos, "heal")
	elif r < 0.012:
		pickups.item(e.pos + Vector3(0.8, 0, 0), "magnet")
	if e.elite or e.type == EnemyManager.BRUTE:
		shake(0.15)

func add_xp(v: float) -> void:
	xp += v * st.xp
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = xp_needed(level)
		pending_levels += 1
	if pending_levels > 0 and state == S_PLAY:
		_open_levelup(false)

## Early levels come quickly so the first minute already feels like growth.
static func xp_needed(lv: int) -> float:
	var n := float(lv - 1)
	return 4.0 + n * 3.5 + pow(n, 1.6)

func open_chest(p: Vector3) -> void:
	chests_opened += 1
	Sfx.play("chest", Vector3.INF, 1.0, 0.0)
	fx.burst(p + Vector3(0, 1, 0), Color(1.0, 0.85, 0.35), 36, 2.2)
	for i in 8:
		pickups.gem(p + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 5)
	pending_chest += 1
	if state == S_PLAY:
		_open_levelup(true)

func _open_levelup(chest: bool) -> void:
	var choices := roll_choices()
	if choices.is_empty():
		pending_levels = 0
		pending_chest = 0
		player.heal(30.0)
		return
	state = S_LEVELUP
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not chest:
		Sfx.play("levelup", Vector3.INF, 1.0, 0.0)
	ui.show_levelup(choices, chest or pending_chest > 0)
	if demo and bot:
		bot.pick_soon(choices)

func roll_choices() -> Array:
	var pool: Array = []   # [id, kind, weight]
	var owned := weapons.lv.size()
	for id in Upgrades.WEAPONS.keys():
		var l := weapons.level(id)
		if l > 0 and l < Upgrades.WEAPON_MAX:
			pool.append([id, "w", 3.0])
		elif l == 0 and owned < Upgrades.MAX_WEAPONS:
			pool.append([id, "w", 2.6 if owned < 3 else 1.4])
	for id in Upgrades.PASSIVES.keys():
		var l: int = passives.get(id, 0)
		var cap := 2 if id == "amount" else Upgrades.PASSIVE_MAX
		if l < cap:
			pool.append([id, "p", 0.8 if id == "amount" else 1.6])
	var out: Array = []
	var need_new_weapon := owned < 2
	while out.size() < 3 and pool.size() > 0:
		var tot := 0.0
		for c in pool: tot += c[2]
		var r := randf() * tot
		var pick := 0
		for i in pool.size():
			r -= pool[i][2]
			if r <= 0.0:
				pick = i
				break
		if need_new_weapon and out.is_empty():
			for i in pool.size():
				if pool[i][1] == "w" and weapons.level(pool[i][0]) == 0:
					pick = i
					break
		out.append({"id": pool[pick][0], "kind": pool[pick][1]})
		pool.remove_at(pick)
	return out

func apply_choice(c: Dictionary) -> void:
	var id: String = c["id"]
	if c["kind"] == "w":
		weapons.add_weapon(id)
		if weapons.level(id) >= Upgrades.WEAPON_MAX and state != S_TITLE:
			toast("%s uyandı! +%%40 hasar" % Upgrades.WEAPONS[id]["name"], 3.5)
			fx.ring(player.global_position, 9.0, Color(1.0, 0.85, 0.3), 0.6, 0.2, 0.2)
			fx.burst(player.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.3), 40, 2.0)
			Sfx.play("shrine", Vector3.INF, 1.0, 0.0)
			shake(0.3)
		return
	passives[id] = passives.get(id, 0) + 1
	match id:
		"hp":
			player.max_hp += 25.0
			player.hp = player.max_hp
		"speed": st.speed *= 1.08
		"power": st.dmg *= 1.15
		"haste": st.cd *= 0.92
		"area":
			st.area *= 1.12
			st.area_range *= 1.06
		"amount": st.amount += 1
		"magnet": st.magnet *= 1.4
		"regen": st.regen += 0.8
		"wisdom": st.xp *= 1.15
		"crit": st.crit += 0.08

func choose(c: Dictionary) -> void:
	apply_choice(c)
	Sfx.play("select", Vector3.INF, 1.0, 0.0)
	fx.burst(player.global_position + Vector3(0, 1, 0), Color(1.0, 0.85, 0.4), 14, 1.2)
	if pending_chest > 0:
		pending_chest -= 1
	elif pending_levels > 0:
		pending_levels -= 1
	if pending_chest > 0 or pending_levels > 0:
		var ch := roll_choices()
		if not ch.is_empty():
			ui.show_levelup(ch, pending_chest > 0)
			if demo and bot:
				bot.pick_soon(ch)
			return
		pending_levels = 0
		pending_chest = 0
	ui.hide_levelup()
	state = S_PLAY
	get_tree().paused = false
	if not demo:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Brief invulnerability and a soft push so a pick never drops you into a hit.
	player.invuln_t = maxf(player.invuln_t, 0.6)
	var pp: Vector3 = player.global_position
	fx.ring(pp, 6.0, Color(1.0, 0.75, 0.3), 0.35, 0.0, 0.1)
	for e in em.query(pp, 6.0):
		var away: Vector3 = e.pos - pp
		away.y = 0
		e.vel += away.normalized() * 14.0

func on_slide(p: Vector3, dir: Vector3) -> void:
	weapons.on_slide(p, dir)

func toast(msg: String, dur := 3.0) -> void:
	if ui:
		ui.toast(msg, dur)

# ---------------------------------------------------------------- end

func on_player_died() -> void:
	shake(0.6)
	Sfx.play("roar", Vector3.INF, 0.5, 0.0)
	get_tree().create_timer(1.4, true, false, true).timeout.connect(func(): _end_run(false))

func _end_run(victory: bool) -> void:
	if state == S_END:
		return
	state = S_END
	Engine.time_scale = 1.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var rec := _load_record()
	var new_best := false
	if not demo:
		new_best = _save_record(victory)
	var summary := {
		"victory": victory, "time": t, "kills": kills, "level": level,
		"damage": stats_total_damage, "taken": stats_damage_taken,
		"chests": chests_opened, "shrines": shrines_lit,
		"weapons": weapons.lv.duplicate(), "passives": passives.duplicate(),
		"best": rec, "new_best": new_best, "demo": demo,
	}
	ui.show_end(summary)
	if demo:
		print("DEMO_END ", JSON.stringify({"victory": victory, "time": t, "kills": kills, "level": level, "damage": stats_total_damage}))

func _load_record() -> Dictionary:
	var c := ConfigFile.new()
	var d := {"best_time": 0.0, "best_kills": 0, "wins": 0, "runs": 0}
	if c.load(RECORD_PATH) == OK:
		for k in d.keys():
			d[k] = c.get_value("r", k, d[k])
	return d

func _save_record(victory: bool) -> bool:
	var d := _load_record()
	var best := false
	d["runs"] += 1
	if victory:
		d["wins"] += 1
	if t > d["best_time"]:
		d["best_time"] = t
		best = true
	if kills > d["best_kills"]:
		d["best_kills"] = kills
		best = true
	var c := ConfigFile.new()
	for k in d.keys():
		c.set_value("r", k, d[k])
	c.save(RECORD_PATH)
	return best

static func fmt_time(sec: float) -> String:
	# Floor to whole seconds first so 59.97 never shows as 00:60.
	var s := int(floor(sec))
	return "%02d:%02d" % [s / 60, s % 60]
