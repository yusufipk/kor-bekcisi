class_name Serpent
extends Node3D
## Kor Yılanı: the mid-run boss. A head and a chain of body segments that follow
## the head's trail. Segments are EnemyManager entries (type SEG) that forward
## damage to the head, so every weapon already knows how to hit it.

const SEGMENTS := 14
const SPACING := 1.55
const HEAD_H := 2.6

var head = null              # EnemyManager.Enemy (type SERPENT)
var segs: Array = []         # EnemyManager.Enemy (type SEG)
var head_node: Node3D
var seg_nodes: Array = []
var trail: Array = []        # recent head positions, newest first
var active := false
var dying := false
var die_t := 0.0
var die_i := 0
var state := "hunt"
var timer := 3.0
var dir := Vector3.FORWARD
var weave := 0.0
var fight_t := 0.0
var taken := 0.0
var calibrated := false
var overlay: ShaderMaterial

func spawn(p: Vector3) -> void:
	var g = Game.inst
	var em: EnemyManager = g.em
	active = true
	head = em.spawn(EnemyManager.SERPENT, p)
	head.max_hp = 6000.0
	head.hp = head.max_hp
	dir = (g.player.global_position - p).normalized()
	dir.y = 0
	trail.clear()
	for i in SEGMENTS * 8:
		trail.append(p - dir * (i * SPACING / 8.0 * 1.0))
	overlay = _overlay()
	head_node = _model("res://art/models/yilan_bas.glb", HEAD_H)
	add_child(head_node)
	for i in SEGMENTS:
		var s = em.spawn(EnemyManager.SEG, p - dir * SPACING * (i + 1))
		s.link = head
		s.r = lerpf(1.25, 0.7, float(i) / SEGMENTS)
		segs.append(s)
		var nd := _model("res://art/models/yilan_govde.glb", lerpf(2.1, 1.1, float(i) / SEGMENTS))
		add_child(nd)
		seg_nodes.append(nd)
	# It bursts out of the ground: dust and a roar.
	g.fx.ring(p, 9.0, Color(1.0, 0.4, 0.6), 0.6, 0.25, 0.25)
	for k in 4:
		g.fx.dust(p + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), 8)
	Sfx.play("serpent", Vector3.INF, 1.0, 0.0)
	g.shake(0.6)
	g.ui.banner("ARA BOSS", "Kor Yılanı", Color(1.0, 0.45, 0.75))
	g.ui.show_boss_bar(true, "Kor Yılanı", head)
	state = "hunt"
	timer = 3.5

