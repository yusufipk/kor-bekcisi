class_name Weapons
extends Node3D
## Auto-firing weapons. Levels live in `lv`; global multipliers come from Game.st.

var lv := {}            # id -> level
var cd := {}            # id -> seconds until next fire
var em: EnemyManager
var fx: Fx

# Bolts
var bolts: Array = []   # {p, v, life, dmg, pierce, hit}
var bolt_mm: MultiMeshInstance3D
# Blades
var blades: Array = []  # {p, dir, t, range, dmg, hit:{}}
var blade_nodes: Array = []
# Orbit
var orbit_nodes: Array = []
var orbit_angle := 0.0
# Trail
var patches: Array = [] # {p, life, r}
var patch_mm: MultiMeshInstance3D
var trail_drop := 0.0
var last_trail_pos := Vector3.ZERO
var patch_tick := 0.0
# Meteors
var meteors: Array = [] # {target, t, dmg, r, node}
var meteor_nodes: Array = []

func setup(enemy_mgr: EnemyManager, effects: Fx) -> void:
	em = enemy_mgr
	fx = effects
	# Bolt visuals
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	var cap := CapsuleMesh.new()
	cap.radius = 0.16
	cap.height = 0.9
	cap.radial_segments = 6
	cap.rings = 2
	cap.material = _glow(Color(1.0, 0.6, 0.2), 4.0)
	m.mesh = cap
	m.instance_count = 400
	m.visible_instance_count = 0
	bolt_mm = MultiMeshInstance3D.new()
	bolt_mm.multimesh = m
	bolt_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt_mm.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 40, 400))
	add_child(bolt_mm)
	# Fire patches
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.orientation = PlaneMesh.FACE_Y
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
varying float life;
void vertex() { life = COLOR.a; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float flick = 0.75 + 0.25 * sin(TIME * 13.0 + p.x * 7.0 + p.y * 5.0);
	float a = (1.0 - smoothstep(0.3, 1.0, r)) * flick * life * 0.75;
	ALBEDO = mix(vec3(0.75, 0.10, 0.01), vec3(1.0, 0.42, 0.06), 1.0 - r);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	q.material = smat
	pm.mesh = q
	pm.instance_count = 260
	pm.visible_instance_count = 0
	patch_mm = MultiMeshInstance3D.new()
	patch_mm.multimesh = pm
	patch_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch_mm.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 40, 400))
	add_child(patch_mm)

func _glow(c: Color, e: float) -> StandardMaterial3D:
	# Shaded + strong emission so the glow pass blooms it (unshaded caps at 1.0).
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = e
	return mat

func add_weapon(id: String) -> void:
	lv[id] = lv.get(id, 0) + 1
	if not cd.has(id):
		cd[id] = 0.3

## Awakening: a weapon at max level hits 40 % harder.
func _aw(l: int) -> float:
	return 1.4 if l >= Upgrades.WEAPON_MAX else 1.0

func _boss_in_range(pp: Vector3, r: float) -> bool:
	var b = em.boss
	return b != null and b.alive and Vector2(b.pos.x - pp.x, b.pos.z - pp.z).length() < r

func level(id: String) -> int:
	return lv.get(id, 0)

func _dmg(base: float) -> Array:
	var st = Game.inst.st
	var crit: bool = randf() < st.crit
	return [base * st.dmg * (2.2 if crit else 1.0), crit]

func _hit(e, base: float, knock: Vector3) -> bool:
	var r := _dmg(base)
	if r[1]:
		Game.inst.hitstop(0.025)
	return em.damage(e, r[0], knock, r[1])

func update(dt: float, player) -> void:
	var st = Game.inst.st
	var pp: Vector3 = player.global_position
	for id in lv.keys():
		cd[id] -= dt
		if cd[id] <= 0.0:
			cd[id] = _fire(id, lv[id], player, st)
	_update_bolts(dt)
	_update_blades(dt, pp)
	_update_orbit(dt, pp, st)
	_update_trail(dt, player, st)
	_update_meteors(dt)

