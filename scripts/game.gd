class_name Game
extends Node3D
## Run controller: director (spawns, events, boss), XP and level-ups, camera,
## music and records.

static var inst: Game

enum { S_TITLE, S_PLAY, S_LEVELUP, S_PAUSE, S_END }
const BOSS_TIME := 600.0
const EVO_FROM := 240.0
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
var levelup_gap := 0.0       # level-ups that land soon after a card screen wait and batch up
var kills := 0
var stats_total_damage := 0.0
var stats_damage_taken := 0.0
var chests_opened := 0
var shrines_lit := 0
var crystals_broken := 0
var serpent_killed := false
var enemy_dmg_mult := 1.0
var won := false
var rerolls := 1
var revives := 0
var meta = preload("res://scripts/meta.gd").new()
var new_discoveries: Array = []
var evolved: Array = []          # weapon ids evolved this run, in order
var weapon_damage := {}          # weapon id -> damage dealt this run
var cur_chest := false           # the open card set came from a chest
var dmg_src := ""                # set by Weapons around each hit
var demo := false
var end_ms := 0
var mouse_ms := 0
var demo_cfg := {}
var prof := [0, 0, 0, 0, 0, 0]

var world: World
var serpent  # scripts/serpent.gd
var crystal_t := 30.0
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
var evo_t := 0.0             # evolution camera pull-in, real seconds left
var slow_t := 0.0            # cinematic slow motion, real seconds left
var slow_scale := 1.0
var cam_look = null          # Vector3 the camera turns toward during cinematics
var boss_phase := 1
var boss_rain: Array = []    # [pos, t] ash meteors in flight
var boss_fissures: Array = []  # [origin, dir, t]
var boss_intro_t := 0.0
var crumble: Array = []      # enemies dissolving after the boss falls
var cam_dist := 11.0
var lamp: OmniLight3D
var hero_ring: MeshInstance3D
var dawn_k := 0.0

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
var boss_fight_t := 0.0
var boss_taken := 0.0
var boss_calibrated := false
var boss_warn := 0.0

# Shrines
var shrines: Array = []   # {node, p, lit, charge, light}
var chest_model_path := "res://art/models/sandik.glb"


func _enter_tree() -> void:
	inst = self

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_demo_cfg()
	if not demo:
		meta.load_cfg()
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
	serpent = preload("res://scripts/serpent.gd").new()
	add_child(serpent)
	for i in 8:
		_grow_crystal()
	for n in [world, fx, em, pickups, weapons, player, serpent]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	ui = preload("res://scripts/ui.gd").new()
	add_child(ui)
	# Bound method, so the connection dies with this scene on restart.
	Settings.changed.connect(_on_settings_changed)
	if demo:
		bot = preload("res://scripts/bot.gd").new()
		add_child(bot)
		start_run()
	else:
		state = S_TITLE
		get_tree().paused = true
		ui.show_title(_load_record())
		_play_music("early")
		# Debug builds only: open a menu screen directly for screenshots.
		var c := ConfigFile.new()
		if OS.is_debug_build() and c.load(DEMO_PATH) == OK and c.get_value("demo", "screen", "") == "altar":
			ui._altar()

func _on_settings_changed() -> void:
	world.apply_brightness(Settings.brightness)

func _load_demo_cfg() -> void:
	if not OS.is_debug_build():
		return
	var c := ConfigFile.new()
	if c.load(DEMO_PATH) == OK and c.get_value("demo", "enabled", false):
		demo = true
		for k in c.get_section_keys("demo"):
			demo_cfg[k] = c.get_value("demo", k)
	# Test runs can also pass the same keys after "--": `-- demo=1 bot=circle seed=3`.
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() != 2:
			continue
		var v = kv[1]
		if v == "true" or v == "false":
			v = v == "true"
		elif v.is_valid_float():
			v = float(v)
		demo_cfg[kv[0]] = v
	if demo_cfg.get("demo", 0.0) == 1.0:
		demo = true
	if demo and demo_cfg.has("seed"):
		seed(int(demo_cfg["seed"]))

# ---------------------------------------------------------------- setup

