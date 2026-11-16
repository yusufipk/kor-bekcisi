extends Node
## Demo autopilot for testing (enabled by user://demo.cfg in debug builds only).
## Steers away from enemies, toward crystals, chests and unlit lanterns; jumps
## and slides when cornered; picks upgrades. Never writes the record file.
##
## `bot=circle`, `bot=flee` and `bot=tip` stand in for a first-time player instead: one runs
## in a loop without looking, one only runs away from the crowd it sees, and one
## follows the lantern tip and then loops inside the lantern's light.
## Neither dodges, seeks lanterns or rerolls, and both pick cards at random.

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
	pick_t = float(g.demo_cfg.get("pick_delay", 0.25))

func _process(dt: float) -> void:
	var rdt := dt / maxf(Engine.time_scale, 0.01)
	if pick_t >= 0.0:
		pick_t -= rdt
		if pick_t < 0.0 and pending.size() > 0:
			# Evolutions first, then partner passives, then weapon upgrades.
			if _naive():
				var c = pending[randi() % pending.size()]
				pending = []
				g.choose(c)
				return
			var best = pending[0]
			var score := -1.0
			for c in pending:
				var sc := 0.0
				match c["kind"]:
					"e": sc = 100.0
					"w": sc = 10.0 if g.weapons.level(c["id"]) > 0 else 6.0
					"p":
						var w := Upgrades.evolves_weapon(c["id"])
						sc = 12.0 if w != "" and g.weapons.level(w) >= 3 and g.passives.get(c["id"], 0) == 0 else 4.0
					_: sc = 1.0
				if sc > score:
					score = sc
					best = c
			# Spend a reroll on a weak hand, like a player would.
			if score < 5.0 and g.rerolls > 0:
				pending = []
				g.reroll()
				return
			pending = []
			g.choose(best)
	if g.state == Game.S_END and g.demo_cfg.get("autoquit", false):
		get_tree().quit()

func _naive() -> bool:
	return g.demo_cfg.get("bot", "smart") != "smart"

## A newcomer: circles blindly, or runs from whatever crowd is in front of them.
func _naive_steer(pp: Vector3, dt: float) -> Vector3:
	var flat := Vector3(pp.x, 0, pp.z)
	var steer := Vector3.ZERO
	if g.demo_cfg.get("bot") == "circle":
		var t: float = g.t
		steer = Vector3(cos(t * 0.55), 0, sin(t * 0.55))
	elif g.demo_cfg.get("bot") == "tip":
		# Followed the one on-screen tip: lights the first lantern, then runs
		# loops around it, inside its healing light.
		var sp: Vector3 = g.shrines[0]["p"]
		var to := Vector3(sp.x - pp.x, 0, sp.z - pp.z)
		if not g.shrines[0]["lit"]:
			steer = to.normalized() if to.length() > 1.5 else Vector3.ZERO
		else:
			var tang := Vector3(-to.z, 0, to.x).normalized()
			steer = tang + to.normalized() * clampf((to.length() - 5.0) * 0.3, -1.0, 1.0)
	else:
		var away := Vector3.ZERO
		for e in g.em.query(pp, 14.0):
			if e.type == EnemyManager.CRYSTAL:
				continue
			var d: Vector3 = pp - e.pos
			d.y = 0
			away += d.normalized()
		steer = away.normalized() if away.length() > 0.5 else Vector3(cos(g.t * 0.3), 0, sin(g.t * 0.3))
		# Now and then a panicked jump, never a slide: the newcomer does not know it.
		if away.length() > 4.0 and randf() < 0.01:
			g.player.bot_jump = true
	if flat.length() > g.world.island_radius - 6.0:
		steer -= flat.normalized() * 1.5
	return steer.normalized()

func _physics_process(dt: float) -> void:
	if g.state != Game.S_PLAY:
		return
	var p = g.player
	var pp: Vector3 = p.global_position
	if _naive():
		var ns := _naive_steer(pp, dt)
		var local := Basis(Vector3.UP, g.cam_yaw).inverse() * ns
		p.bot_input = Vector2(local.x, local.z)
		g.cam_yaw = lerp_angle(g.cam_yaw, atan2(-ns.x, -ns.z), dt * 0.8)
		log_t += dt
		if log_t > 10.0:
			log_t = 0.0
			print("BOT t=%d hp=%d lv=%d kills=%d alive=%d fps=%d" % [g.t, p.hp, g.level, g.kills, g.em.alive_count(), Engine.get_frames_per_second()])
		return
	var steer := Vector3.ZERO
	var danger := 0.0
	for e in g.em.query(pp, 9.0):
		var d: Vector3 = pp - e.pos
		d.y = 0
		var l := maxf(d.length(), 0.3)
		var big: bool = e.type == EnemyManager.BOSS or e.type == EnemyManager.SERPENT or e.type == EnemyManager.SEG or e.type == EnemyManager.BOYNUZ
		if e.type == EnemyManager.CRYSTAL:
			continue
		var w: float = (3.0 if big else 1.0) / (l * l)
		if e.type == EnemyManager.KESE and e.mode == 1:
			w *= 4.0
		steer += d / l * w * 6.0
		danger += w
	# Step sideways out of a charger's lane.
	for e in g.em.query(pp, 20.0):
		if e.type == EnemyManager.BOYNUZ and e.mode > 0:
			var rel: Vector3 = pp - e.pos
			rel.y = 0
			var along: float = rel.dot(e.dir)
			var side: Vector3 = rel - e.dir * along
			if along > 0.0 and side.length() < 2.5:
				var away: Vector3 = side.normalized() if side.length() > 0.1 else Vector3(-e.dir.z, 0, e.dir.x)
				steer += away * 6.0
				danger += 2.0
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
	# Crystals only win over a far objective when they are close.
	var far_goal: bool = goal != null and pp.distance_to(goal) > 25.0
	if g.pickups.g_count > 0 and (goal == null or far_goal):
		var best := 1e9
		for i in mini(g.pickups.g_count, 200):
			var d2: float = pp.distance_squared_to(g.pickups.g_pos[i])
			if d2 < best and d2 < 100.0:
				best = d2
				goal = g.pickups.g_pos[i]
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
	# Fight the boss at mid range instead of running from it forever.
	var bs = g.em.boss
	if bs != null and bs.alive:
		var to_b: Vector3 = bs.pos - pp
		to_b.y = 0
		var db := to_b.length()
		if db > 14.0:
			steer += to_b.normalized() * 2.5
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
	if g.em.boss != null and g.em.boss.alive and Engine.get_physics_frames() % 300 == 0:
		print("BOSS t=%.1f hp=%d/%d dist=%.1f" % [g.t, g.em.boss.hp, g.em.boss.max_hp, pp.distance_to(g.em.boss.pos)])
	if log_t > 10.0:
		log_t = 0.0
		print("BOT t=%d hp=%d lv=%d kills=%d alive=%d fps=%d" % [g.t, p.hp, g.level, g.kills, g.em.alive_count(), Engine.get_frames_per_second()])