func _fire(id: String, l: int, player, st) -> float:
	var pp: Vector3 = player.global_position
	match id:
		"bolt":
			var n = 1 + int(l >= 2) + int(l >= 5) + 2 * int(l >= 7) + st.amount
			var dmg := 11.0 * (1.3 if l >= 3 else 1.0) * _aw(l)
			var pierce := int(l >= 4) + int(l >= 7)
			var used: Array = []
			var boss_live: bool = _boss_in_range(pp, 26.0)
			for i in n:
				var tgt = em.nearest(pp, 22.0 * st.area_range, used)
				# During the boss fight every other bolt goes for the boss.
				if boss_live and i % 2 == 0:
					tgt = em.boss
				var dir: Vector3
				if tgt != null:
					used.append(tgt)
					dir = (tgt.pos + Vector3(0, 0.6 + tgt.fly * 0.8, 0)) - (pp + Vector3(0, 1.1, 0))
				elif used.size() > 0:
					var u = used[i % used.size()]
					dir = (u.pos - pp).rotated(Vector3.UP, randf_range(-0.25, 0.25))
				else:
					dir = Vector3(sin(player.facing), 0, cos(player.facing)).rotated(Vector3.UP, (i - (n - 1) * 0.5) * 0.18)
				dir = dir.normalized()
				bolts.append({"p": pp + Vector3(0, 1.1, 0), "v": dir * 26.0, "life": 1.1, "dmg": dmg, "pierce": pierce, "hit": []})
			Sfx.play("shoot", pp, 0.35)
			return 0.78 * (0.8 if l >= 6 else 1.0) * st.cd
		"chain":
			var strikes := 1 + int(l >= 5) + int(st.amount > 0)
			var hops := 3 + 2 * int(l >= 2) + 3 * int(l >= 6)
			var dmg := 16.0 * (1.35 if l >= 3 else 1.0) * (1.5 if l >= 7 else 1.0) * _aw(l)
			var fired := false
			for s in strikes:
				var first = em.nearest(pp, 16.0 * st.area_range, [])
				if s == 0 and _boss_in_range(pp, 20.0):
					first = em.boss
				elif s > 0:
					var near := em.query(pp, 16.0 * st.area_range)
					if near.is_empty():
						break
					first = near[randi() % near.size()]
				if first == null:
					break
				fired = true
				var hit: Array = []
				var cur = first
				var from := pp + Vector3(0, 1.4, 0)
				for h in hops:
					if cur == null:
						break
					hit.append(cur)
					var to: Vector3 = cur.pos + Vector3(0, 0.7 + cur.fly, 0)
					fx.bolt(from, to)
					fx.burst(to, Color(0.6, 0.9, 1.0), 2, 0.6)
					cur.slow_t = 0.8
					_hit(cur, dmg, Vector3.ZERO)
					from = to
					cur = em.nearest(cur.pos, 7.0 * st.area, hit)
			if fired:
				Sfx.play("zap", pp, 0.5)
			return 1.5 * (0.75 if l >= 4 else 1.0) * st.cd
		"nova":
			var waves := 2 if l >= 6 else 1
			for w in waves:
				_nova(pp, l, st, w * 0.25)
			return 3.2 * (0.75 if l >= 4 else 1.0) * st.cd
		"blade":
			var n = 1 + int(l >= 2) + int(l >= 5) + 2 * int(l >= 7) + st.amount
			var base_dir := Vector3(sin(player.facing), 0, cos(player.facing))
			if player.velocity.length() < 1.0:
				var tgt = em.nearest(pp, 20.0, [])
				if tgt != null:
					base_dir = (tgt.pos - pp).normalized()
			for i in n:
				var dir := base_dir.rotated(Vector3.UP, (i - (n - 1) * 0.5) * (TAU / maxf(n, 3.0)))
				var rng = 9.0 * (1.35 if l >= 4 else 1.0) * st.area_range
				var dmg := 20.0 * (1.3 if l >= 3 else 1.0) * (1.4 if l >= 6 else 1.0) * _aw(l)
				blades.append({"p": pp + Vector3(0, 1.0, 0), "dir": dir, "t": 0.0, "range": rng, "dmg": dmg, "hit": {}})
			Sfx.play("whoosh", pp, 0.45)
			return 1.9 * st.cd
		"meteor":
			var n = 1 + int(l >= 2) + int(l >= 5) + 2 * int(l >= 7) + st.amount
			for i in n:
				var near := em.query(pp, 18.0)
				var target: Vector3
				if i == 0 and _boss_in_range(pp, 24.0):
					target = em.boss.pos
				elif near.size() > 0:
					target = near[randi() % near.size()].pos
				else:
					target = pp + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
				var r = 3.2 * (1.35 if l >= 3 else 1.0) * st.area
				var dmg := 42.0 * (1.5 if l >= 6 else 1.0) * _aw(l)
				fx.telegraph(target, r, 0.55 + i * 0.12)
				meteors.append({"target": target, "t": 0.55 + i * 0.12, "dmg": dmg, "r": r, "node": _meteor_node()})
			return 2.6 * (0.75 if l >= 4 else 1.0) * st.cd
		"orbit", "trail":
			return 999.0
	return 1.0