func _enemy_material(tex: Texture2D, rim: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool has_tex = false;
uniform vec3 base_col : source_color = vec3(0.35, 0.28, 0.42);
uniform vec3 rim_col : source_color = vec3(0.55, 0.42, 1.0);
uniform float inner_glow = 0.0;
global uniform float night;
varying vec4 cd;
void vertex() {
	cd = INSTANCE_CUSTOM;
	// Small idle wobble so static meshes feel alive.
	VERTEX.x += sin(TIME * 6.0 + cd.w + VERTEX.y * 3.0) * 0.03 * VERTEX.y;
}
void fragment() {
	vec3 c = has_tex ? texture(tex, UV).rgb : base_col;
	if (cd.y > 0.5) c = mix(c, vec3(1.0, 0.55, 0.15), 0.35);
	if (cd.z > 0.5) c = mix(c, vec3(0.35, 0.6, 1.0), 0.22);
	// Hit flash stays partial so big bodies keep their shape and colour.
	ALBEDO = mix(c, vec3(1.0, 0.92, 0.9), cd.x * 0.45);
	ROUGHNESS = 0.85;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	// At night the rim and cracks glow harder so the horde stays readable.
	EMISSION = rim_col * rim * (0.9 + cd.y * 2.0 + night * 0.6) + vec3(1.0, 0.8, 0.7) * cd.x * 0.25 + c * inner_glow * (0.5 + night);
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
	# type -> [file, height, yaw, rim colour]
	var spec := {
		# The horde glows a cold violet, apart from the warm sky, the turquoise
		# hero and the lava-orange boss. Keses keep a yellow fuse colour.
		EnemyManager.CRAWLER: ["bocek", 0.9, 0.0, Color(0.55, 0.42, 1.0)],
		EnemyManager.MOTH: ["guve", 0.8, PI, Color(0.6, 0.5, 1.0)],
		EnemyManager.BRUTE: ["hantal", 2.3, 0.0, Color(0.5, 0.45, 0.95)],
		EnemyManager.SPITTER: ["tukurgec", 1.5, 0.0, Color(0.45, 0.62, 1.0)],
		EnemyManager.KESE: ["kese", 1.3, 0.0, Color(1.0, 0.72, 0.2)],
		EnemyManager.BOYNUZ: ["boynuz", 1.7, -PI * 0.5, Color(0.75, 0.38, 1.0)],
		EnemyManager.CRYSTAL: ["kristal", 1.8, 0.0, Color(1.0, 0.7, 0.25)],
	}
	var meshes := {}
	var mats := {}
	for ti in spec.keys():
		var sp: Array = spec[ti]
		var r := Models.merged_mesh("res://art/models/%s.glb" % sp[0], sp[1], sp[2])
		if r.is_empty():
			var pm := SphereMesh.new()
			pm.radius = 0.5
			pm.height = 0.9
			pm.radial_segments = 7
			pm.rings = 3
			# Placeholder meshes are centred; lift so the base sits on the ground.
			var stf := SurfaceTool.new()
			stf.append_from(pm, 0, Transform3D(Basis(), Vector3(0, 0.45, 0)))
			meshes[ti] = stf.commit()
			mats[ti] = _enemy_material(null, sp[3])
		else:
			meshes[ti] = r[0]
			mats[ti] = _enemy_material(r[1], sp[3])
	# Crystals glow from inside, more so at night.
	mats[EnemyManager.CRYSTAL].set_shader_parameter("inner_glow", 0.6)
	em.setup(meshes, mats)

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
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	lamp.position = Vector3(0, 1.5, 0)
	lamp.shadow_enabled = false
	player.add_child(lamp)
	player.set_model(model, anim, names)
	Models.fit_skinned(model, 1.75)
	_hero_marks(model)

## A turquoise outline and a ring at the feet keep the hero findable in any
## light, among orange trees, a violet horde and a red ash sky alike.
func _hero_marks(model: Node3D) -> void:
	var osh := Shader.new()
	osh.code = """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec3 col : source_color = vec3(0.35, 1.0, 0.92);
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Grow with camera distance so the line keeps its width on screen.
	float w = 0.009 * length(wp - CAMERA_POSITION_WORLD);
	VERTEX += NORMAL * w / max(length(MODEL_MATRIX[0].xyz), 0.0001);
}
void fragment() {
	ALBEDO = col;
}
"""
	var om := ShaderMaterial.new()
	om.shader = osh
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = om
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 2.6)
	q.orientation = PlaneMesh.FACE_Y
	ring.mesh = q
	var rsh := Shader.new()
	rsh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 col : source_color = vec3(0.3, 1.0, 0.9);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float band = smoothstep(0.62, 0.72, r) * (1.0 - smoothstep(0.82, 0.92, r));
	// Four slow notches turn around the ring so it reads as the hero's own.
	float ang = atan(p.y, p.x) + TIME * 0.8;
	float notch = 0.65 + 0.35 * step(0.0, sin(ang * 4.0));
	ALBEDO = col * band * notch * 1.4;
	ALPHA = 1.0;
}
"""
	var rm := ShaderMaterial.new()
	rm.shader = rsh
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Stays on the ground while the hero jumps.
	ring.top_level = true
	player.add_child(ring)
	hero_ring = ring

func _setup_camera() -> void:
	cam_rig = Node3D.new()
	add_child(cam_rig)
	cam_pitch_node = Node3D.new()
	cam_rig.add_child(cam_pitch_node)
	spring = SpringArm3D.new()
	spring.spring_length = 11.0
	# No arm collision: pulling in behind a tree or column dropped the camera to
	# head height. Every prop fades when it stands between camera and hero instead.
	spring.collision_mask = 0
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
	_apply_meta()
	weapons.add_weapon(meta.start_weapon if meta.rank("start") > 0 else "bolt")
	if not demo:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.show_hud()
	ui.hint("WASD koş  ·  Boşluk zıpla  ·  Shift kay  ·  Silahlar kendiliğinden ateş eder", 7.0)
	toast("Öndeki ✦ fenerin yanında 2 saniye dur: yanınca güç verir, ışığı canını doldurur.", 7.0)
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
	# Debug: a ready evolution, to look at the golden card.
	if demo and demo_cfg.get("screen", "") == "evo":
		weapons.lv["bolt"] = Upgrades.WEAPON_MAX
		passives["crit"] = 1
		t = maxf(t, EVO_FROM)
		get_tree().create_timer(1.0).timeout.connect(open_chest.bind(player.global_position))

## Permanent altar upgrades. Demo runs have no ranks, so tests stay comparable.
func _apply_meta() -> void:
	if demo:
		return
	player.max_hp += 10.0 * meta.rank("hp")
	player.hp = player.max_hp
	st.dmg *= 1.0 + 0.04 * meta.rank("dmg")
	st.speed *= 1.0 + 0.03 * meta.rank("speed")
	st.magnet *= 1.0 + 0.15 * meta.rank("magnet")
	st.xp *= 1.0 + 0.05 * meta.rank("xp")
	rerolls += meta.rank("reroll")
	revives = meta.rank("revive")

## Called by the player at zero health. Returns true if a revive was spent.
func try_revive() -> bool:
	if revives <= 0:
		return false
	revives -= 1
	player.hp = player.max_hp * 0.5
	player.invuln_t = 2.5
	var pp: Vector3 = player.global_position
	fx.ring(pp, 12.0, Color(0.5, 1.0, 0.7), 0.6, 0.25, 0.25)
	fx.pillar(pp, Color(0.6, 1.0, 0.75))
	for e in em.query(pp, 12.0):
		if _is_big(e) or e.type == EnemyManager.CRYSTAL:
			continue
		e.vel += (e.pos - pp).normalized() * 26.0
		em.damage(e, 300.0, Vector3.ZERO)
	slowmo(1.0, 0.3)
	Sfx.play("evolve", Vector3.INF, 1.0, 0.0)
	ui.banner("İKİNCİ NEFES", "Daha bitmedi", Color(0.6, 1.0, 0.75), 1.6)
	return true

func restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and state == S_PLAY and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := 0.0024 * Settings.mouse_sens
		cam_yaw -= ev.relative.x * s
		mouse_ms = Time.get_ticks_msec()
		cam_pitch -= ev.relative.y * s * (-1.0 if Settings.invert_y else 1.0)
		cam_pitch = clampf(cam_pitch, -1.25, -0.12)
	if ev.is_action_pressed("pause"):
		if state == S_PLAY:
			pause()
		elif state == S_PAUSE:
			resume()
	if ev.is_action_pressed("restart") and state == S_END and Time.get_ticks_msec() - end_ms > 1200:
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
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	evo_t = maxf(0.0, evo_t - real_dt)
	if slow_t > 0.0 and hitstop_t <= 0.0:
		slow_t -= real_dt
		var base_ts := float(demo_cfg.get("time_scale", 1.0)) if demo else 1.0
		Engine.time_scale = base_ts * (slow_scale if slow_t > 0.0 else 1.0)
	_update_camera(dt)
	Sfx.listener_pos = player.global_position
	if state != S_PLAY:
		return
	if won:
		dawn_k = minf(1.0, dawn_k + dt * 0.35)
	elif (pending_chest > 0 or (pending_levels > 0 and levelup_gap <= 0.0)) and not player.dead and not _cinematic():
		_open_levelup(pending_chest > 0)
		return
	levelup_gap -= dt
	world.update_time(t, dawn_k)
	world.follow(player.global_position)
	lamp.light_energy = 1.6 + world.night * 1.4
	lamp.omni_range = 7.0 + world.night * 6.0
	t += dt
	if demo:
		_demo_shots()
	if demo and demo_cfg.has("pause_at") and t >= float(demo_cfg["pause_at"]) and not events_done.has("demo_pause"):
		events_done["demo_pause"] = true
		pause()
		ui.hide_pause()  # demo freeze is for screenshots: keep the frame clean
		return
	# Contact damage starts at 75 % and reaches full strength at 3:00.
	# From 5:30 it climbs faster again, so a strong build still gets hit late.
	enemy_dmg_mult = (0.75 + 0.25 * minf(1.0, t / 180.0)) * (1.0 + t / 600.0 + maxf(0.0, t - 330.0) / 500.0)
	# The late term answers evolutions: from about 5:30 the night horde hardens.
	# Before 4:00 the linear term grows as a curve, so the starting bolt still
	# kills a crawler in one shot for the first two minutes.
	var lin := t / 220.0 if t >= 240.0 else pow(t / 240.0, 2.0) * 240.0 / 220.0
	em.hp_mult = 1.0 + lin + pow(t / 400.0, 2.0) + pow(maxf(0.0, t - 330.0) / 148.0, 2.2)
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
		var n := mini(crumble.size(), 12)
		for k in n:
			var o = crumble.pop_back()
			if o.alive:
				em.dissolve(o)
				fx.burst(o.pos + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.5), 4, 1.0)
		if boss_dead_t < 0.0:
			_end_run(true)
	ui.update_hud()

## Demo only: save frames at the run times listed in `shots` (seconds, comma
## separated) into `shot_dir`, and quit at `quit_at`.
var _shot_list: Array = []
func _demo_shots() -> void:
	if _shot_list.is_empty() and demo_cfg.has("shots") and not events_done.has("shots_parsed"):
		events_done["shots_parsed"] = true
		for s in str(demo_cfg["shots"]).split(",", false):
			_shot_list.append(float(s))
		_shot_list.sort()
	if not _shot_list.is_empty() and t >= _shot_list[0]:
		var at: float = _shot_list.pop_front()
		var dir := str(demo_cfg.get("shot_dir", "user://shots"))
		DirAccess.make_dir_recursive_absolute(dir)
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_jpg("%s/t%03d.jpg" % [dir, int(at)], 0.85)
			print("SHOT t=%d" % int(at))
	if demo_cfg.has("quit_at") and t >= float(demo_cfg["quit_at"]):
		print("DEMO_QUIT t=%.0f hp=%.0f lv=%d" % [t, player.hp, level])
		get_tree().quit()

func _update_camera(dt: float) -> void:
	player.cam_yaw = cam_yaw
	if hero_ring:
		var hp3: Vector3 = player.global_position
		hero_ring.global_position = Vector3(hp3.x, 0.07, hp3.z)
	var target: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	var bs = em.boss
	var boss_live: bool = bs != null and bs.alive and not won
	if boss_live:
		# Frame hero and giant together: the pivot leans toward the boss.
		var to_b: Vector3 = bs.pos - player.global_position
		to_b.y = 0
		target += to_b.limit_length(20.0) * 0.3
	cam_rig.position = cam_rig.position.lerp(target, minf(1.0, dt * 6.0 if boss_live else dt * 12.0))
	cam_rig.rotation.y = cam_yaw
	cam_pitch_node.rotation.x = cam_pitch
	var rdt := dt / maxf(Engine.time_scale, 0.05)
	var want := 11.0
	if boss_live:
		want = 12.5
		# With the mouse at rest, turn slowly toward a boss that left the view,
		# so a keyboard-only player never fights an off-screen giant.
		if cam_look == null and Time.get_ticks_msec() - mouse_ms > 1500:
			var tb: Vector3 = bs.pos - player.global_position
			var yaw_b := atan2(-tb.x, -tb.z)
			var diff := angle_difference(cam_yaw, yaw_b)
			if absf(diff) > 0.9 and Vector2(tb.x, tb.z).length() > 4.0:
				cam_yaw += clampf(diff, -rdt * 1.2, rdt * 1.2)
	if evo_t > 0.0:
		want = 6.5
	cam_dist = lerpf(cam_dist, want, minf(1.0, rdt * 3.0))
	if cam_look != null:
		var to: Vector3 = cam_look - player.global_position
		if Vector2(to.x, to.z).length() > 0.5:
			var yaw_to := atan2(-to.x, -to.z)
			cam_yaw = lerp_angle(cam_yaw, yaw_to, minf(1.0, rdt * 3.5))
	spring.spring_length = cam_dist
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

## Bosses are immune to screen-clearing effects (lanterns, evolutions, revive).
func _is_big(e) -> bool:
	return e.type == EnemyManager.BOSS or e.type == EnemyManager.SERPENT or e.type == EnemyManager.SEG

## Level-ups wait while an evolution or the boss entrance is on screen.
func _cinematic() -> bool:
	return evo_t > 0.0 or boss_intro_t > 0.0 or won

func slowmo(real_seconds: float, scale: float) -> void:
	slow_t = maxf(slow_t, real_seconds)
	slow_scale = scale

func shake(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)

func hitstop(d: float) -> void:
	if hitstop_t > 0.0 or state != S_PLAY:
		return
	hitstop_t = d
	Engine.time_scale = 0.05

# ---------------------------------------------------------------- director

func _target_alive() -> float:
	# The first three minutes are tuned for someone who has never played: about
	# 40 % fewer enemies, then the curve rejoins the old one by 5:00.
	var pts := [[0.0, 6.0], [45.0, 14.0], [120.0, 33.0], [200.0, 70.0], [300.0, 150.0], [360.0, 190.0], [480.0, 280.0], [570.0, 360.0], [600.0, 380.0]]
	for i in pts.size() - 1:
		if t < pts[i + 1][0]:
			var k: float = (t - pts[i][0]) / (pts[i + 1][0] - pts[i][0])
			return lerpf(pts[i][1], pts[i + 1][1], k)
	return 70.0  # during the boss: thinner support waves

func _pick_type() -> int:
	var types := [EnemyManager.CRAWLER, EnemyManager.MOTH, EnemyManager.BRUTE, EnemyManager.SPITTER, EnemyManager.KESE, EnemyManager.BOYNUZ]
	var w := [1.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	# Moths are fast and stick to you: they arrive gradually from 1:15.
	if t > 75.0: w[1] = lerpf(0.15, 0.45, clampf((t - 75.0) / 105.0, 0.0, 1.0))
	if t > 170.0: w[2] = 0.10 + minf(t / 4000.0, 0.10)
	if t > 230.0: w[3] = 0.14
	if t > 160.0: w[4] = 0.10 + minf((t - 160.0) / 4000.0, 0.08)
	# Chargers are a threat to read, not a crowd: keep only a few at a time.
	if t > 300.0 and em.count_type(EnemyManager.BOYNUZ) < 3 + int(t / 150.0): w[5] = 0.05
	var tot := 0.0
	for x in w: tot += x
	var r := randf() * tot
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			return types[i]
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
	if won or boss_dead_t >= 0.0:
		return  # the boss is down: no more spawns while the victory plays out
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
		# Early elites are big crawlers; brutes and spitters wait for the serpent.
		var et := 0 if t < 300.0 else (2 if randf() < 0.6 else 3)
		em.spawn(et, _spawn_pos(18.0, 22.0), true)
		toast("Parlayan bir düşman geliyor. Onu yen, sandık düşürür!")
	# Chests on the map
	chest_t -= dt
	if chest_t <= 0.0:
		chest_t = 55.0
		if pickups.chests.size() < 2 and not boss_spawned:
			var p := _chest_spot()
			pickups.spawn_chest(p, Models.prop(chest_model_path, 1.1))
			toast("Adada bir sandık belirdi. Işık sütununu takip et!")
	_event(150.0, "ring1")
	_event(345.0, "ring2")  # not on top of the serpent's arrival
	_event(450.0, "ring3")
	_event(240.0, "swarm1")
	_event(420.0, "swarm2")
	_event(540.0, "swarm3")
	crystal_t -= dt
	if crystal_t <= 0.0:
		crystal_t = 40.0
		if em.count_type(EnemyManager.CRYSTAL) < 8:
			_grow_crystal()
	_event(480.0, "night_raid")
	_event(290.0, "serpent_warn")
	_event(300.0, "serpent")
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
	elif id == "tip_jump":
		toast("Sıkıştın mı? Shift ile kay, kayarken hasar almazsın.", 4.5)
	elif id == "night_raid":
		# Gece Akını: elites from three sides and a pack of chargers.
		toast("Gece Akını! Parlayanlar her yandan geliyor.", 4.0)
		shake(0.3)
		var base := randf() * TAU
		for k in 3:
			var a := base + TAU * k / 3.0
			var et: int = [EnemyManager.BRUTE, EnemyManager.SPITTER, EnemyManager.BOYNUZ][k]
			em.spawn(et, pp + Vector3(cos(a), 0, sin(a)) * 20.0, true)
		for k in 4:
			var a := base + TAU * (k + 0.5) / 4.0
			em.spawn(EnemyManager.BOYNUZ, pp + Vector3(cos(a), 0, sin(a)) * 24.0)
	elif id == "serpent_warn":
		toast("Toprak kayıyor... bir şey yükseliyor!", 3.5)
		shake(0.3)
		Sfx.play("quake", Vector3.INF, 0.8, 0.0)
	elif id == "serpent":
		serpent.spawn(_spawn_pos(18.0, 22.0))
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
	var pp: Vector3 = player.global_position
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var p := pp + fwd * 17.0
	var pl := Vector2(p.x, p.z).length()
	if pl > world.island_radius - 8.0:
		p = Vector3(p.x, 0, p.z) * ((world.island_radius - 8.0) / pl)
	# The serpent leaves the stage if it is still around.
	if serpent.active and not serpent.dying:
		serpent.retreat()
	var e = em.spawn(EnemyManager.BOSS, p)
	# Provisional HP; _boss_calibrate resizes it from damage actually landed on the boss.
	e.max_hp = 20000.0
	boss_fight_t = 0.0
	boss_taken = 0.0
	boss_calibrated = false
	e.hp = e.max_hp
	var node := Models.prop("res://art/models/boss.glb", 9.5)
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
uniform float warn = 0.0;
uniform float rage = 0.0;
varying vec3 obj;
void vertex() {
	// World units, so the crack size does not depend on the model's import scale.
	obj = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - MODEL_MATRIX[3].xyz;
}
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.6 + 0.4 * sin(TIME * 30.0);
	// Lava cracks: thin bands where two warped sine fields cross zero.
	vec3 q = obj * 0.9;
	float a = sin(q.x * 2.1 + sin(q.y * 1.3 + TIME * 0.6) * 1.6 + q.z * 0.7);
	float b = sin(q.z * 2.3 + sin(q.y * 1.7 - TIME * 0.5) * 1.4 - q.x * 0.6);
	float crack = (1.0 - smoothstep(0.0, 0.16, abs(a))) + (1.0 - smoothstep(0.0, 0.12, abs(b)));
	float throb = 0.75 + 0.25 * sin(TIME * (3.0 + rage * 4.0) + q.y);
	vec3 lava = vec3(1.0, 0.42, 0.06) * clamp(crack, 0.0, 1.0) * throb * (0.9 + rage * 0.8);
	ALBEDO = vec3(1.0, 0.85, 0.8) * flash * 0.1 + vec3(1.0, 0.1, 0.05) * warn * pulse * 0.9 + vec3(1.0, 0.5, 0.15) * rim * 0.55 + lava;
}
"""
	ov.shader = osh
	# Thin out where it stands between the camera and the hero, like the props.
	world.apply_fade(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = ov
	node.set_meta("overlay", ov)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.15)
	glow.light_energy = 3.0
	glow.omni_range = 10.0
	glow.position.y = 4.0
	node.add_child(glow)
	add_child(node)
	em.boss_node = node
	pickups.set_beams(false)
	ui.show_boss_bar(true)
	# Entrance: it rises out of the ground in slow motion, the camera turns to it
	# and a shockwave clears the crowd around the hero.
	node.position = Vector3(p.x, -10.0, p.z)
	var tw := create_tween()
	tw.tween_property(node, "position:y", 0.0, 1.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	boss_intro_t = 2.4
	cam_look = p
	slowmo(2.2, 0.35)
	boss_phase = 1
	boss_state = "walk"
	boss_timer = 4.0
	fx.ring(p, 16.0, Color(1.0, 0.3, 0.4), 0.8, 0.2, 0.3)
	for k in 6:
		fx.dust(p + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), 10)
	for o in em.query(pp, 26.0):
		if _is_big(o) or o.type == EnemyManager.CRYSTAL:
			continue
		var away: Vector3 = o.pos - pp
		away.y = 0
		o.vel += away.normalized() * 30.0
		em.damage(o, o.max_hp * 0.6)
	Sfx.play("quake", Vector3.INF, 1.0, 0.0)
	Sfx.play("roar", Vector3.INF, 1.0, 0.0)
	shake(0.9)
	ui.banner("SON SAVAŞ", "Kül Devi", Color(1.0, 0.55, 0.2), 2.2)

