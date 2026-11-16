class_name EnemyManager
extends Node3D
## Data-driven horde. Enemies are plain objects updated in one loop and drawn with
## one MultiMesh per type, so hundreds stay cheap. A uniform grid serves
## separation and weapon hit queries.

const CELL := 2.5
const MAX_ALIVE := 460

enum { CRAWLER, MOTH, BRUTE, SPITTER, BOSS, KESE, BOYNUZ, CRYSTAL, SERPENT, SEG }
## Types drawn with a MultiMesh; the boss and the serpent use their own nodes.
const DRAWN := [CRAWLER, MOTH, BRUTE, SPITTER, KESE, BOYNUZ, CRYSTAL]
## Types the director does not count toward the crowd size.
const NOT_HORDE := [BOSS, CRYSTAL, SERPENT, SEG]

var TYPES := [
	{"name": "Kül Böceği", "hp": 9.0, "speed": 3.9, "dmg": 7.0, "xp": 1, "r": 0.55, "scale": 1.0, "fly": 0.0, "jump_safe": 0.9},
	{"name": "Kül Güvesi", "hp": 6.0, "speed": 6.4, "dmg": 5.0, "xp": 1, "r": 0.5, "scale": 1.0, "fly": 1.1, "jump_safe": 2.6},
	{"name": "Taş Hantal", "hp": 60.0, "speed": 2.5, "dmg": 14.0, "xp": 6, "r": 1.1, "scale": 1.0, "fly": 0.0, "jump_safe": 2.0},
	{"name": "Kor Tükürgeci", "hp": 26.0, "speed": 3.2, "dmg": 8.0, "xp": 3, "r": 0.7, "scale": 1.0, "fly": 0.0, "jump_safe": 1.2},
	{"name": "Kül Devi", "hp": 26000.0, "speed": 3.0, "dmg": 22.0, "xp": 0, "r": 2.6, "scale": 1.0, "fly": 0.0, "jump_safe": 99.0},
	{"name": "Kor Kesesi", "hp": 18.0, "speed": 5.4, "dmg": 6.0, "xp": 3, "r": 0.7, "scale": 1.0, "fly": 0.0, "jump_safe": 1.1},
	{"name": "Kül Boynuzu", "hp": 110.0, "speed": 3.0, "dmg": 24.0, "xp": 8, "r": 1.0, "scale": 1.0, "fly": 0.0, "jump_safe": 1.7},
	{"name": "Kehribar", "hp": 70.0, "speed": 0.0, "dmg": 0.0, "xp": 0, "r": 1.0, "scale": 1.0, "fly": 0.0, "jump_safe": 0.0},
	{"name": "Kor Yılanı", "hp": 8000.0, "speed": 0.0, "dmg": 14.0, "xp": 0, "r": 1.5, "scale": 1.0, "fly": 0.0, "jump_safe": 2.2},
	{"name": "Yılan gövdesi", "hp": 1.0, "speed": 0.0, "dmg": 9.0, "xp": 0, "r": 1.2, "scale": 1.0, "fly": 0.0, "jump_safe": 1.9},
]
const KESE_R := 3.2

class Enemy:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var hp := 1.0
	var max_hp := 1.0
	var type := 0
	var flash := 0.0
	var elite := false
	var phase := 0.0
	var alive := true
	var shoot_t := 0.0
	var yaw := 0.0
	var orbit_cd := 0.0
	var trail_cd := 0.0
	var slow_t := 0.0
	var dmg_mult := 1.0
	var spd_mult := 1.0
	var r := 0.5          # cached body radius
	var speed := 1.0      # cached base speed
	var fly := 0.0
	var jump_safe := 1.0
	var dmg := 1.0
	var mode := 0         # per-type state machine (kese fuse, boynuz charge)
	var timer := 0.0
	var dir := Vector3.ZERO
	var link = null       # serpent segment -> head
	var swell := 0.0

var enemies: Array = []
var grid := {}
var mm := {}                 # type -> MultiMeshInstance3D (DRAWN types only)
var bufs := {}
var horde := 0               # alive crowd, excluding crystals, boss and serpent
var boss = null
var boss_node: Node3D = null
var hp_mult := 1.0           # rises with time
var bullets: Array = []      # enemy projectiles: [pos, vel, life]
var bullet_mm: MultiMeshInstance3D