func _nova(pp: Vector3, l: int, st, delay: float) -> void:
	if delay > 0.0:
		get_tree().create_timer(delay, false).timeout.connect(func(): _nova(Game.inst.player.global_position, l, st, 0.0))
		return
	var r = 5.5 * (1.25 if l >= 2 else 1.0) * (1.25 if l >= 5 else 1.0) * st.area
	var dmg := 22.0 * (1.4 if l >= 3 else 1.0) * (1.6 if l >= 7 else 1.0) * _aw(l)
	fx.ring(pp, r, Color(1.0, 0.45, 0.25), 0.35, 0.15, 0.18)
	Sfx.play("nova", pp, 0.6)
	for e in em.query(pp, r):
		var away: Vector3 = e.pos - pp
		away.y = 0
		_hit(e, dmg, away.normalized() * 16.0)

func _update_bolts(dt: float) -> void:
	var m := bolt_mm.multimesh
	var n := 0
	var i := 0
	while i < bolts.size():
		var b: Dictionary = bolts[i]
		b["p"] += b["v"] * dt
		b["life"] -= dt
		var p: Vector3 = b["p"]
		var dead: bool = b["life"] <= 0.0
		if not dead:
			for e in em.query(Vector3(p.x, 0, p.z), 0.35):
				var top: float = e.fly + 1.6 * (3.0 if e.type == EnemyManager.BOSS else 1.0)
				if p.y > top + 0.4:
					continue
				if b["hit"].has(e):
					continue
				b["hit"].append(e)
				fx.burst(p, Color(1.0, 0.65, 0.25), 3, 0.6)
				_hit(e, b["dmg"], b["v"].normalized() * 5.0)
				b["pierce"] -= 1
				if b["pierce"] < 0:
					dead = true
					break
		if p.y < 0.0:
			dead = true
		if dead:
			bolts[i] = bolts[bolts.size() - 1]
			bolts.pop_back()
			continue
		if n < 400:
			var t := Transform3D(Basis(), p).looking_at(p + b["v"], Vector3.UP)
			t.basis = t.basis * Basis(Vector3.RIGHT, PI * 0.5)
			m.set_instance_transform(n, t)
			n += 1
		i += 1
	m.visible_instance_count = n

func _blade_node(i: int) -> Node3D:
	while blade_nodes.size() <= i:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.45
		tm.outer_radius = 0.8
		tm.rings = 10
		tm.ring_segments = 4
		tm.material = _glow(Color(0.8, 0.95, 1.0), 2.5)
		mi.mesh = tm
		mi.scale = Vector3(1, 0.25, 1)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		blade_nodes.append(mi)
	return blade_nodes[i]

func _update_blades(dt: float, pp: Vector3) -> void:
	var i := 0
	while i < blades.size():
		var b: Dictionary = blades[i]
		b["t"] += dt
		var T := 1.3
		var k: float = b["t"] / T
		if k >= 1.0:
			blades.remove_at(i)
			continue
		# Out and back along the throw line, returning to the player's current spot.
		var out: float = sin(k * PI) * b["range"]
		var origin := pp.lerp(b["p"], 1.0 - k) if k > 0.5 else Vector3(b["p"])
		b["pos"] = Vector3(origin.x, 1.0, origin.z) + b["dir"] * out
		for key in b["hit"].keys():
			b["hit"][key] -= dt
		for e in em.query(b["pos"], 1.0 * Game.inst.st.area):
			var hid = e.get_instance_id()
			if b["hit"].get(hid, 0.0) > 0.0:
				continue
			b["hit"][hid] = 0.35
			_hit(e, b["dmg"], b["dir"] * 6.0)
		i += 1
	for j in blade_nodes.size():
		blade_nodes[j].visible = j < blades.size()
	for j in blades.size():
		var nd := _blade_node(j)
		nd.visible = true
		nd.position = blades[j]["pos"]
		nd.rotation.y += dt * 22.0
		nd.scale = Vector3(1, 0.25, 1) * Game.inst.st.area

func _update_orbit(dt: float, pp: Vector3, st) -> void:
	var l := level("orbit")
	var n := 0
	if l > 0:
		n = 2 + int(l >= 2) + int(l >= 5) + 2 * int(l >= 7) + st.amount
	while orbit_nodes.size() < n:
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.28
		sp.height = 0.56
		sp.radial_segments = 10
		sp.rings = 5
		sp.material = _glow(Color(1.0, 0.75, 0.3), 5.0)
		mi.mesh = sp
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		orbit_nodes.append(mi)
	for j in orbit_nodes.size():
		orbit_nodes[j].visible = j < n
	if n == 0:
		return
	var radius = 3.0 * (1.3 if l >= 4 else 1.0) * st.area
	var speed := 3.2 * (1.35 if l >= 4 else 1.0)
	var dmg := 9.0 * (1.3 if l >= 3 else 1.0) * (1.4 if l >= 6 else 1.0) * _aw(l)
	orbit_angle += speed * dt
	for j in n:
		var a := orbit_angle + TAU * j / n
		var p := pp + Vector3(cos(a) * radius, 1.0, sin(a) * radius)
		orbit_nodes[j].position = p
		orbit_nodes[j].scale = Vector3.ONE * (1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.02 + j)) * sqrt(st.area)
		for e in em.query(Vector3(p.x, 0, p.z), 0.6 * st.area):
			if e.orbit_cd > 0.0:
				continue
			e.orbit_cd = 0.4
			var away: Vector3 = (e.pos - pp)
			away.y = 0
			_hit(e, dmg, away.normalized() * 9.0)