## Called by EnemyManager for the boss each frame. Returns a move speed factor.
func boss_ai(e, dt: float, dist: float, dx: float, dz: float) -> float:
	_boss_calibrate(e, dt)
	boss_warn = maxf(0.0, boss_warn - dt * 4.0)
	_boss_hazards(dt)
	if boss_intro_t > 0.0:
		boss_intro_t -= dt / maxf(Engine.time_scale, 0.05)
		if boss_intro_t <= 0.0:
			cam_look = null
		return 0.0
	var frac: float = e.hp / maxf(e.max_hp, 1.0)
	var ph := 1 if frac > 0.66 else (2 if frac > 0.33 else 3)
	if ph > boss_phase:
		boss_phase = ph
		_boss_phase_change(e, ph)
	var enraged: bool = boss_phase >= 3
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
				if boss_phase >= 2 and r < 0.3:
					boss_state = "rain" if randf() < 0.5 else "fissure"
					boss_attack_t = 0.9
					if boss_state == "rain":
						_boss_rain()
					else:
						_boss_fissure(e)
					return 0.0
				r = randf()
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
			if boss_timer <= 0.0:
				boss_timer = 0.4 if not enraged else 0.28
				var n := 14 if not enraged else 20
				var off := randf() * TAU
				for i in n:
					var a := off + TAU * i / n
					em.add_bullet(e.pos + Vector3(0, 1.2, 0), Vector3(cos(a), 0, sin(a)) * 8.0, 5.0)
			if boss_attack_t <= 0.0:
				_boss_next(enraged)
			return 0.3
		"charge_wind":
			boss_attack_t -= dt
			boss_warn = 1.0
			if Engine.get_process_frames() % 4 == 0:
				fx.burst(e.pos + Vector3(0, 3.0, 0), Color(1.0, 0.45, 0.1), 3, 1.0)
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
		"rain", "fissure":
			boss_attack_t -= dt
			if boss_attack_t <= 0.0:
				_boss_next(enraged)
			return 0.0
		"summon":
			boss_attack_t -= dt
			if boss_attack_t <= 0.0:
				for i in 10:
					var a := TAU * i / 10.0
					var kind := EnemyManager.KESE if enraged and i % 3 == 0 else (0 if i % 2 == 0 else 1)
					em.spawn(kind, e.pos + Vector3(cos(a), 0, sin(a)) * 5.0)
				fx.ring(e.pos, 6.0, Color(0.8, 0.3, 1.0), 0.5, 0.2, 0.2)
				_boss_next(enraged)
			return 0.0
	return 1.0

