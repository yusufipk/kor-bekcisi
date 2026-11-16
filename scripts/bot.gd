extends Node
## Demo autopilot for testing (enabled by user://demo.cfg in debug builds only).
## Steers away from enemies, toward crystals, chests and unlit lanterns; jumps
## and slides when cornered; picks upgrades. Never writes the record file.

var g
var pick_t := -1.0
var pending: Array = []
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var log_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.inst

func pick_soon(choices: Array) -> void:
	pending = choices
	pick_t = 0.25

func _process(dt: float) -> void:
	var rdt := dt / maxf(Engine.time_scale, 0.01)
	if pick_t >= 0.0:
		pick_t -= rdt
		if pick_t < 0.0 and pending.size() > 0:
			# Prefer weapon upgrades and damage, like a reasonable player.
			var best = pending[0]
			for c in pending:
				if c["kind"] == "w" and g.weapons.level(c["id"]) > 0:
					best = c
					break
			pending = []
			g.choose(best)
	if g.state == Game.S_END and g.demo_cfg.get("autoquit", false):
		get_tree().quit()

func _physics_process(dt: float) -> void:
	if g.state != Game.S_PLAY:
		return
	var p = g.player
	var pp: Vector3 = p.global_position
	var steer := Vector3.ZERO
	var danger := 0.0
	for e in g.em.query(pp, 9.0):
		var d: Vector3 = pp - e.pos
		d.y = 0
		var l := maxf(d.length(), 0.3)
		var w: float = (3.0 if e.type == EnemyManager.BOSS else 1.0) / (l * l)
		steer += d / l * w * 6.0
		danger += w
	for b in g.em.bullets:
		var d: Vector3 = pp - b[0]
		d.y = 0
		var l := d.length()
		if l < 4.0:
			steer += d.normalized() * 2.0 / maxf(l, 0.5)
	# Goals
	var goal = null
	if g.pickups.chests.size() > 0:
		goal = g.pickups.chests[0].position
	else:
		for s in g.shrines:
			if not s["lit"]:
				if goal == null or pp.distance_to(s["p"]) < pp.distance_to(goal):
					goal = s["p"]
	if g.pickups.g_count > 0:
		var best := 1e9
		for i in mini(g.pickups.g_count, 200):
			var d2: float = pp.distance_squared_to(g.pickups.g_pos[i])
			if d2 < best and d2 < 400.0:
				best = d2
				goal = g.pickups.g_pos[i] if danger < 0.6 or goal == null else goal
	if goal != null:
		var to: Vector3 = goal - pp
		to.y = 0
		steer += to.normalized() * (1.2 if danger < 0.8 else 0.4)
	# Stay away from the rim and the middle of obstacles
	var flat := Vector3(pp.x, 0, pp.z)
	if flat.length() > g.world.island_radius - 10.0:
		steer -= flat.normalized() * 2.0
	for o in g.world.obstacles:
		var d = Vector2(pp.x, pp.z) - o[0]
		var l = d.length()
		if l < o[1] + 2.0:
			steer += Vector3(d.x, 0, d.y).normalized() * 1.5
	if steer.length() < 0.1:
		steer = Vector3(sin(Time.get_ticks_msec() * 0.0005), 0, cos(Time.get_ticks_msec() * 0.0005))
	steer = steer.normalized()
	var inv := Basis(Vector3.UP, g.cam_yaw).inverse()
	var local := inv * steer
	p.bot_input = Vector2(local.x, local.z)
	if danger > 1.6 and p.slide_cd <= 0.0:
		p.bot_slide = true
	elif danger > 1.0 and p.is_on_floor() and randf() < 0.05:
		p.bot_jump = true
	# Keep the camera behind the movement direction
	g.cam_yaw = lerp_angle(g.cam_yaw, atan2(-steer.x, -steer.z), dt * 0.8)
	stuck_t += dt
	if stuck_t > 3.0:
		if pp.distance_to(last_pos) < 1.0:
			print("BOT_STUCK at ", pp)
		last_pos = pp
		stuck_t = 0.0
	log_t += dt
	if log_t > 10.0:
		log_t = 0.0
		print("BOT t=%d hp=%d lv=%d kills=%d alive=%d fps=%d" % [g.t, p.hp, g.level, g.kills, g.em.alive_count(), Engine.get_frames_per_second()])