var obstacles: Array = []    # [Vector2 center, radius]
var obs_grid := {}
const OBS_CELL := 8.0

func setup(meshes: Dictionary, mats: Dictionary) -> void:
	for t in DRAWN:
		if not meshes.has(t):
			continue
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = false
		m.use_custom_data = true
		m.mesh = meshes[t]
		m.instance_count = MAX_ALIVE
		m.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = m
		mi.material_override = mats[t]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 40, 400))
		add_child(mi)
		mm[t] = mi
		var b := PackedFloat32Array()
		b.resize(MAX_ALIVE * 16)
		bufs[t] = b
	# Enemy bullets
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	var sph := SphereMesh.new()
	sph.radius = 0.32
	sph.height = 0.64
	sph.radial_segments = 8
	sph.rings = 4
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.3, 0.9)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.2, 0.8)
	smat.emission_energy_multiplier = 3.0
	sph.material = smat
	bm.mesh = sph
	bm.instance_count = 300
	bm.visible_instance_count = 0
	bullet_mm = MultiMeshInstance3D.new()
	bullet_mm.multimesh = bm
	bullet_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bullet_mm.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 40, 400))
	add_child(bullet_mm)

func set_obstacles(list: Array) -> void:
	obstacles = list
	obs_grid.clear()
	for o in list:
		var c: Vector2 = o[0]
		var r: float = o[1]
		for x in range(floori((c.x - r) / OBS_CELL), floori((c.x + r) / OBS_CELL) + 1):
			for z in range(floori((c.y - r) / OBS_CELL), floori((c.y + r) / OBS_CELL) + 1):
				var k := Vector2i(x, z)
				if not obs_grid.has(k):
					obs_grid[k] = []
				obs_grid[k].append(o)

func alive_count() -> int:
	return horde

func count_type(type: int) -> int:
	var n := 0
	for e in enemies:
		if e.alive and e.type == type:
			n += 1
	return n

func spawn(type: int, pos: Vector3, elite := false):
	if not NOT_HORDE.has(type) and enemies.size() >= MAX_ALIVE:
		return null
	var d: Dictionary = TYPES[type]
	var e := Enemy.new()
	e.type = type
	e.pos = Vector3(pos.x, 0.0, pos.z)
	e.max_hp = d["hp"] * (hp_mult if not NOT_HORDE.has(type) else 1.0)
	if elite:
		e.max_hp *= 14.0
		e.dmg_mult = 1.6
		e.spd_mult = 1.1
	e.hp = e.max_hp
	e.elite = elite
	e.phase = randf() * TAU
	e.shoot_t = randf_range(1.0, 3.0)
	e.r = float(d["r"]) * (1.6 if elite else 1.0)
	e.speed = d["speed"]
	e.fly = d["fly"]
	e.jump_safe = d["jump_safe"]
	e.dmg = d["dmg"]
	if type == BOYNUZ:
		e.timer = randf_range(1.0, 3.0)
	enemies.append(e)
	if type == BOSS:
		boss = e
	if not NOT_HORDE.has(type):
		horde += 1
	return e

func radius_of(e) -> float:
	return e.r

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

func _rebuild_grid() -> void:
	grid.clear()
	for e in enemies:
		var k := _cell(e.pos)
		var a = grid.get(k)
		if a == null:
			grid[k] = [e]
		else:
			a.append(e)

## Enemies whose body overlaps a circle (xz plane).
func query(p: Vector3, radius: float) -> Array:
	var out: Array = []
	# Pad by the largest horde radius (elite brute); the boss is checked apart.
	var cr := ceili((radius + 1.8) / CELL)
	var c := _cell(p)
	if boss != null and boss.alive:
		var bx: float = boss.pos.x - p.x
		var bz: float = boss.pos.z - p.z
		var br: float = radius + boss.r
		if bx * bx + bz * bz <= br * br:
			out.append(boss)
	for x in range(c.x - cr, c.x + cr + 1):
		for z in range(c.y - cr, c.y + cr + 1):
			var a = grid.get(Vector2i(x, z))
			if a == null:
				continue
			for e in a:
				if not e.alive or e.type == BOSS:
					continue
				var dx: float = e.pos.x - p.x
				var dz: float = e.pos.z - p.z
				var rr: float = radius + e.r
				if dx * dx + dz * dz <= rr * rr:
					out.append(e)
	return out

