class_name EnemyManager
extends Node3D
## Data-driven horde. Enemies are plain objects updated in one loop and drawn with
## one MultiMesh per type, so hundreds stay cheap. A uniform grid serves
## separation and weapon hit queries.

const CELL := 2.5
const MAX_ALIVE := 460

enum { CRAWLER, MOTH, BRUTE, SPITTER, BOSS }

var TYPES := [
	{"name": "Kül Böceği", "hp": 9.0, "speed": 3.9, "dmg": 7.0, "xp": 1, "r": 0.55, "scale": 1.0, "fly": 0.0, "jump_safe": 0.9},
	{"name": "Kül Güvesi", "hp": 6.0, "speed": 6.4, "dmg": 5.0, "xp": 1, "r": 0.5, "scale": 1.0, "fly": 1.1, "jump_safe": 2.6},
	{"name": "Taş Hantal", "hp": 70.0, "speed": 2.5, "dmg": 14.0, "xp": 6, "r": 1.1, "scale": 1.0, "fly": 0.0, "jump_safe": 2.0},
	{"name": "Kor Tükürgeci", "hp": 26.0, "speed": 3.2, "dmg": 8.0, "xp": 3, "r": 0.7, "scale": 1.0, "fly": 0.0, "jump_safe": 1.2},
	{"name": "Kül Devi", "hp": 26000.0, "speed": 3.0, "dmg": 22.0, "xp": 0, "r": 2.6, "scale": 1.0, "fly": 0.0, "jump_safe": 99.0},
]

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

var enemies: Array = []
var grid := {}
var mm: Array = []           # MultiMeshInstance3D per type (boss excluded)
var bufs: Array = []
var boss = null
var boss_node: Node3D = null
var hp_mult := 1.0           # rises with time
var bullets: Array = []      # enemy projectiles: [pos, vel, life]
var bullet_mm: MultiMeshInstance3D

var obstacles: Array = []    # [Vector2 center, radius]
var obs_grid := {}
const OBS_CELL := 8.0

func setup(meshes: Array, mats: Array, scales: Array) -> void:
	for t in range(4):
		TYPES[t]["scale"] = scales[t]
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
		mm.append(mi)
		var b := PackedFloat32Array()
		b.resize(MAX_ALIVE * 16)
		bufs.append(b)
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
	return enemies.size()

func spawn(type: int, pos: Vector3, elite := false):
	if type != BOSS and enemies.size() >= MAX_ALIVE:
		return null
	var d: Dictionary = TYPES[type]
	var e := Enemy.new()
	e.type = type
	e.pos = Vector3(pos.x, 0.0, pos.z)
	e.max_hp = d["hp"] * (hp_mult if type != BOSS else 1.0)
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
	enemies.append(e)
	if type == BOSS:
		boss = e
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
	var cr := ceili((radius + 2.7) / CELL)
	var c := _cell(p)
	for x in range(c.x - cr, c.x + cr + 1):
		for z in range(c.y - cr, c.y + cr + 1):
			var a = grid.get(Vector2i(x, z))
			if a == null:
				continue
			for e in a:
				if not e.alive:
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
		if not e.alive or (not exclude.is_empty() and exclude.has(e)):
			continue
		var d2: float = (e.pos.x - p.x) * (e.pos.x - p.x) + (e.pos.z - p.z) * (e.pos.z - p.z)
		if d2 < bd:
			bd = d2
			best = e
	return best

## Returns true if the hit killed the enemy.
func damage(e, amount: float, knock: Vector3 = Vector3.ZERO, crit := false) -> bool:
	if not e.alive:
		return false
	e.hp -= amount
	e.flash = 1.0
	var weight := 1.0
	if e.type == BRUTE: weight = 3.5
	if e.elite: weight *= 3.0
	if e.type == BOSS: weight = 60.0
	e.vel += knock / weight
	var g = Game.inst
	g.fx.damage_number(e.pos + Vector3(0, 1.5 + TYPES[e.type]["fly"] + (3.0 if e.type == BOSS else 0.0), 0), amount, crit)
	g.stats_total_damage += amount
	if e.hp <= 0.0:
		_kill(e)
		return true
	Sfx.play("hit", e.pos, 0.55 if not crit else 0.85)
	return false

func _kill(e) -> void:
	e.alive = false
	var g = Game.inst
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
	_rebuild_grid()
	var g = Game.inst
	var t := Time.get_ticks_msec() * 0.001
	var counts := [0, 0, 0, 0]
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
					bullets.append([e.pos + Vector3(0, 1.0, 0), bv, 4.0])
					if e.elite:
						bullets.append([e.pos + Vector3(0, 1.0, 0), bv.rotated(Vector3.UP, 0.3), 4.0])
						bullets.append([e.pos + Vector3(0, 1.0, 0), bv.rotated(Vector3.UP, -0.3), 4.0])
			BOSS:
				var f: float = g.boss_ai(e, dt, dist, dx, dz)
				mx *= f
				mz *= f
		var r: float = e.r
		if e.type != BOSS:
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
						if o == e:
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
		e.flash = maxf(0.0, e.flash - dt * 7.0)
		e.slow_t -= dt
		e.orbit_cd -= dt
		e.trail_cd -= dt
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
			counts[ti] = idx + 1
			_write(bufs[ti], idx, e, d, t)
		elif boss_node:
			boss_node.position = Vector3(e.pos.x, boss_node.position.y, e.pos.z)
			boss_node.rotation.y = e.yaw
			var ov = boss_node.get_meta("overlay", null)
			if ov:
				ov.set_shader_parameter("flash", e.flash)
	for ti in range(4):
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
		if e.type != BOSS:
			e.alive = false
	bullets.clear()