func _update_trail(dt: float, player, st) -> void:
	var l := level("trail")
	if l > 0:
		var pp: Vector3 = player.global_position
		trail_drop -= dt
		if trail_drop <= 0.0 and pp.distance_to(last_trail_pos) > 1.2 and player.is_on_floor():
			trail_drop = 0.12
			last_trail_pos = pp
			var r = 1.25 * (1.25 if l >= 4 else 1.0) * st.area
			var life := 2.2 * (1.4 if l >= 3 else 1.0) * (1.4 if l >= 6 else 1.0)
			if patches.size() < 250:
				patches.append({"p": Vector3(pp.x, 0.06, pp.z), "life": life, "max": life, "r": r})
	patch_tick -= dt
	var do_tick := patch_tick <= 0.0
	if do_tick:
		patch_tick = 0.1
	var dmg := 7.0 * (1.4 if l >= 2 else 1.0) * (1.5 if l >= 5 else 1.0) * (1.6 if l >= 7 else 1.0) * _aw(l)
	var m := patch_mm.multimesh
	var i := 0
	var n := 0
	while i < patches.size():
		var pt: Dictionary = patches[i]
		pt["life"] -= dt
		if pt["life"] <= 0.0:
			patches[i] = patches[patches.size() - 1]
			patches.pop_back()
			continue
		if do_tick:
			for e in em.query(pt["p"], pt["r"]):
				if e.trail_cd > 0.0 or e.fly > 0.5:
					continue
				e.trail_cd = 0.45
				_hit(e, dmg, Vector3.ZERO)
		if n < 260:
			var r: float = pt["r"]
			m.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(r, 1, r)), pt["p"]))
			m.set_instance_color(n, Color(1, 1, 1, clampf(pt["life"] / 0.6, 0.0, 1.0)))
			n += 1
		i += 1
	m.visible_instance_count = n

## Slide with the trail weapon drops a big burst of fire.
func on_slide(p: Vector3, dir: Vector3) -> void:
	var l := level("trail")
	if l <= 0:
		return
	var st = Game.inst.st
	for k in 4:
		var q := p + dir * (k * 1.6)
		if patches.size() < 250:
			var life := 2.6 * (1.4 if l >= 3 else 1.0)
			patches.append({"p": Vector3(q.x, 0.06, q.z), "life": life, "max": life, "r": 1.7 * st.area})

func _meteor_node() -> MeshInstance3D:
	for nd in meteor_nodes:
		if not nd.visible:
			nd.visible = true
			return nd
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.7
	sp.height = 1.4
	sp.radial_segments = 8
	sp.rings = 4
	sp.material = _glow(Color(1.0, 0.55, 0.85), 5.0)
	mi.mesh = sp
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	meteor_nodes.append(mi)
	return mi

func _update_meteors(dt: float) -> void:
	var i := 0
	while i < meteors.size():
		var mt: Dictionary = meteors[i]
		mt["t"] -= dt
		var nd: MeshInstance3D = mt["node"]
		var tg: Vector3 = mt["target"]
		var h := maxf(0.0, mt["t"]) * 30.0
		nd.position = tg + Vector3(h * 0.35, h, h * 0.2)
		if mt["t"] <= 0.0:
			nd.visible = false
			fx.ring(tg, mt["r"], Color(1.0, 0.5, 0.8), 0.35, 0.3, 0.2)
			fx.burst(tg + Vector3(0, 0.4, 0), Color(1.0, 0.5, 0.85), 14, 1.6)
			fx.burst(tg + Vector3(0, 0.4, 0), Color(1.0, 0.8, 0.4), 8, 1.2)
			Sfx.play("meteor", tg, 0.55)
			Game.inst.shake(0.12)
			for e in em.query(tg, mt["r"]):
				var away: Vector3 = e.pos - tg
				away.y = 0
				_hit(e, mt["dmg"], away.normalized() * 10.0)
			meteors.remove_at(i)
			continue
		i += 1
