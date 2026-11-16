extends Node
## Global settings and input map. Persisted to user://settings.cfg.

const PATH := "user://settings.cfg"

var mouse_sens := 1.0
var music_vol := 0.7
var sfx_vol := 0.8
var brightness := 1.0
var invert_y := false

signal changed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_setup_input()
	load_cfg()
	apply()

func _setup_buses() -> void:
	for n in ["Music", "SFX"]:
		if AudioServer.get_bus_index(n) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, n)
			AudioServer.set_bus_send(i, "Master")
	# Limiter only on SFX so loud fights never pull the music down with them.
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -3.0
		AudioServer.add_bus_effect(sfx, lim)

func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("slide", [KEY_SHIFT, KEY_CTRL])
	_key("pause", [KEY_ESCAPE, KEY_P])
	_key("pick_1", [KEY_1])
	_key("pick_2", [KEY_2])
	_key("pick_3", [KEY_3])
	_key("restart", [KEY_R])
	# Right mouse button also slides.
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("slide", mb)
	# Space is the jump key: it must never press a focused menu button, or a
	# player still jumping when they die skips the summary and starts a new run.
	for ev in InputMap.action_get_events("ui_accept"):
		if ev is InputEventKey and (ev.keycode == KEY_SPACE or ev.physical_keycode == KEY_SPACE):
			InputMap.action_erase_event("ui_accept", ev)

## Load a save file that may only hold plain values. ConfigFile.load would
## instantiate Object(...) and Resource(...) values while parsing, before any
## type check, so a shared save could construct objects or load scripts.
static func load_plain(c: ConfigFile, path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var text := FileAccess.get_file_as_string(path)
	# Allowlist, not a denylist: this game's saves hold only numbers, bools,
	# strings, arrays and dictionaries, none of which need "(". Every Variant
	# constructor does (Object, Resource, Vector3...), however it is spaced or
	# commented, so with the quoted strings removed any "(" rejects the file.
	var strings := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")
	if strings.sub(text, "", true).contains("("):
		push_warning("Ignoring save with non-plain values: " + path)
		return ERR_INVALID_DATA
	return c.parse(text)

static func _num(v, fallback: float, lo: float, hi: float) -> float:
	return clampf(float(v), lo, hi) if (v is int or v is float) and not is_nan(float(v)) else fallback

func load_cfg() -> void:
	var c := ConfigFile.new()
	if load_plain(c, PATH) != OK:
		return
	mouse_sens = _num(c.get_value("s", "mouse_sens", mouse_sens), mouse_sens, 0.2, 3.0)
	music_vol = _num(c.get_value("s", "music_vol", music_vol), music_vol, 0.0, 1.0)
	sfx_vol = _num(c.get_value("s", "sfx_vol", sfx_vol), sfx_vol, 0.0, 1.0)
	brightness = _num(c.get_value("s", "brightness", brightness), brightness, 0.6, 1.6)
	var inv = c.get_value("s", "invert_y", invert_y)
	invert_y = inv if inv is bool else false

func save_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("s", "mouse_sens", mouse_sens)
	c.set_value("s", "music_vol", music_vol)
	c.set_value("s", "sfx_vol", sfx_vol)
	c.set_value("s", "brightness", brightness)
	c.set_value("s", "invert_y", invert_y)
	c.save(PATH)

func apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_vol, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_vol, 0.0001)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_vol <= 0.001)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), sfx_vol <= 0.001)
	changed.emit()
