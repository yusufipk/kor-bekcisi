extends CanvasLayer
## All screens built in code: title, HUD, level-up cards, pause/settings, end.

const ACCENT := Color(1.0, 0.62, 0.22)
const TEAL := Color(0.35, 0.85, 0.8)
const PANEL_BG := Color(0.12, 0.09, 0.16, 0.92)

var g
var root: Control
var hud: Control
var hp_bar: ProgressBar
var hp_label: Label
var xp_bar: ProgressBar
var lv_label: Label
var time_label: Label
var kill_label: Label
var weapon_row: HBoxContainer
var passive_row: HBoxContainer
var banner_box: VBoxContainer
var reroll_btn: Button
var banner_tw: Tween
var toast_label: Label
var toast_t := 0.0
var hint_label: Label
var hint_t := 0.0
var boss_box: Control
var boss_bar: ProgressBar
var boss_label: Label
var bar_target = null
var vignette: ColorRect
var markers: Array = []
var threat_arrow: Label
var slide_bar: ProgressBar
var demo_label: Label

var title_layer: Control
var lvl_layer: Control
var lvl_title: Label
var lvl_cards: HBoxContainer
var cur_choices: Array = []
var pause_layer: Control
var pause_build: VBoxContainer
var end_layer: Control

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	g = Game.inst
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme = _theme()
	_build_hud()
	_build_levelup()
	_build_pause()

func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 20
	th.set_color("font_outline_color", "Label", Color(0.08, 0.04, 0.1))
	th.set_constant("outline_size", "Label", 6)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.18, 0.3)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.85, 0.45, 0.15)
	th.set_stylebox("normal", "Button", sb)
	th.set_stylebox("hover", "Button", sbh)
	th.set_stylebox("pressed", "Button", sbh)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_font_size("font_size", "Button", 22)
	return th

