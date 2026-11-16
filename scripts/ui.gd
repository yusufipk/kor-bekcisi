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
var toast_label: Label
var toast_t := 0.0
var hint_label: Label
var hint_t := 0.0
var boss_box: Control
var boss_bar: ProgressBar
var vignette: ColorRect
var markers: Array = []
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
	hpbox.offset_left = 24; hpbox.offset_top = -96; hpbox.offset_right = 384; hpbox.offset_bottom = -20
	hud.add_child(hpbox)
	weapon_row = HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 8)
	hpbox.add_child(weapon_row)
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
	var bl := _label("Kül Devi", 22, Color(1.0, 0.5, 0.75))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(bl)
	boss_bar = _bar(Color(0.95, 0.25, 0.6), Color(0, 0, 0, 0.55), 18)
	boss_box.add_child(boss_bar)
	for i in 8:
		var m := _label("", 26)
		m.visible = false
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.size = Vector2(60, 34)
		hud.add_child(m)
		markers.append(m)
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

func show_boss_bar(on: bool) -> void:
	boss_box.visible = on

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
	if g.em.boss and g.em.boss.alive:
		boss_bar.max_value = g.em.boss.max_hp
		boss_bar.value = g.em.boss.hp
	if Engine.get_process_frames() % 10 == 0:
		_refresh_weapons()
	_update_markers()

func _refresh_weapons() -> void:
	var ids: Array = g.weapons.lv.keys()
	while weapon_row.get_child_count() < ids.size():
		var l := _badge("", Color.WHITE, 42)
		weapon_row.add_child(l)
	for i in ids.size():
		var id: String = ids[i]
		var w: Dictionary = Upgrades.WEAPONS[id]
		var b: PanelContainer = weapon_row.get_child(i)
		var lab: Label = b.get_child(0)
		var lvl: int = g.weapons.lv[id]
		lab.text = "%s%d" % [w["icon"], lvl] if lvl < Upgrades.WEAPON_MAX else "%s★" % w["icon"]
		var sb := b.get_theme_stylebox("panel") as StyleBoxFlat
		sb.bg_color = Color(w["color"], 0.35)
		sb.border_color = Color(1.0, 0.85, 0.3)
		sb.set_border_width_all(2 if lvl >= Upgrades.WEAPON_MAX else 0)

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

## Edge markers for chests and unlit lanterns, so exploring has a direction.
func _update_markers() -> void:
	var cam: Camera3D = g.cam
	var vp := get_viewport().get_visible_rect().size
	var targets: Array = []
	for c in g.pickups.chests:
		targets.append([c.position + Vector3(0, 1, 0), "▼", Color(1.0, 0.85, 0.3)])
	for s in g.shrines:
		if not s["lit"]:
			targets.append([s["p"] + Vector3(0, 4.5, 0), "✦", Color(1.0, 0.7, 0.4)])
	for i in markers.size():
		var m: Label = markers[i]
		if i >= targets.size():
			m.visible = false
			continue
		var wp: Vector3 = targets[i][0]
		var behind := cam.is_position_behind(wp)
		var sp := cam.unproject_position(wp)
		var margin := 40.0
		var on := not behind and sp.x > margin and sp.x < vp.x - margin and sp.y > margin and sp.y < vp.y - margin
		var c := vp * 0.5
		if behind:
			sp = c - (sp - c) * 10.0
		if not on:
			var d := sp - c
			var k := minf((c.x - margin) / maxf(absf(d.x), 0.01), (c.y - margin) / maxf(absf(d.y), 0.01))
			sp = c + d * minf(k, 1.0)
		var dist: float = g.player.global_position.distance_to(wp)
		m.text = "%s\n%dm" % [targets[i][1], int(dist)] if not on else targets[i][1]
		m.add_theme_color_override("font_color", targets[i][2])
		m.add_theme_font_size_override("font_size", 22 if not on else 30)
		m.position = sp - Vector2(30, 17)
		m.visible = true

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
	var set_btn := Button.new()
	set_btn.text = "Ayarlar"
	set_btn.custom_minimum_size = Vector2(260, 50)
	set_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	set_btn.pressed.connect(func(): _settings_popup())
	col.add_child(set_btn)
	if rec["runs"] > 0:
		col.add_child(_label("En uzun tur %s  ·  En çok %d düşman  ·  %d zafer" % [Game.fmt_time(rec["best_time"]), rec["best_kills"], rec["wins"]], 20, Color(1, 0.85, 0.5)))
	start.grab_focus()

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