## After 8 s of fighting, size the boss so the rest lasts about 50 s at the
## damage rate this build actually lands on it (single-target damage differs
## from horde damage by an order of magnitude, so it must be measured here).
func _boss_calibrate(e, dt: float) -> void:
	if boss_calibrated:
		return
	# The clock starts at the first hit, so walking into range does not count.
	if boss_taken > 0.0:
		boss_fight_t += dt
	if boss_fight_t < 8.0 and e.hp > e.max_hp * 0.25:
		return
	boss_calibrated = true
	var rate := boss_taken / maxf(boss_fight_t, 0.1)
	var total := maxf(9000.0, boss_taken + rate * 62.0)
	e.max_hp = total
	e.hp = total - boss_taken

func on_boss_hit(dealt: float) -> void:
	boss_taken += dealt

func _boss_phase_change(e, ph: int) -> void:
	Sfx.play("roar", Vector3.INF, 1.0, 0.0, 0.85)
	shake(0.6)
	fx.ring(e.pos, 14.0, Color(1.0, 0.25, 0.3), 0.6, 0.15, 0.3)
	var pp: Vector3 = player.global_position
	for o in em.query(e.pos, 12.0):
		if o.type != EnemyManager.BOSS:
			o.vel += (o.pos - e.pos).normalized() * 18.0
	boss_warn = 1.0
	if ph == 2:
		toast("Kül Devi gökten kül yağdırıyor! Kırmızı halkalardan çık.", 3.5)
	else:
		toast("Kül Devi öfkelendi!", 3.0)
	boss_state = "walk"
	boss_timer = 1.0
	if pp.distance_to(e.pos) < 6.0:
		player.velocity += (pp - e.pos).normalized() * 12.0