func _model(path: String, h: float) -> Node3D:
	var n := Models.prop(path, h)
	if n == null:
		n = Node3D.new()
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = h * 0.5
		sp.height = h
		mi.mesh = sp
		mi.position.y = h * 0.5
		n.add_child(mi)
	Game.inst.world.apply_fade(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = overlay
	return n

func _overlay() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never;
uniform float flash = 0.0;
uniform float warn = 0.0;
global uniform float night;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.6 + 0.4 * sin(TIME * 30.0);
	ALBEDO = vec3(1.0, 0.85, 0.8) * flash * 0.1 + vec3(1.0, 0.1, 0.05) * warn * pulse * 0.8 + vec3(1.0, 0.3, 0.6) * rim * (0.45 + night * 0.4);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func on_hit(dealt: float) -> void:
	taken += dealt

func on_killed() -> void:
	var g = Game.inst
	dying = true
	die_t = 0.0
	die_i = SEGMENTS - 1
	g.serpent_killed = true
	g.ui.show_boss_bar(false)
	g.shake(0.6)
	Sfx.play("roar", Vector3.INF, 0.8, 0.0, 1.3)

func _process(dt: float) -> void:
	if not active:
		return
	var g = Game.inst
	if g.state != Game.S_PLAY:
		return
	if dying:
		_die_step(dt)
		return
	if head == null or not head.alive:
		return
	_calibrate(dt)
	var pp: Vector3 = g.player.global_position
	var hp0: Vector3 = head.pos
	var to: Vector3 = pp - hp0
	to.y = 0
	var dist: float = to.length()
	var want: Vector3 = to / maxf(dist, 0.01)
	var speed := 6.8
	timer -= dt
	var warn := 0.0
	match state:
		"hunt":
			weave += dt * 2.2
			want = want.rotated(Vector3.UP, sin(weave) * 0.7)
			if timer <= 0.0:
				if dist < 22.0 and randf() < 0.55:
					state = "aim"
					timer = 0.9
					dir = to / maxf(dist, 0.01)
					g.fx.lane(head.pos, dir, 24.0, 2.6, 0.9)
					Sfx.play("charge", head.pos, 1.0, 0.05, 0.7)
				else:
					state = "spit"
					timer = 1.2
		"aim":
			speed = 0.0
			warn = 1.0
			want = dir
			if timer <= 0.0:
				state = "dive"
				timer = 1.1
		"dive":
			speed = 21.0
			want = dir
			if Engine.get_process_frames() % 2 == 0:
				g.fx.dust(head.pos, 3)
			if timer <= 0.0:
				state = "hunt"
				timer = randf_range(3.0, 4.5)
				g.shake(0.2)
		"spit":
			speed = 1.5
			warn = 0.5
			if timer <= 0.6 and timer + dt > 0.6:
				var base := atan2(to.x, to.z)
				for k in 9:
					var a := base + (k - 4) * 0.16
					g.em.add_bullet(head.pos + Vector3(0, 1.6, 0), Vector3(sin(a), 0, cos(a)) * 10.0, 4.0)
				Sfx.play("explode", head.pos, 0.6, 0.1, 1.4)
			if timer <= 0.0:
				state = "hunt"
				timer = randf_range(3.0, 4.5)
	# Turn gradually, except during the dive which is committed.
	if state != "dive" and state != "aim":
		dir = dir.slerp(want, minf(1.0, dt * 2.6)).normalized()
	# Stay on the island.
	var hl: float = Vector2(head.pos.x, head.pos.z).length()
	var edge: float = g.world.island_radius - 4.0
	if hl > edge:
		var inward := -Vector3(head.pos.x, 0, head.pos.z).normalized()
		dir = dir.slerp(inward, minf(1.0, dt * 5.0)).normalized()
		if hl > edge + 2.0:
			head.pos = Vector3(head.pos.x, 0, head.pos.z) * ((edge + 2.0) / hl)
	head.pos += dir * speed * dt
	head.yaw = atan2(dir.x, dir.z)
	# Record the trail and lay the body along it.
	if trail.is_empty() or trail[0].distance_to(head.pos) > SPACING / 8.0:
		trail.push_front(head.pos)
		if trail.size() > SEGMENTS * 8 + 8:
			trail.pop_back()
	_layout(dt)
	head_node.position = head.pos
	head_node.rotation.y = head.yaw
	head_node.position.y = (0.6 if state == "spit" else 0.0) + sin(Time.get_ticks_msec() * 0.006) * 0.1
	overlay.set_shader_parameter("flash", head.flash)
	overlay.set_shader_parameter("warn", warn)

func _layout(_dt: float) -> void:
	for i in segs.size():
		var idx := mini((i + 1) * 8, trail.size() - 1)
		var p: Vector3 = trail[idx]
		var ahead: Vector3 = trail[maxi(idx - 4, 0)]
		var s = segs[i]
		s.pos = p
		var nd: Node3D = seg_nodes[i]
		nd.position = p + Vector3(0, absf(sin(Time.get_ticks_msec() * 0.005 + i * 0.6)) * 0.15, 0)
		var d: Vector3 = ahead - p
		if d.length() > 0.01:
			nd.rotation.y = atan2(d.x, d.z)

## Size its health from the damage it actually takes in the first seconds, so the
## fight lasts about 35 s for any build.
func _calibrate(dt: float) -> void:
	if calibrated:
		return
	if taken > 0.0:
		fight_t += dt
	if fight_t < 6.0 and head.hp > head.max_hp * 0.3:
		return
	calibrated = true
	var rate := taken / maxf(fight_t, 0.1)
	var total := maxf(2500.0, taken + rate * 30.0)
	head.max_hp = total
	head.hp = total - taken

## Tail-to-head chain of bursts, then the head, then the reward.
func _die_step(dt: float) -> void:
	var g = Game.inst
	die_t -= dt
	if die_t > 0.0:
		return
	die_t = 0.09
	if die_i >= 0:
		var s = segs[die_i]
		var p: Vector3 = s.pos
		g.fx.burst(p + Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.7), 16, 1.8)
		g.fx.ring(p, 3.0, Color(1.0, 0.5, 0.3), 0.3, 0.3, 0.2)
		Sfx.play("explode", p, 0.8)
		g.shake(0.08)
		s.alive = false
		seg_nodes[die_i].visible = false
		for i in 2:
			g.pickups.gem(p + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), 6)
		die_i -= 1
		return
	var hp: Vector3 = head.pos
	g.fx.burst(hp + Vector3(0, 1.5, 0), Color(1.0, 0.5, 0.8), 50, 3.0)
	g.fx.burst(hp + Vector3(0, 1.5, 0), Color(1.0, 0.85, 0.4), 30, 2.4)
	g.fx.ring(hp, 10.0, Color(1.0, 0.6, 0.3), 0.6, 0.25, 0.25)
	Sfx.play("slam", Vector3.INF, 1.0, 0.0)
	g.shake(0.7)
	head_node.visible = false
	g.pickups.spawn_chest(hp, Models.prop(g.chest_model_path, 1.4))
	g.pickups.item(hp + Vector3(1.5, 0, 0), "heal")
	g.ui.banner("YENİLDİ", "Kor Yılanı", Color(1.0, 0.8, 0.4), 1.8)
	active = false
	dying = false