func _label(txt: String, size: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _bar(col: Color, bg: Color, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size.y = h
	var f := StyleBoxFlat.new()
	f.bg_color = col
	f.set_corner_radius_all(int(h * 0.5))
	var k := StyleBoxFlat.new()
	k.bg_color = bg
	k.set_corner_radius_all(int(h * 0.5))
	b.add_theme_stylebox_override("fill", f)
	b.add_theme_stylebox_override("background", k)
	return b

func _panel(bg := PANEL_BG) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 28; sb.content_margin_right = 28
	sb.content_margin_top = 22; sb.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", sb)
	return p

# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(0.9, 0.05, 0.1, smoothstep(0.35, 0.75, d) * amount);
}
"""
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vignette.material = vm
	hud.add_child(vignette)
	# XP across the top
	xp_bar = _bar(Color(1.0, 0.8, 0.3), Color(0, 0, 0, 0.45), 12)
	xp_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	xp_bar.offset_left = 16; xp_bar.offset_right = -16; xp_bar.offset_top = 10; xp_bar.offset_bottom = 22
	hud.add_child(xp_bar)
	lv_label = _label("Sv 1", 24, Color(1.0, 0.85, 0.4))
	lv_label.position = Vector2(20, 26)
	hud.add_child(lv_label)
	time_label = _label("00:00", 40)
	time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.offset_left = -100; time_label.offset_right = 100; time_label.offset_top = 24
	hud.add_child(time_label)
	kill_label = _label("☠ 0", 26)
	kill_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kill_label.offset_left = -220; kill_label.offset_right = -20; kill_label.offset_top = 26
	hud.add_child(kill_label)
	# HP bottom-left
	var hpbox := VBoxContainer.new()
	hpbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hpbox.offset_left = 24; hpbox.offset_top = -140; hpbox.offset_right = 384; hpbox.offset_bottom = -20
	hud.add_child(hpbox)
	weapon_row = HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 8)
	hpbox.add_child(weapon_row)
	passive_row = HBoxContainer.new()
	passive_row.add_theme_constant_override("separation", 6)
	hpbox.add_child(passive_row)
	for i in Upgrades.MAX_WEAPONS:
		weapon_row.add_child(_badge("", Color.WHITE, 46))
	for i in Upgrades.MAX_PASSIVES:
		passive_row.add_child(_badge("", Color.WHITE, 32))
	var hprow := HBoxContainer.new()
	hpbox.add_child(hprow)
	hp_bar = _bar(Color(0.95, 0.3, 0.32), Color(0, 0, 0, 0.5), 22)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hprow.add_child(hp_bar)
	hp_label = _label("100", 22)
	hp_label.custom_minimum_size.x = 64
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hprow.add_child(hp_label)
	slide_bar = _bar(TEAL, Color(0, 0, 0, 0.4), 6)
	hpbox.add_child(slide_bar)
	toast_label = _label("", 28, Color(1.0, 0.92, 0.7))
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.offset_left = -600; toast_label.offset_right = 600; toast_label.offset_top = 150
	hud.add_child(toast_label)
	hint_label = _label("", 22, Color(1, 1, 1, 0.9))
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.offset_left = -600; hint_label.offset_right = 600; hint_label.offset_top = -150; hint_label.offset_bottom = -110
	hud.add_child(hint_label)
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.offset_left = -360; boss_box.offset_right = 360; boss_box.offset_top = 82; boss_box.offset_bottom = 130
	boss_box.visible = false
	hud.add_child(boss_box)
	boss_label = _label("Kül Devi", 22, Color(1.0, 0.68, 0.35))
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_label)
	boss_bar = _bar(Color(1.0, 0.45, 0.12), Color(0, 0, 0, 0.55), 18)
	boss_box.add_child(boss_bar)
	for i in 8:
		var m := _label("", 26)
		m.visible = false
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.size = Vector2(60, 34)
		hud.add_child(m)
		markers.append(m)
	threat_arrow = _label("▲", 56, Color(1.0, 0.45, 0.15))
	threat_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	threat_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Fixed box larger than the glyph, so the pivot stays at its centre.
	threat_arrow.custom_minimum_size = Vector2(110, 110)
	threat_arrow.size = Vector2(110, 110)
	threat_arrow.pivot_offset = Vector2(55, 55)
	threat_arrow.add_theme_constant_override("outline_size", 10)
	threat_arrow.visible = false
	hud.add_child(threat_arrow)
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER)
	banner_box.offset_left = -500; banner_box.offset_right = 500; banner_box.offset_top = -190; banner_box.offset_bottom = -60
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.pivot_offset = Vector2(500, 65)
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.visible = false
	hud.add_child(banner_box)
	demo_label = _label("DEMO", 18, Color(0.6, 1.0, 1.0))
	demo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	demo_label.offset_left = -120; demo_label.offset_top = 60; demo_label.offset_right = -20
	demo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	demo_label.visible = false
	hud.add_child(demo_label)

func show_hud() -> void:
	if title_layer:
		title_layer.queue_free()
		title_layer = null
	hud.visible = true
	demo_label.visible = g.demo

func hint(txt: String, dur: float) -> void:
	hint_label.text = txt
	hint_t = dur

func toast(txt: String, dur := 3.0) -> void:
	toast_label.text = txt
	toast_t = dur

func show_boss_bar(on: bool, title := "Kül Devi", target = null) -> void:
	boss_box.visible = on
	boss_label.text = title
	bar_target = target

func update_hud() -> void:
	var p = g.player
	hp_bar.max_value = p.max_hp
	hp_bar.value = p.hp
	hp_label.text = str(int(ceil(p.hp)))
	xp_bar.max_value = g.xp_next
	xp_bar.value = g.xp
	lv_label.text = "Sv %d" % g.level
	var remain: float = Game.BOSS_TIME - g.t
	time_label.text = Game.fmt_time(g.t)
	time_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.6) if remain < 30.0 and remain > 0.0 else Color.WHITE)
	kill_label.text = "☠ %d" % g.kills
	slide_bar.max_value = 1.0
	slide_bar.value = 1.0 - clampf(p.slide_cd / maxf(0.01, p.SLIDE_CD * g.st.slide_cd), 0.0, 1.0)
	var dt := get_process_delta_time()
	toast_t -= dt
	toast_label.modulate.a = clampf(toast_t, 0.0, 1.0)
	hint_t -= dt
	hint_label.modulate.a = clampf(hint_t, 0.0, 1.0)
	(vignette.material as ShaderMaterial).set_shader_parameter("amount", maxf(p.hurt_flash * 0.8, (1.0 - p.hp / p.max_hp) * 0.45 if p.hp < p.max_hp * 0.35 else 0.0))
	var bt = bar_target if bar_target != null else g.em.boss
	if bt and bt.alive:
		boss_bar.max_value = bt.max_hp
		boss_bar.value = bt.hp
	if Engine.get_process_frames() % 10 == 0:
		_refresh_weapons()
	_update_markers()

func _refresh_weapons() -> void:
	var ids: Array = g.weapons.lv.keys()
	for i in Upgrades.MAX_WEAPONS:
		var b: PanelContainer = weapon_row.get_child(i)
		var lab: Label = b.get_child(0)
		var sb := b.get_theme_stylebox("panel") as StyleBoxFlat
		if i >= ids.size():
			lab.text = ""
			sb.bg_color = Color(1, 1, 1, 0.06)
			sb.border_color = Color(1, 1, 1, 0.18)
			sb.set_border_width_all(1)
			continue
		var id: String = ids[i]
		var lvl: int = g.weapons.lv[id]
		if lvl >= Upgrades.EVO_LEVEL:
			var e: Dictionary = Upgrades.EVOS[id]
			lab.text = e["icon"]
			sb.bg_color = Color(e["color"], 0.55)
			sb.border_color = Color(1.0, 0.95, 0.6)
			sb.set_border_width_all(3)
			continue
		var w: Dictionary = Upgrades.WEAPONS[id]
		lab.text = "%s%d" % [w["icon"], lvl] if lvl < Upgrades.WEAPON_MAX else "%s★" % w["icon"]
		sb.bg_color = Color(w["color"], 0.35)
		sb.border_color = Color(1.0, 0.85, 0.3)
		sb.set_border_width_all(2 if lvl >= Upgrades.WEAPON_MAX else 0)
	var pids: Array = g.passives.keys()
	for i in Upgrades.MAX_PASSIVES:
		var b: PanelContainer = passive_row.get_child(i)
		var lab: Label = b.get_child(0)
		var sb := b.get_theme_stylebox("panel") as StyleBoxFlat
		if i >= pids.size():
			lab.text = ""
			sb.bg_color = Color(1, 1, 1, 0.06)
			sb.border_color = Color(1, 1, 1, 0.18)
			sb.set_border_width_all(1)
			continue
		var pid: String = pids[i]
		lab.text = "%s%d" % [Upgrades.PASSIVES[pid]["icon"], g.passives[pid]]
		sb.bg_color = Color(TEAL, 0.3)
		sb.set_border_width_all(0)

## Big centred announcement (evolutions, mini-boss, boss).
func banner(top: String, main: String, col: Color, dur := 2.6) -> void:
	for c in banner_box.get_children():
		c.queue_free()
	var a := _label(top, 30, col.lightened(0.3))
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(a)
	var b := _label(main, 76, col)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("outline_size", 12)
	banner_box.add_child(b)
	banner_box.visible = true
	banner_box.modulate.a = 0.0
	banner_box.scale = Vector2(1.4, 1.4)
	if banner_tw and banner_tw.is_valid():
		banner_tw.kill()
	var tw := create_tween()
	banner_tw = tw
	tw.set_parallel(true)
	tw.tween_property(banner_box, "modulate:a", 1.0, 0.2)
	tw.tween_property(banner_box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(dur)
	tw.chain().tween_property(banner_box, "modulate:a", 0.0, 0.5)

func _badge(txt: String, col: Color, sz: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(sz, sz * 0.8)
	var l := _label(txt, int(sz * 0.5))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

## Edge markers for chests and the nearest unlit lantern, so exploring has a
## direction. Off-screen markers stay inside a safe band clear of the HUD and are
## pushed apart so they never print over each other or over the health number.
func _update_markers() -> void:
	var cam: Camera3D = g.cam
	var vp := get_viewport().get_visible_rect().size
	var pp: Vector3 = g.player.global_position
	var targets: Array = []
	var chests: Array = g.pickups.chests.duplicate()
	chests.sort_custom(func(x, y): return pp.distance_squared_to(x.position) < pp.distance_squared_to(y.position))
	for k in mini(chests.size(), 2):
		targets.append([chests[k].position + Vector3(0, 1, 0), "▼", Color(1.0, 0.85, 0.3)])
	var best = null
	for s in g.shrines:
		if not s["lit"] and (best == null or pp.distance_squared_to(s["p"]) < pp.distance_squared_to(best["p"])):
			best = s
	if best != null:
		targets.append([best["p"] + Vector3(0, 4.5, 0), "✦", Color(1.0, 0.7, 0.4)])
	var lo := Vector2(70.0, 150.0)
	var hi := Vector2(vp.x - 70.0, vp.y - 180.0)
	var placed: Array = []
	for i in markers.size():
		var m: Label = markers[i]
		if i >= targets.size():
			m.visible = false
			continue
		var wp: Vector3 = targets[i][0]
		var r := _edge_point(cam, wp, vp, lo, hi)
		var sp: Vector2 = r[0]
		var on: bool = r[1]
		if not on:
			for q in placed:
				if sp.distance_to(q) < 46.0:
					sp.y += 46.0 if sp.y < hi.y - 46.0 else -46.0
		placed.append(sp)
		m.text = targets[i][1] if on else "%s %dm" % [targets[i][1], int(pp.distance_to(wp))]
		m.add_theme_color_override("font_color", targets[i][2])
		m.add_theme_font_size_override("font_size", 30 if on else 22)
		m.size = Vector2(120, 36)
		m.position = sp - m.size * 0.5
		m.visible = true
	_update_threat_arrow(cam, vp, lo, hi)

## Screen point for a world position; off-screen ones are pulled to the edge of
## the [lo, hi] band along the line from the screen centre. Returns [point, on].
func _edge_point(cam: Camera3D, wp: Vector3, vp: Vector2, lo: Vector2, hi: Vector2) -> Array:
	var behind := cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp)
	var on := not behind and sp.x > 40.0 and sp.x < vp.x - 40.0 and sp.y > 40.0 and sp.y < vp.y - 40.0
	if on:
		return [sp, true]
	var c := (lo + hi) * 0.5
	if behind:
		sp = c - (sp - c) * 10.0
	var d := sp - c
	var half := (hi - lo) * 0.5
	var k := minf(half.x / maxf(absf(d.x), 0.01), half.y / maxf(absf(d.y), 0.01))
	return [c + d * minf(k, 1.0), false]

## A big arrow at the screen edge while the boss or the serpent is out of view.
func _update_threat_arrow(cam: Camera3D, vp: Vector2, lo: Vector2, hi: Vector2) -> void:
	var tgt = null
	if g.em.boss != null and g.em.boss.alive:
		tgt = g.em.boss
	elif g.serpent and g.serpent.active and g.serpent.head and g.serpent.head.alive:
		tgt = g.serpent.head
	if tgt == null:
		threat_arrow.visible = false
		return
	var r := _edge_point(cam, tgt.pos + Vector3(0, 3.0, 0), vp, lo, hi)
	if r[1]:
		threat_arrow.visible = false
		return
	var sp: Vector2 = r[0]
	var d: Vector2 = sp - (lo + hi) * 0.5
	threat_arrow.visible = true
	threat_arrow.position = sp - threat_arrow.size * 0.5
	threat_arrow.rotation = d.angle() + PI * 0.5
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
	threat_arrow.modulate = Color(1, 1, 1, pulse)

# ------------------------------------------------------------------ title

func show_title(rec: Dictionary) -> void:
	title_layer = Control.new()
	title_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_layer)
	var bg := TextureRect.new()
	bg.texture = load("res://art/ui/kapak.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	title_layer.add_child(bg)
	# Slow push-in on the key art and embers drifting up keep the menu alive.
	bg.resized.connect(func(): bg.pivot_offset = bg.size * 0.5)
	var kb := bg.create_tween().set_loops()
	kb.tween_property(bg, "scale", Vector2(1.07, 1.07), 18.0).set_trans(Tween.TRANS_SINE)
	kb.tween_property(bg, "scale", Vector2(1.0, 1.0), 18.0).set_trans(Tween.TRANS_SINE)
	var embers := CPUParticles2D.new()
	embers.amount = 70
	embers.lifetime = 7.0
	embers.preprocess = 7.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(1100, 10)
	embers.direction = Vector2(0, -1)
	embers.spread = 25.0
	embers.gravity = Vector2(0, -12)
	embers.initial_velocity_min = 30.0
	embers.initial_velocity_max = 80.0
	embers.scale_amount_min = 2.0
	embers.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.35, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.6, 0.25, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.35, 0.2, 0.0))
	embers.color_ramp = ramp
	title_layer.add_child(embers)
	title_layer.resized.connect(func(): embers.position = Vector2(title_layer.size.x * 0.5, title_layer.size.y + 20))
	embers.position = Vector2(800, 920)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var gs := Shader.new()
	gs.code = """
shader_type canvas_item;
void fragment() { COLOR = vec4(0.08, 0.04, 0.12, mix(0.88, 0.05, smoothstep(0.25, 0.65, UV.x))); }
"""
	var gm := ShaderMaterial.new()
	gm.shader = gs
	shade.material = gm
	title_layer.add_child(shade)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 80; col.offset_right = 640
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	title_layer.add_child(col)
	col.add_child(_label("Kor Bekçisi", 84, ACCENT))
	col.add_child(_label("Fenerleri yak, 10 dakika dayan, Kül Devi'ni devir.", 24, Color(1, 0.93, 0.85)))
	var keys := GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", 18)
	keys.add_theme_constant_override("v_separation", 6)
	for pair in [["WASD", "koş"], ["Boşluk", "zıpla (alçak düşmanların üstünden)"], ["Shift / sağ tık", "kay (kayarken dokunulmazsın)"], ["Fare", "kamerayı çevir"], ["Esc", "duraklat ve ayarlar"]]:
		keys.add_child(_label(pair[0], 20, TEAL))
		keys.add_child(_label(pair[1], 20))
	col.add_child(keys)
	var start := Button.new()
	start.text = "Başla"
	start.custom_minimum_size = Vector2(260, 60)
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.pressed.connect(func(): g.start_run())
	col.add_child(start)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var altar := Button.new()
	altar.text = "Kor Sunağı  ·  %d kor" % g.meta.kor
	altar.custom_minimum_size = Vector2(300, 50)
	altar.pressed.connect(func(): _altar())
	row.add_child(altar)
	var set_btn := Button.new()
	set_btn.text = "Ayarlar"
	set_btn.custom_minimum_size = Vector2(160, 50)
	set_btn.pressed.connect(func(): _settings_popup())
	row.add_child(set_btn)
	if g.meta.rank("start") > 0:
		col.add_child(_start_picker())
	col.add_child(_evo_strip())
	if rec["runs"] > 0:
		col.add_child(_label("En uzun tur %s  ·  En çok %d düşman  ·  %d zafer" % [Game.fmt_time(rec["best_time"]), rec["best_kills"], rec["wins"]], 20, Color(1, 0.85, 0.5)))
	start.grab_focus()

## Row of starting weapons (unlocked at the altar).
func _start_picker() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var name_l := _label("Başlangıç: " + Upgrades.WEAPONS[g.meta.start_weapon]["name"], 20, TEAL)
	name_l.custom_minimum_size.x = 250
	h.add_child(name_l)
	for id in Upgrades.WEAPONS.keys():
		var w: Dictionary = Upgrades.WEAPONS[id]
		var b := Button.new()
		b.text = w["icon"]
		b.tooltip_text = w["name"]
		b.custom_minimum_size = Vector2(44, 40)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(w["color"], 0.55 if id == g.meta.start_weapon else 0.15)
		sb.set_corner_radius_all(8)
		sb.border_color = Color(1.0, 0.85, 0.3)
		sb.set_border_width_all(2 if id == g.meta.start_weapon else 0)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func():
			g.meta.start_weapon = id
			g.meta.save_cfg()
			var par := h.get_parent()
			var idx := h.get_index()
			h.queue_free()
			var nh := _start_picker()
			par.add_child(nh)
			par.move_child(nh, idx))
		h.add_child(b)
	return h

## The seven evolutions as a collection: lit when discovered.
func _evo_strip() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var n: int = g.meta.discovered.size()
	var l := _label("Dönüşümler %d / %d" % [n, Upgrades.EVOS.size()], 20, Color(1.0, 0.9, 0.55))
	l.custom_minimum_size.x = 250
	h.add_child(l)
	for id in Upgrades.EVOS.keys():
		var e: Dictionary = Upgrades.EVOS[id]
		var known: bool = g.meta.discovered.has(id)
		var b := _badge(e["icon"] if known else "?", e["color"] if known else Color(0.5, 0.5, 0.6), 44)
		b.tooltip_text = e["name"] if known else "%s + %s" % [Upgrades.WEAPONS[id]["name"], Upgrades.PASSIVES[e["partner"]]["name"]]
		if not known:
			(b.get_child(0) as Label).add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
		h.add_child(b)
	return h

## Kor Sunağı: permanent upgrades on the left, the evolution book on the right.
func _altar() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.02, 0.07, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	cc.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	head.add_child(_label("Kor Sunağı", 48, ACCENT))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var bal := _label("%d kor" % g.meta.kor, 34, Color(1.0, 0.8, 0.4))
	head.add_child(bal)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	outer.add_child(h)
	var left := _panel()
	left.custom_minimum_size = Vector2(720, 520)
	h.add_child(left)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	left.add_child(grid)
	var right := _panel()
	right.custom_minimum_size = Vector2(440, 520)
	h.add_child(right)
	var book := VBoxContainer.new()
	book.add_theme_constant_override("separation", 10)
	right.add_child(book)
	# Lambdas capture locals by value, so the self-reference goes through an array.
	var holder: Array = []
	var rebuild := func():
		for c in grid.get_children():
			c.queue_free()
		bal.text = "%d kor" % g.meta.kor
		for u in g.meta.UPGRADES:
			grid.add_child(_altar_tile(u, holder[0]))
	holder.append(rebuild)
	rebuild.call()
	book.add_child(_label("Dönüşümler", 28, Color(1.0, 0.9, 0.55)))
	for id in Upgrades.EVOS.keys():
		var e: Dictionary = Upgrades.EVOS[id]
		var known: bool = g.meta.discovered.has(id)
		var recipe := "%s %s  +  %s %s" % [Upgrades.WEAPONS[id]["icon"], Upgrades.WEAPONS[id]["name"], Upgrades.PASSIVES[e["partner"]]["icon"], Upgrades.PASSIVES[e["partner"]]["name"]]
		book.add_child(_row(e["icon"] if known else "?", e["name"] if known else "???", "", e["color"] if known else Color(0.5, 0.5, 0.6)))
		var rl := _label(recipe, 17, Color(0.8, 0.78, 0.9))
		rl.custom_minimum_size.x = 380
		book.add_child(rl)
	var close := Button.new()
	close.text = "Kapat"
	close.custom_minimum_size = Vector2(240, 52)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		dim.queue_free()
		# Refresh the title so the kor count and pickers are current.
		if title_layer:
			title_layer.queue_free()
			title_layer = null
			show_title(g._load_record()))
	outer.add_child(close)
	close.grab_focus()

func _altar_tile(u: Dictionary, rebuild: Callable) -> Control:
	var id: String = u["id"]
	var r: int = g.meta.rank(id)
	var mx: int = (u["cost"] as Array).size()
	var cost: int = g.meta.next_cost(id)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.14, 0.26, 0.95)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(330, 128)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var badge := _badge(u["icon"], ACCENT, 54)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(badge)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	v.add_child(_label(u["name"], 21, Color(1, 0.92, 0.8)))
	v.add_child(_label(u["desc"], 17, Color(0.82, 0.8, 0.92)))
	var pips := ""
	for i in mx:
		pips += "●" if i < r else "○"
	v.add_child(_label(pips, 16, ACCENT))
	var b := Button.new()
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size = Vector2(92, 46)
	if cost < 0:
		b.text = "Tamam"
		b.disabled = true
	else:
		b.text = "%d" % cost
		b.disabled = g.meta.kor < cost
		b.pressed.connect(func():
			if g.meta.buy(id):
				Sfx.play("select", Vector3.INF, 1.0, 0.0)
				rebuild.call())
	h.add_child(b)
	return p

func _settings_popup() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var p := _panel()
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size.x = 520
	p.add_child(v)
	v.add_child(_label("Ayarlar", 34, ACCENT))
	_settings_controls(v)
	var close := Button.new()
	close.text = "Kapat"
	close.pressed.connect(func(): dim.queue_free())
	v.add_child(close)

func _settings_controls(parent: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(grid)
	_slider(grid, "Fare hassasiyeti", 0.2, 3.0, Settings.mouse_sens, func(v): Settings.mouse_sens = v, "%.1fx")
	_slider(grid, "Müzik", 0.0, 1.0, Settings.music_vol, func(v): Settings.music_vol = v, "%d%%", 100.0)
	_slider(grid, "Efektler", 0.0, 1.0, Settings.sfx_vol, func(v): Settings.sfx_vol = v, "%d%%", 100.0)
	_slider(grid, "Parlaklık", 0.6, 1.6, Settings.brightness, func(v): Settings.brightness = v, "%d%%", 100.0)
	var inv := CheckBox.new()
	inv.text = "Dikey ekseni ters çevir"
	inv.button_pressed = Settings.invert_y
	inv.toggled.connect(func(on): Settings.invert_y = on; Settings.save_cfg())
	parent.add_child(inv)

func _slider(grid: GridContainer, name: String, lo: float, hi: float, val: float, setter: Callable, fmt: String, mul := 1.0) -> void:
	grid.add_child(_label(name, 20))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = val
	s.custom_minimum_size = Vector2(240, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(s)
	var vl := _label(fmt % (val * mul), 20, TEAL)
	vl.custom_minimum_size.x = 64
	grid.add_child(vl)
	s.value_changed.connect(func(v):
		setter.call(v)
		vl.text = fmt % (v * mul)
		Settings.apply()
		Settings.save_cfg())

# ------------------------------------------------------------------ level-up

func _build_levelup() -> void:
	lvl_layer = ColorRect.new()
	(lvl_layer as ColorRect).color = Color(0.05, 0.02, 0.08, 0.6)
	lvl_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	lvl_layer.visible = false
	root.add_child(lvl_layer)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 26)
	lvl_layer.add_child(v)
	lvl_title = _label("", 54, ACCENT)
	lvl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lvl_title)
	lvl_cards = HBoxContainer.new()
	lvl_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	lvl_cards.add_theme_constant_override("separation", 24)
	v.add_child(lvl_cards)
	reroll_btn = Button.new()
	reroll_btn.custom_minimum_size = Vector2(300, 52)
	reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reroll_btn.pressed.connect(func(): g.reroll())
	v.add_child(reroll_btn)

func show_levelup(choices: Array, chest: bool) -> void:
	cur_choices = choices
	lvl_layer.visible = true
	var has_evo := false
	for c in choices:
		if c["kind"] == "e":
			has_evo = true
	var picks: int = g.pending_levels + g.pending_chest
	lvl_title.text = "Dönüşüm hazır!" if has_evo else ("Hazine!" if chest else "Seviye %d" % g.level)
	if picks > 1:
		lvl_title.text += "  ·  %d seçim" % picks
	lvl_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45) if has_evo else ACCENT)
	reroll_btn.text = "Yeniden çek  [R]   ×%d" % g.rerolls
	reroll_btn.visible = g.rerolls > 0
	for c in lvl_cards.get_children():
		c.queue_free()
	for i in choices.size():
		lvl_cards.add_child(_card(choices[i], i))
	lvl_layer.modulate.a = 0.0
	create_tween().tween_property(lvl_layer, "modulate:a", 1.0, 0.12)
	# Demo only: one frame of the card screen from level `card_shot` on.
	if g.demo and g.demo_cfg.has("card_shot") and g.level >= int(g.demo_cfg["card_shot"]) and not g.events_done.has("card_shot"):
		g.events_done["card_shot"] = true
		get_tree().create_timer(0.5, true, false, true).timeout.connect(func():
			var dir := str(g.demo_cfg.get("shot_dir", "user://shots"))
			DirAccess.make_dir_recursive_absolute(dir)
			get_viewport().get_texture().get_image().save_jpg(dir + "/kart.jpg", 0.85)
			print("SHOT card"))

func _card(c: Dictionary, i: int) -> Button:
	var id: String = c["id"]
	var kind: String = c["kind"]
	var is_w: bool = kind == "w"
	var d: Dictionary
	match kind:
		"w": d = Upgrades.WEAPONS[id]
		"p": d = Upgrades.PASSIVES[id]
		"e": d = Upgrades.EVOS[id]
		_: d = Upgrades.FILLER
	var cur: int = g.weapons.level(id) if is_w else g.passives.get(id, 0)
	var col: Color = d.get("color", TEAL)
	var b := Button.new()
	b.custom_minimum_size = Vector2(380, 160)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.11, 0.2, 0.97)
	sb.set_corner_radius_all(14)
	sb.border_color = col
	sb.set_border_width_all(3)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.3, 0.18, 0.28, 1.0)
	sbh.set_border_width_all(5)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.pressed.connect(func(): _pick(i))
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18; h.offset_right = -18; h.offset_top = 14; h.offset_bottom = -14
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var badge := _badge(d["icon"], col, 72)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(badge)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var nm := _label(d["name"], 24, col.lightened(0.2))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(nm)
	var tag_txt := "  Yeni" if cur == 0 else "  Sv %d" % (cur + 1)
	if is_w and cur + 1 >= Upgrades.WEAPON_MAX:
		tag_txt = "  Uyanış"
		sb.border_color = Color(1.0, 0.85, 0.3)
		sbh.border_color = Color(1.0, 0.85, 0.3)
	if kind == "e":
		tag_txt = ""
		sb.bg_color = Color(0.32, 0.22, 0.1, 0.98)
		sbh.bg_color = Color(0.45, 0.3, 0.12, 1.0)
		sb.border_color = Color(1.0, 0.9, 0.45)
		sbh.border_color = Color(1.0, 0.95, 0.6)
		sb.set_border_width_all(5)
		sbh.set_border_width_all(7)
	elif kind == "x":
		tag_txt = ""
	var gold := cur == 0 or tag_txt == "  Uyanış" or kind == "e"
	var tag := _label(tag_txt, 18, Color(1, 0.9, 0.5) if gold else Color(0.8, 0.8, 0.9))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tag)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	var key := _label(str(i + 1), 20, Color(1, 1, 1, 0.45))
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(key)
	var txt: String = d["desc"]
	if kind == "w":
		txt = Upgrades.weapon_card(id, cur + 1)
	elif kind == "p":
		txt = Upgrades.passive_card(id, g.st)
	var desc := _label(txt, 19)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 220
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc)
	return b

func _pick(i: int) -> void:
	if not lvl_layer.visible or i >= cur_choices.size():
		return
	var c = cur_choices[i]
	cur_choices = []
	g.choose(c)

func hide_levelup() -> void:
	lvl_layer.visible = false

func _unhandled_input(ev: InputEvent) -> void:
	if lvl_layer.visible and not g.demo:
		for k in 3:
			if ev.is_action_pressed("pick_%d" % (k + 1)):
				_pick(k)
				get_viewport().set_input_as_handled()
		if ev.is_action_pressed("restart"):
			g.reroll()
			get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ pause

func _build_pause() -> void:
	pause_layer = ColorRect.new()
	(pause_layer as ColorRect).color = Color(0.05, 0.02, 0.08, 0.72)
	pause_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.visible = false
	root.add_child(pause_layer)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(cc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	cc.add_child(h)
	var left := _panel()
	left.custom_minimum_size = Vector2(560, 420)
	h.add_child(left)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	left.add_child(v)
	v.add_child(_label("Duraklatıldı", 38, ACCENT))
	_settings_controls(v)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var cont := Button.new()
	cont.text = "Devam"
	cont.pressed.connect(func(): g.resume())
	row.add_child(cont)
	var rs := Button.new()
	rs.text = "Baştan başla"
	rs.pressed.connect(func(): g.restart())
	row.add_child(rs)
	var q := Button.new()
	q.text = "Çık"
	q.pressed.connect(func(): get_tree().quit())
	row.add_child(q)
	var right := _panel()
	right.custom_minimum_size = Vector2(380, 420)
	h.add_child(right)
	pause_build = VBoxContainer.new()
	pause_build.add_theme_constant_override("separation", 8)
	right.add_child(pause_build)

func _build_list(parent: Control) -> void:
	for c in parent.get_children():
		c.queue_free()
	parent.add_child(_label("Donanım", 28, ACCENT))
	for id in g.weapons.lv.keys():
		var lvl: int = g.weapons.lv[id]
		if lvl >= Upgrades.EVO_LEVEL:
			var e: Dictionary = Upgrades.EVOS[id]
			parent.add_child(_row(e["icon"], e["name"], "Dönüştü", e["color"]))
			continue
		var w: Dictionary = Upgrades.WEAPONS[id]
		parent.add_child(_row(w["icon"], w["name"], "Sv %d" % lvl, w["color"]))
	for id in g.passives.keys():
		var p: Dictionary = Upgrades.PASSIVES[id]
		parent.add_child(_row(p["icon"], p["name"], "Sv %d" % g.passives[id], TEAL))
	if g.shrines_lit > 0:
		parent.add_child(_row("✦", "Yanan fener", "%d / %d" % [g.shrines_lit, g.shrines.size()], Color(1.0, 0.75, 0.4)))

func _row(icon: String, name: String, val: String, col: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var b := _badge(icon, col, 34)
	h.add_child(b)
	var n := _label(name, 20)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(_label(val, 20, col.lightened(0.3)))
	return h

func show_pause() -> void:
	_build_list(pause_build)
	pause_layer.visible = true

func hide_pause() -> void:
	pause_layer.visible = false

# ------------------------------------------------------------------ end

func show_end(s: Dictionary) -> void:
	hud.visible = false
	lvl_layer.visible = false
	hide_pause()
	end_layer = ColorRect.new()
	(end_layer as ColorRect).color = Color(0.05, 0.02, 0.08, 0.72)
	end_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(end_layer)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_layer.add_child(cc)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 20)
	cc.add_child(outer)
	var title := _label("Kül Devi yenildi!" if s["victory"] else "Fenerin söndü", 64, ACCENT if s["victory"] else Color(1.0, 0.5, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	outer.add_child(h)
	var left := _panel()
	left.custom_minimum_size = Vector2(520, 0)
	h.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 14)
	left.add_child(lv)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 8)
	lv.add_child(grid)
	var rows := [
		["Süre", Game.fmt_time(s["time"])],
		["Seviye", str(s["level"])],
		["Düşman", _big(float(s["kills"]))],
		["Alınan hasar", str(int(s["taken"]))],
		["Fener", "%d / 5" % s["shrines"]],
		["Kristal", str(s["crystals"])],
	]
	for r in rows:
		grid.add_child(_label(r[0], 21, Color(0.85, 0.8, 0.95)))
		var vl := _label(r[1], 23, Color.WHITE)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.custom_minimum_size.x = 70
		grid.add_child(vl)
	# Damage by weapon: which part of the build carried the run.
	var wd: Dictionary = s["weapon_damage"]
	var ids: Array = []
	for id in wd.keys():
		if Upgrades.WEAPONS.has(id):
			ids.append(id)
	ids.sort_custom(func(x, y): return wd[x] > wd[y])
	var top := 1.0
	for id in ids:
		top = maxf(top, wd[id])
	lv.add_child(_label("Silah hasarı", 24, ACCENT))
	for id in ids:
		var evo: bool = s["weapons"].get(id, 0) >= Upgrades.EVO_LEVEL
		var d: Dictionary = Upgrades.EVOS[id] if evo else Upgrades.WEAPONS[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_badge(d["icon"], d["color"], 34))
		var nm := _label(d["name"], 19)
		nm.custom_minimum_size.x = 160
		row.add_child(nm)
		var bar := _bar(d["color"], Color(0, 0, 0, 0.35), 14)
		bar.max_value = top
		bar.value = wd[id]
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var nl := _label(_big(wd[id]), 19, Color(0.9, 0.88, 0.95))
		nl.custom_minimum_size.x = 92
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(nl)
		lv.add_child(row)
	var right := _panel()
	right.custom_minimum_size = Vector2(400, 0)
	h.add_child(right)
	var bl := VBoxContainer.new()
	bl.add_theme_constant_override("separation", 8)
	right.add_child(bl)
	_build_list(bl)
	# Reward and discoveries, then the record.
	var line := "+%d kor  ·  sunakta %d kor" % [s["kor"], s["kor_total"]]
	if s["demo"]:
		line = "Demo turu, rekora ve sunağa yazılmadı"
	var rl := _label(line, 28, Color(1.0, 0.8, 0.4))
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(rl)
	for id in s["new_discoveries"]:
		var e: Dictionary = Upgrades.EVOS[id]
		var dl := _label("Yeni dönüşüm keşfedildi: %s %s" % [e["icon"], e["name"]], 22, e["color"])
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(dl)
	var best: Dictionary = s["best"]
	if not s["demo"] and (s["new_best"] or best["runs"] > 0):
		var rec_txt := "Yeni rekor!" if s["new_best"] else "Rekor %s  ·  %d düşman" % [Game.fmt_time(best["best_time"]), best["best_kills"]]
		var rb := _label(rec_txt, 22, Color(0.95, 0.9, 1.0))
		rb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(rb)
	var again := Button.new()
	again.text = "Bir tur daha  [R]"
	again.custom_minimum_size = Vector2(320, 64)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(func(): g.restart())
	outer.add_child(again)
	# Keys mashed in the last second of a run must not skip the summary.
	again.disabled = true
	get_tree().create_timer(1.2, true, false, true).timeout.connect(func():
		if is_instance_valid(again):
			again.disabled = false
			again.grab_focus())

## Turkish style short numbers: 4,5 mn, 154 bin.
func _big(v: float) -> String:
	if v >= 1000000.0:
		return ("%.1f mn" % (v / 1000000.0)).replace(".", ",")
	if v >= 10000.0:
		return "%d bin" % int(v / 1000.0)
	if v >= 1000.0:
		return ("%.1f bin" % (v / 1000.0)).replace(".", ",")
	return str(int(v))