func nearest(p: Vector3, max_r: float, exclude: Array = []):
	var best = null
	var bd := max_r * max_r
	for e in enemies:
		if not e.alive or e.type == CRYSTAL or (not exclude.is_empty() and exclude.has(e)):
			continue
		var d2: float = (e.pos.x - p.x) * (e.pos.x - p.x) + (e.pos.z - p.z) * (e.pos.z - p.z)
		if d2 < bd:
			bd = d2
			best = e
	return best

## Returns true if the hit killed the enemy.
## flash < 1 for damage-over-time sources so crowds in fire do not glow white.
func damage(e, amount: float, knock: Vector3 = Vector3.ZERO, crit := false, flash := 1.0) -> bool:
	if not e.alive:
		return false
	var shown_at: Vector3 = e.pos
	if e.type == SEG:
		e.flash = maxf(e.flash, flash)
		e = e.link
		if e == null or not e.alive:
			return false
	# Count effective damage only, so overkill does not inflate stats.
	var dealt := minf(amount, e.hp)
	e.hp -= amount
	e.flash = maxf(e.flash, flash)
	var weight := 1.0
	if e.type == BRUTE or e.type == BOYNUZ: weight = 3.5
	if e.elite: weight *= 3.0
	if e.type == BOSS: weight = 60.0
	if e.type != CRYSTAL and e.type != SERPENT:
		e.vel += knock / weight
	var g = Game.inst
	# Damage-over-time ticks skip the floating number to keep the screen readable.
	if flash >= 1.0 or crit:
		g.fx.damage_number(shown_at + Vector3(0, 1.5 + e.fly + (3.0 if e.type == BOSS else 0.0), 0), amount, crit, e.get_instance_id())
	g.stats_total_damage += dealt
	if g.dmg_src != "":
		g.weapon_damage[g.dmg_src] = g.weapon_damage.get(g.dmg_src, 0.0) + dealt
	if e.type == BOSS:
		g.on_boss_hit(dealt)
	elif e.type == SERPENT:
		g.serpent.on_hit(dealt)
	if e.hp <= 0.0:
		_kill(e)
		return true
	Sfx.play("hit", e.pos, 0.55 if not crit else 0.85)
	return false

func _kill(e) -> void:
	e.alive = false
	if not NOT_HORDE.has(e.type):
		horde -= 1
	var g = Game.inst
	if e.type == KESE:
		_explode(e, e.mode == 2)
	elif e.type == CRYSTAL:
		g.on_crystal_broken(e)
		return
	elif e.type == SERPENT:
		g.serpent.on_killed()
		return
	var col := Color(0.55, 0.35, 0.8)
	if e.type == SPITTER: col = Color(0.95, 0.3, 0.65)
	if e.type == BRUTE: col = Color(0.6, 0.55, 0.7)
	var y: float = 0.6 + TYPES[e.type]["fly"]
	g.fx.burst(e.pos + Vector3(0, y, 0), col, 8 if not e.elite else 30, 1.0 if not e.elite else 2.2)
	g.fx.burst(e.pos + Vector3(0, y, 0), Color(1.0, 0.75, 0.3), 3 if not e.elite else 12, 0.8)
	Sfx.play("kill", e.pos, 0.7)
	g.on_enemy_killed(e)