func show_levelup(choices: Array, chest: bool) -> void:
	cur_choices = choices
	lvl_layer.visible = true
	lvl_title.text = "Hazine!" if chest else "Seviye %d" % g.level
	for c in lvl_cards.get_children():
		c.queue_free()
	for i in choices.size():
		lvl_cards.add_child(_card(choices[i], i))
	lvl_layer.modulate.a = 0.0
	create_tween().tween_property(lvl_layer, "modulate:a", 1.0, 0.12)

func _card(c: Dictionary, i: int) -> Button:
	var id: String = c["id"]
	var is_w: bool = c["kind"] == "w"
	var d: Dictionary = Upgrades.WEAPONS[id] if is_w else Upgrades.PASSIVES[id]
	var cur: int = g.weapons.level(id) if is_w else g.passives.get(id, 0)
	var col: Color = d.get("color", TEAL)
	var b := Button.new()
	b.custom_minimum_size = Vector2(360, 150)
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
	var tag := _label(tag_txt, 18, Color(1, 0.9, 0.5) if cur == 0 or tag_txt == "  Uyanış" else Color(0.8, 0.8, 0.9))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tag)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	var key := _label(str(i + 1), 20, Color(1, 1, 1, 0.45))
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(key)
	var desc := _label(Upgrades.level_text(id, cur + 1), 19)
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
		var w: Dictionary = Upgrades.WEAPONS[id]
		parent.add_child(_row(w["icon"], w["name"], "Sv %d" % g.weapons.lv[id], w["color"]))
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
	end_layer = ColorRect.new()
	(end_layer as ColorRect).color = Color(0.05, 0.02, 0.08, 0.8)
	end_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(end_layer)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_layer.add_child(cc)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 22)
	cc.add_child(outer)
	var title := _label("Kül Devi yenildi!" if s["victory"] else "Fenerin söndü", 64, ACCENT if s["victory"] else Color(1.0, 0.5, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	outer.add_child(h)
	var left := _panel()
	left.custom_minimum_size = Vector2(460, 380)
	h.add_child(left)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	var rows := [
		["Süre", Game.fmt_time(s["time"])],
		["Yenilen düşman", str(s["kills"])],
		["Seviye", str(s["level"])],
		["Verilen hasar", _big(s["damage"])],
		["Alınan hasar", str(int(s["taken"]))],
		["Açılan sandık", str(s["chests"])],
		["Yakılan fener", "%d / 5" % s["shrines"]],
	]
	for r in rows:
		grid.add_child(_label(r[0], 24, Color(0.85, 0.8, 0.95)))
		var vl := _label(r[1], 26, Color.WHITE)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(vl)
	var right := _panel()
	right.custom_minimum_size = Vector2(380, 380)
	h.add_child(right)
	var bl := VBoxContainer.new()
	bl.add_theme_constant_override("separation", 8)
	right.add_child(bl)
	_build_list(bl)
	var best: Dictionary = s["best"]
	var line := ""
	if s["demo"]:
		line = "Demo turu, rekora yazılmadı"
	elif s["new_best"]:
		line = "Yeni rekor!"
	elif best["runs"] > 0:
		line = "Rekor %s  ·  %d düşman" % [Game.fmt_time(best["best_time"]), best["best_kills"]]
	if line != "":
		var rl := _label(line, 26, Color(1.0, 0.85, 0.4))
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(rl)
	var again := Button.new()
	again.text = "Bir tur daha  [R]"
	again.custom_minimum_size = Vector2(320, 64)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(func(): g.restart())
	outer.add_child(again)
	again.grab_focus()

func _big(v: float) -> String:
	if v >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if v >= 1000.0:
		return "%.1fB" % (v / 1000.0)
	return str(int(v))