## Ash meteors: a ring of telegraphs closing in on the hero, one after another.
func _boss_rain() -> void:
	var pp: Vector3 = player.global_position
	Sfx.play("roar", Vector3.INF, 0.6, 0.1, 1.2)
	var n := 12 if boss_phase < 3 else 16
	for i in n:
		var a := randf() * TAU
		var d := randf_range(0.0, 9.0) if i % 3 != 0 else 0.0
		var p := pp + Vector3(cos(a) * d, 0, sin(a) * d)
		var delay := 0.9 + i * 0.12
		fx.telegraph(p, 2.6, delay)
		boss_rain.append([p, delay])

## Fissures: lanes radiating from the boss, one aimed at the hero.
func _boss_fissure(e) -> void:
	var pp: Vector3 = player.global_position
	var to: Vector3 = pp - e.pos
	to.y = 0
	var base := atan2(to.x, to.z)
	var n := 5 if boss_phase < 3 else 7
	for i in n:
		var a := base + TAU * i / n
		var d := Vector3(sin(a), 0, cos(a))
		fx.lane(e.pos, d, 26.0, 2.4, 1.1)
		boss_fissures.append([e.pos, d, 1.1])
	Sfx.play("quake", Vector3.INF, 0.7, 0.05)

func _boss_hazards(dt: float) -> void:
	var pp: Vector3 = player.global_position
	var i := 0
	while i < boss_rain.size():
		boss_rain[i][1] -= dt
		if boss_rain[i][1] <= 0.0:
			var p: Vector3 = boss_rain[i][0]
			fx.ring(p, 2.6, Color(1.0, 0.35, 0.25), 0.3, 0.4, 0.2)
			fx.burst(p + Vector3(0, 0.5, 0), Color(0.5, 0.4, 0.45), 10, 1.4)
			fx.burst(p + Vector3(0, 0.5, 0), Color(1.0, 0.45, 0.2), 6, 1.2)
			Sfx.play("meteor", p, 0.5)
			if Vector2(pp.x - p.x, pp.z - p.z).length() < 2.6 and pp.y < 1.5:
				player.hurt(20.0, p)
			boss_rain.remove_at(i)
			continue
		i += 1
	i = 0
	while i < boss_fissures.size():
		var f: Array = boss_fissures[i]
		f[2] -= dt
		if f[2] <= 0.0:
			var o: Vector3 = f[0]
			var d: Vector3 = f[1]
			for k in 7:
				fx.burst(o + d * (3.0 + k * 3.4) + Vector3(0, 0.3, 0), Color(1.0, 0.4, 0.2), 4, 1.4)
			var rel: Vector3 = pp - o
			rel.y = 0
			var along: float = rel.dot(d)
			var side: float = (rel - d * along).length()
			if along > 0.0 and along < 26.0 and side < 1.2 and pp.y < 1.0:
				player.hurt(26.0, pp - d)
			boss_fissures.remove_at(i)
			shake(0.15)
			continue
		i += 1