func update(dt: float, player_pos: Vector3, player: Node) -> void:
	var i := 0
	while i < enemies.size():
		if not enemies[i].alive:
			enemies[i] = enemies[enemies.size() - 1]
			enemies.pop_back()
		else:
			i += 1
	var g = Game.inst
	var t := Time.get_ticks_msec() * 0.001
	var counts := {}
	for ti in DRAWN:
		counts[ti] = 0
	var island_r: float = g.world.island_radius - 1.0
	var py: float = player.position.y
	for e in enemies:
		var d: Dictionary = TYPES[e.type]
		var tx: float = player_pos.x - e.pos.x
		var tz: float = player_pos.z - e.pos.z
		var dist := sqrt(tx * tx + tz * tz) + 0.0001
		var dx := tx / dist
		var dz := tz / dist
		var spd: float = e.speed * e.spd_mult * (0.45 if e.slow_t > 0.0 else 1.0)
		var mx := dx * spd
		var mz := dz * spd
		match e.type:
			MOTH:
				var w := sin(t * 2.6 + e.phase) * 0.9
				mx += -dz * w * spd
				mz += dx * w * spd
			SPITTER:
				if dist < 8.5:
					mx = -dx * spd * 0.6
					mz = -dz * spd * 0.6
				elif dist < 12.0:
					mx = -dz * spd * 0.5
					mz = dx * spd * 0.5
				e.shoot_t -= dt
				if e.shoot_t <= 0.0 and dist < 16.0:
					e.shoot_t = randf_range(2.6, 3.6)
					var bv := Vector3(dx, 0, dz) * 7.0
					add_bullet(e.pos + Vector3(0, 1.0, 0), bv, 4.0)
					if e.elite:
						add_bullet(e.pos + Vector3(0, 1.0, 0), bv.rotated(Vector3.UP, 0.3), 4.0)
						add_bullet(e.pos + Vector3(0, 1.0, 0), bv.rotated(Vector3.UP, -0.3), 4.0)
			BOSS:
				var f: float = g.boss_ai(e, dt, dist, dx, dz)
				mx *= f
				mz *= f
			KESE:
				if e.mode == 0 and dist < 2.6:
					# Fuse: stop, swell and flash, then burst.
					e.mode = 1
					e.timer = 0.85
					g.fx.telegraph(e.pos, KESE_R, 0.85)
				if e.mode == 1:
					mx = 0.0
					mz = 0.0
					e.timer -= dt
					e.swell = 1.0 - e.timer / 0.85
					e.flash = 0.5 + 0.5 * sin(t * 40.0)
					if e.timer <= 0.0:
						e.mode = 2
						_kill(e)
						continue
			BOYNUZ:
				e.timer -= dt
				if e.mode == 0:
					if dist < 15.0 and dist > 4.0 and e.timer <= 0.0:
						e.mode = 1
						e.timer = 0.95
						e.dir = Vector3(dx, 0, dz)
						g.fx.lane(e.pos, e.dir, 19.0, 1.8 * (1.6 if e.elite else 1.0), 0.95)
						Sfx.play("charge", e.pos, 0.9)
				elif e.mode == 1:
					mx = 0.0
					mz = 0.0
					e.flash = 0.35 + 0.35 * sin(t * 30.0)
					e.yaw = atan2(e.dir.x, e.dir.z)
					if e.timer <= 0.0:
						e.mode = 2
						e.timer = 0.75
				elif e.mode == 2:
					mx = e.dir.x * 24.0
					mz = e.dir.z * 24.0
					if Engine.get_process_frames() % 3 == 0:
						g.fx.dust(e.pos, 2)
					if e.timer <= 0.0:
						e.mode = 0
						e.timer = randf_range(3.0, 4.5)
			CRYSTAL, SERPENT, SEG:
				# Static, or moved by the serpent controller.
				mx = 0.0
				mz = 0.0
		var r: float = e.r
		if e.type == CRYSTAL or e.type == SERPENT or e.type == SEG:
			e.flash = maxf(0.0, e.flash - dt * 10.0)
			var live_body: bool = e.type == SERPENT or (e.type == SEG and e.link != null and e.link.alive)
			if live_body and dist < r + 0.45 and py < e.jump_safe:
				player.hurt(e.dmg * g.enemy_dmg_mult, e.pos)
			if e.type == CRYSTAL:
				var ci: int = counts[CRYSTAL]
				counts[CRYSTAL] = ci + 1
				_write(bufs[CRYSTAL], ci, e, d, t)
			continue
		if e.type != BOSS and not (e.type == BOYNUZ and e.mode == 2):
			# Separation from neighbours
			var sx := 0.0
			var sz := 0.0
			var c := Vector2i(floori(e.pos.x / CELL), floori(e.pos.z / CELL))
			var checked := 0
			for ox in range(-1, 2):
				for oz in range(-1, 2):
					var a = grid.get(Vector2i(c.x + ox, c.y + oz))
					if a == null:
						continue
					for o in a:
						if o == e or not o.alive:
							continue
						var ex: float = e.pos.x - o.pos.x
						var ez: float = e.pos.z - o.pos.z
						var rr: float = r + o.r
						var l2 := ex * ex + ez * ez
						if l2 < rr * rr and l2 > 0.00001:
							var l := sqrt(l2)
							var push := (rr - l) / rr
							sx += ex / l * push
							sz += ez / l * push
						checked += 1
						if checked > 12:
							break
			mx += sx * 9.0
			mz += sz * 9.0
		e.pos.x += (mx + e.vel.x) * dt
		e.pos.z += (mz + e.vel.z) * dt
		e.vel *= exp(-7.0 * dt)
		# Obstacles: push out and slide around the edge
		var ol = obs_grid.get(Vector2i(floori(e.pos.x / OBS_CELL), floori(e.pos.z / OBS_CELL)))
		if ol != null:
			for o in ol:
				var oc2: Vector2 = o[0]
				var orr: float = o[1] + r * 0.7
				var ex2 = e.pos.x - oc2.x
				var ez2 = e.pos.z - oc2.y
				var l2b = ex2 * ex2 + ez2 * ez2
				if l2b < orr * orr and l2b > 0.0001:
					var lb := sqrt(l2b)
					e.pos.x = oc2.x + ex2 / lb * orr
					e.pos.z = oc2.y + ez2 / lb * orr
					var side := 1.0 if (dx * ez2 - dz * ex2) >= 0.0 else -1.0
					e.pos.x += -ez2 / lb * side * spd * dt
					e.pos.z += ex2 / lb * side * spd * dt
		var pl := sqrt(e.pos.x * e.pos.x + e.pos.z * e.pos.z)
		if pl > island_r:
			e.pos.x *= island_r / pl
			e.pos.z *= island_r / pl
		e.flash = maxf(0.0, e.flash - dt * 10.0)
		e.slow_t -= dt
		e.orbit_cd -= dt
		e.trail_cd -= dt
		if not (e.type == BOYNUZ and e.mode > 0):
			e.yaw = lerp_angle(e.yaw, atan2(dx, dz), minf(1.0, dt * 8.0))
		# Contact damage; jumping clears low enemies.
		if dist < r + 0.45 and py < e.jump_safe:
			player.hurt(e.dmg * e.dmg_mult * g.enemy_dmg_mult, e.pos)
		# Recycle stragglers far behind so pressure stays on the player.
		if dist > 46.0 and e.type != BOSS:
			var ang := randf() * TAU
			var np: Vector3 = player_pos + Vector3(cos(ang), 0, sin(ang)) * 28.0
			var nl := Vector2(np.x, np.z).length()
			if nl > island_r:
				np = np * (island_r / nl) * 0.95
			e.pos = Vector3(np.x, 0, np.z)
		if e.type != BOSS:
			var ti: int = e.type
			var idx: int = counts[ti]
			if idx < MAX_ALIVE:
				counts[ti] = idx + 1
				_write(bufs[ti], idx, e, d, t)
		elif boss_node:
			boss_node.position = Vector3(e.pos.x, boss_node.position.y, e.pos.z)
			boss_node.rotation.y = e.yaw
			var ov = boss_node.get_meta("overlay", null)
			if ov:
				ov.set_shader_parameter("flash", e.flash)
				ov.set_shader_parameter("warn", g.boss_warn)
	# Rebuilt after movement so weapon queries this frame see current positions.
	_rebuild_grid()
	for ti in mm.keys():
		var m: MultiMesh = mm[ti].multimesh
		m.visible_instance_count = counts[ti]
		if counts[ti] > 0:
			m.buffer = bufs[ti]
	_update_bullets(dt, player_pos, player)