func _boss_next(enraged: bool) -> void:
	boss_state = "walk"
	boss_timer = randf_range(2.0, 3.0) if enraged else randf_range(3.0, 4.2)

# ---------------------------------------------------------------- shrines

func _update_shrines(dt: float) -> void:
	var pp: Vector3 = player.global_position
	for s in shrines:
		var d := Vector2(pp.x - s["p"].x, pp.z - s["p"].z).length()
		if s["lit"]:
			s["light"].light_energy = 5.0 + world.night * 4.0
			s["light"].omni_range = 9.0 + world.night * 5.0
			# A lit lantern is a safe pool of light: it heals while you stand in it.
			if d < 7.0 and not player.dead:
				player.heal(4.0 * dt)
			continue
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
		if not _is_big(e):
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
	toast("Fener yandı! " + msg.trim_suffix("!") + ". Işığında canın dolar.", 4.5)

# ---------------------------------------------------------------- xp, level-ups

func on_enemy_killed(e) -> void:
	if e.type == EnemyManager.BOSS:
		kills += 1
		boss_dead_t = 5.5
		won = true
		ui.show_boss_bar(false)
		# The whole horde turns to light, a few at a time.
		crumble.clear()
		for o in em.enemies:
			if o.alive and o.type != EnemyManager.BOSS:
				crumble.append(o)
		em.bullets.clear()
		boss_rain.clear()
		boss_fissures.clear()
		slowmo(2.6, 0.3)
		cam_look = e.pos
		evo_t = 2.2
		Sfx.play("roar", Vector3.INF, 1.0, 0.0, 0.8)
		shake(1.0)
		_boss_death_fx(e.pos, 0)
		if demo:
			print("BOSS_DEAD t=%.1f" % t)
		return
	kills += 1
	var v: int = em.TYPES[e.type]["xp"]
	if e.elite:
		pickups.spawn_chest(e.pos, Models.prop(chest_model_path, 1.1))
		v *= 5
	pickups.gem(e.pos, v)
	var r := randf()
	# Fruit is common early, while a new player is still learning to dodge.
	var fruit := lerpf(0.03, 0.009, clampf((t - 180.0) / 120.0, 0.0, 1.0))
	if r < fruit or e.elite:
		pickups.item(e.pos, "heal")
	elif r < fruit + 0.003:
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
	if pending_levels > 0 and levelup_gap <= 0.0 and state == S_PLAY and not player.dead and not _cinematic():
		_open_levelup(false)

## Early levels come quickly so the first minute already feels like growth.
static func xp_needed(lv: int) -> float:
	var n := float(lv - 1)
	# Steepens from level 15: slots are limited, so a run should top out around
	# level 50 and evolutions land in the middle of the run.
	return 4.0 + n * 3.5 + pow(n, 1.4) + 6.0 * pow(maxf(0.0, n - 14.0), 1.8)

func _grow_crystal() -> void:
	if world.crystal_spots.is_empty():
		return
	var pp: Vector3 = player.global_position if player else Vector3.ZERO
	for tries in 6:
		var p: Vector3 = world.crystal_spots[randi() % world.crystal_spots.size()]
		if p.distance_to(pp) < 12.0:
			continue
		var taken := false
		for e in em.enemies:
			if e.alive and e.type == EnemyManager.CRYSTAL and e.pos.distance_to(p) < 3.0:
				taken = true
				break
		if taken:
			continue
		var c = em.spawn(EnemyManager.CRYSTAL, p)
		if c:
			c.max_hp = 70.0 + t * 0.6
			c.hp = c.max_hp
			c.yaw = randf() * TAU
		return

## Amber crystals are the exploration reward: break one for a small jackpot.
func on_crystal_broken(e) -> void:
	var p: Vector3 = e.pos
	crystals_broken += 1
	fx.burst(p + Vector3(0, 1.0, 0), Color(1.0, 0.75, 0.25), 30, 2.2)
	fx.ring(p, 4.0, Color(1.0, 0.8, 0.3), 0.4, 0.2, 0.2)
	Sfx.play("crystal", p, 1.0, 0.1)
	for i in 7:
		pickups.gem(p + Vector3(randf_range(-2.2, 2.2), 0, randf_range(-2.2, 2.2)), 3 + int(t / 60.0))
	var r := randf()
	if r < 0.35:
		pickups.item(p + Vector3(1.0, 0, 0), "heal")
	elif r < 0.55:
		pickups.item(p + Vector3(1.0, 0, 0), "magnet")
	elif r < 0.68:
		pickups.spawn_chest(p, Models.prop(chest_model_path, 1.1))

func open_chest(p: Vector3) -> void:
	chests_opened += 1
	Sfx.play("chest", Vector3.INF, 1.0, 0.0)
	fx.burst(p + Vector3(0, 1, 0), Color(1.0, 0.85, 0.35), 36, 2.2)
	for i in 8:
		pickups.gem(p + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 5)
	pending_chest += 1
	if state == S_PLAY and not player.dead and not _cinematic():
		_open_levelup(true)

func _open_levelup(chest: bool) -> void:
	cur_chest = chest or pending_chest > 0
	var choices := roll_choices(cur_chest)
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

## Weapon ids ready to evolve: max level, partner passive owned, not evolved yet.
func evo_ready() -> Array:
	var out: Array = []
	for id in weapons.lv.keys():
		if weapons.lv[id] == Upgrades.WEAPON_MAX and passives.get(Upgrades.EVOS[id]["partner"], 0) > 0:
			out.append(id)
	return out

func roll_choices(chest := false) -> Array:
	var pool: Array = []   # [id, kind, weight]
	var owned := weapons.lv.size()
	var owned_p := passives.size()
	for id in Upgrades.WEAPONS.keys():
		var l := weapons.level(id)
		if l > 0 and l < Upgrades.WEAPON_MAX:
			pool.append([id, "w", 2.2])
		elif l == 0 and owned < Upgrades.MAX_WEAPONS:
			pool.append([id, "w", 2.6 if owned < 3 else 1.4])
	for id in Upgrades.PASSIVES.keys():
		var l: int = passives.get(id, 0)
		if l >= Upgrades.passive_cap(id):
			continue
		if l == 0 and owned_p >= Upgrades.MAX_PASSIVES:
			continue
		var w := 0.8 if id == "amount" else 1.6
		# Nudge toward the partner of a weapon you already invest in.
		var partner_of := Upgrades.evolves_weapon(id)
		if partner_of != "" and weapons.level(partner_of) >= 4:
			w *= 1.8
		pool.append([id, "p", w])
	var out: Array = []
	# A chest always offers a ready evolution first, from 4:00 on, so the big
	# moment lands mid-run even when the gentler opening speeds up levelling.
	if chest and t >= EVO_FROM:
		for id in evo_ready():
			if out.size() < 3:
				out.append({"id": id, "kind": "e"})
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
			var fresh: Array = []
			for i in pool.size():
				if pool[i][1] == "w" and weapons.level(pool[i][0]) == 0:
					fresh.append(i)
			if not fresh.is_empty():
				pick = fresh[randi() % fresh.size()]
		out.append({"id": pool[pick][0], "kind": pool[pick][1]})
		pool.remove_at(pick)
	if out.is_empty():
		out.append({"id": "filler", "kind": "x"})
	return out

func apply_choice(c: Dictionary) -> void:
	var id: String = c["id"]
	if c["kind"] == "x":
		st.dmg *= 1.04
		player.max_hp += 5.0
		player.heal(15.0)
		return
	if c["kind"] == "e":
		weapons.lv[id] = Upgrades.EVO_LEVEL
		evolved.append(id)
		_evolve_moment(id)
		return
	if c["kind"] == "w":
		weapons.add_weapon(id)
		if weapons.level(id) >= Upgrades.WEAPON_MAX and state != S_TITLE:
			var partner: String = Upgrades.EVOS[id]["partner"]
			if passives.get(partner, 0) > 0:
				toast("%s uyandı! Bir sandık onu dönüştürecek." % Upgrades.WEAPONS[id]["name"], 4.0)
			else:
				toast("%s uyandı! %s alırsan sandıkta dönüşür." % [Upgrades.WEAPONS[id]["name"], Upgrades.PASSIVES[partner]["name"]], 4.5)
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
	if state != S_LEVELUP:
		return  # e.g. a late bot pick after the run already ended
	apply_choice(c)
	Sfx.play("select", Vector3.INF, 1.0, 0.0)
	fx.burst(player.global_position + Vector3(0, 1, 0), Color(1.0, 0.85, 0.4), 14, 1.2)
	if pending_chest > 0:
		pending_chest -= 1
	elif pending_levels > 0:
		pending_levels -= 1
	# After an evolution the cinematic plays first; _process reopens the rest.
	if (pending_chest > 0 or pending_levels > 0) and not _cinematic():
		cur_chest = pending_chest > 0
		var ch := roll_choices(cur_chest)
		if not ch.is_empty():
			ui.show_levelup(ch, cur_chest)
			if demo and bot:
				bot.pick_soon(ch)
			return
		pending_levels = 0
		pending_chest = 0
	ui.hide_levelup()
	# Several level-ups in quick succession open as one screen instead of five.
	levelup_gap = 6.0
	state = S_PLAY
	get_tree().paused = false
	if not demo:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Brief invulnerability and a soft push so a pick never drops you into a hit.
	player.invuln_t = maxf(player.invuln_t, 0.6)
	var pp: Vector3 = player.global_position
	fx.ring(pp, 6.0, Color(1.0, 0.75, 0.3), 0.35, 0.0, 0.1)
	for e in em.query(pp, 6.0):
		if e.type == EnemyManager.BOSS:
			continue
		var away: Vector3 = e.pos - pp
		away.y = 0
		e.vel += away.normalized() * 14.0