func _write(b: PackedFloat32Array, idx: int, e, d: Dictionary, t: float) -> void:
	var s: float = d["scale"] * (1.6 if e.elite else 1.0)
	var hop := 0.0
	var y: float = d["fly"]
	if e.type == CRAWLER:
		hop = absf(sin(t * 9.0 + e.phase)) * 0.12
	elif e.type == MOTH:
		y += sin(t * 5.0 + e.phase) * 0.35
	elif e.type == BRUTE:
		hop = absf(sin(t * 4.0 + e.phase)) * 0.08
	if e.type == KESE:
		s *= 1.0 + e.swell * 0.45
		hop = absf(sin(t * 11.0 + e.phase)) * 0.15
	elif e.type == CRYSTAL:
		hop = 0.0
	var squash = 1.0 + e.flash * 0.25
	var cy := cos(e.yaw)
	var sy := sin(e.yaw)
	var o := idx * 16
	b[o + 0] = cy * s * squash
	b[o + 1] = 0.0
	b[o + 2] = sy * s * squash
	b[o + 3] = e.pos.x
	b[o + 4] = 0.0
	b[o + 5] = s / squash
	b[o + 6] = 0.0
	b[o + 7] = y + hop
	b[o + 8] = -sy * s * squash
	b[o + 9] = 0.0
	b[o + 10] = cy * s * squash
	b[o + 11] = e.pos.z
	# Custom: flash, elite, slowed, phase
	b[o + 12] = e.flash
	b[o + 13] = 1.0 if e.elite else 0.0
	b[o + 14] = 1.0 if e.slow_t > 0.0 else 0.0
	b[o + 15] = e.phase