func reroll() -> void:
	if state != S_LEVELUP or rerolls <= 0:
		return
	rerolls -= 1
	Sfx.play("ui", Vector3.INF, 1.0, 0.0)
	var ch := roll_choices(cur_chest)
	ui.show_levelup(ch, cur_chest)
	if demo and bot:
		bot.pick_soon(ch)

## The big beat of a run: slow time, pull the camera in, pillar of light.
func _evolve_moment(id: String) -> void:
	var evo: Dictionary = Upgrades.EVOS[id]
	var pp: Vector3 = player.global_position
	evo_t = 1.6
	slowmo(1.6, 0.25)
	fx.pillar(pp, evo["color"])
	fx.ring(pp, 14.0, evo["color"], 0.8, 0.3, 0.25)
	fx.ring(pp, 8.0, Color(1, 1, 1), 0.5, 0.2, 0.15)
	fx.burst(pp + Vector3(0, 1.2, 0), evo["color"], 60, 3.0)
	Sfx.play("evolve", Vector3.INF, 1.0, 0.0)
	shake(0.5)
	for e in em.query(pp, 14.0):
		if _is_big(e):
			continue
		var away: Vector3 = e.pos - pp
		away.y = 0
		e.vel += away.normalized() * 22.0
		em.damage(e, 200.0 * st.dmg, Vector3.ZERO)
	var first := false
	if not demo and not meta.discovered.has(id):
		meta.discovered.append(id)
		meta.save_cfg()
		new_discoveries.append(id)
		first = true
	ui.banner("DÖNÜŞÜM  ·  YENİ KEŞİF" if first else "DÖNÜŞÜM", evo["name"], evo["color"])
	if demo:
		print("EVO %s t=%.0f lv=%d" % [id, t, level])

func on_slide(p: Vector3, dir: Vector3) -> void:
	weapons.on_slide(p, dir)

func toast(msg: String, dur := 3.0) -> void:
	if ui:
		ui.toast(msg, dur)

# ---------------------------------------------------------------- end

## Bursts of light out of the falling giant, then the final blast at dawn.
func _boss_death_fx(p: Vector3, step: int) -> void:
	if step < 6:
		var q := p + Vector3(randf_range(-2.5, 2.5), randf_range(2.0, 8.0), randf_range(-2.5, 2.5))
		fx.burst(q, Color(1.0, 0.5, 0.15), 30, 2.6)
		fx.burst(q, Color(1.0, 0.85, 0.5), 14, 2.0)
		Sfx.play("explode", Vector3.INF, 0.9, 0.1, 0.8)
		shake(0.35)
		get_tree().create_timer(0.28, true, false, true).timeout.connect(_boss_death_fx.bind(p, step + 1))
		return
	fx.pillar(p, Color(1.0, 0.8, 0.5))
	fx.ring(p, 30.0, Color(1.0, 0.85, 0.5), 1.0, 0.2, 0.3)
	for i in 8:
		fx.burst(p + Vector3(randf_range(-3, 3), randf_range(1, 8), randf_range(-3, 3)), Color(1.0, 0.6, 0.25), 40, 3.2)
	Sfx.play("slam", Vector3.INF, 1.0, 0.0)
	Sfx.play("quake", Vector3.INF, 1.0, 0.0)
	shake(1.0)
	if em.boss_node:
		var tw := create_tween()
		tw.tween_property(em.boss_node, "scale", Vector3(1.4, 0.02, 1.4), 1.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	ui.banner("ŞAFAK SÖKÜYOR", "Ada kurtuldu", Color(1.0, 0.85, 0.5), 2.5)
	cam_look = null

func on_player_died() -> void:
	if demo:
		var near := {}
		for e in em.query(player.global_position, 5.0):
			near[em.TYPES[e.type]["name"]] = near.get(em.TYPES[e.type]["name"], 0) + 1
		print("DIED t=%.0f lv=%d near=%s build=%s %s" % [t, level, near, weapons.lv, passives])
	shake(0.6)
	Sfx.play("roar", Vector3.INF, 0.5, 0.0)
	get_tree().create_timer(1.4, true, false, true).timeout.connect(_end_run.bind(false))

func _end_run(victory: bool) -> void:
	if state == S_END:
		return
	victory = victory or won
	state = S_END
	end_ms = Time.get_ticks_msec()
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
		"crystals": crystals_broken, "serpent": serpent_killed,
		"evolutions": evolved.size(), "new_discoveries": new_discoveries.duplicate(),
		"weapons": weapons.lv.duplicate(), "passives": passives.duplicate(),
		"weapon_damage": weapon_damage.duplicate(),
		"best": rec, "new_best": new_best, "demo": demo,
	}
	var earned: int = meta.reward(summary)
	summary["kor"] = earned
	if not demo:
		meta.kor += earned
		meta.runs += 1
		meta.save_cfg()
	summary["kor_total"] = meta.kor
	ui.show_end(summary)
	if demo:
		print("DEMO_END ", JSON.stringify({"victory": victory, "time": t, "kills": kills, "level": level, "damage": stats_total_damage}))

func _load_record() -> Dictionary:
	var c := ConfigFile.new()
	var d := {"best_time": 0.0, "best_kills": 0, "wins": 0, "runs": 0}
	if Settings.load_plain(c, RECORD_PATH) == OK:
		for k in d.keys():
			var v = c.get_value("r", k, d[k])
			if v is int or v is float:
				d[k] = maxf(0.0, float(v)) if d[k] is float else maxi(0, int(v))
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