const MAX_BULLETS := 300

## Every live bullet is drawn: the pool cap and the draw cap are the same, so
## nothing can hit the player unseen.
func add_bullet(p: Vector3, v: Vector3, life: float) -> void:
	if bullets.size() < MAX_BULLETS:
		bullets.append([p, v, life])

func _update_bullets(dt: float, player_pos: Vector3, player: Node) -> void:
	var m := bullet_mm.multimesh
	var n := 0
	var i := 0
	while i < bullets.size():
		var bl: Array = bullets[i]
		bl[0] += bl[1] * dt
		bl[2] -= dt
		var p: Vector3 = bl[0]
		var hit := Vector2(p.x - player_pos.x, p.z - player_pos.z).length() < 0.75 and absf(p.y - (player.position.y + 1.0)) < 1.0
		if hit:
			player.hurt(9.0 * Game.inst.enemy_dmg_mult, p)
		if bl[2] <= 0.0 or hit:
			bullets[i] = bullets[bullets.size() - 1]
			bullets.pop_back()
			continue
		if n < 300:
			m.set_instance_transform(n, Transform3D(Basis(), p))
			n += 1
		i += 1
	m.visible_instance_count = n

func clear_all() -> void:
	for e in enemies:
		if e.type != BOSS and e.alive:
			e.alive = false
			if not NOT_HORDE.has(e.type):
				horde -= 1
	bullets.clear()

## Kese burst. Detonated ones hurt the hero; killed ones only hurt the crowd,
## which turns a pack of them into a chain reaction.
func _explode(e, harm_player: bool) -> void:
	var g = Game.inst
	var p: Vector3 = e.pos
	g.fx.ring(p, KESE_R, Color(1.0, 0.45, 0.2), 0.3, 0.45, 0.2)
	g.fx.burst(p + Vector3(0, 0.6, 0), Color(1.0, 0.5, 0.15), 14, 1.6)
	g.fx.burst(p + Vector3(0, 0.6, 0), Color(1.0, 0.25, 0.6), 8, 1.2)
	Sfx.play("explode", p, 0.8)
	g.shake(0.08)
	if harm_player:
		var pp: Vector3 = g.player.global_position
		if Vector2(pp.x - p.x, pp.z - p.z).length() < KESE_R and g.player.position.y < 2.0:
			g.player.hurt(22.0 * g.enemy_dmg_mult, p)
	var prev: String = g.dmg_src
	g.dmg_src = "kese"
	for o in query(p, KESE_R):
		if o == e or o.type == BOSS or o.type == CRYSTAL:
			continue
		damage(o, 45.0 * hp_mult, (o.pos - p).normalized() * 8.0)
	g.dmg_src = prev
