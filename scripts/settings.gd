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

func load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	mouse_sens = c.get_value("s", "mouse_sens", mouse_sens)
	music_vol = c.get_value("s", "music_vol", music_vol)
	sfx_vol = c.get_value("s", "sfx_vol", sfx_vol)
	brightness = c.get_value("s", "brightness", brightness)
	invert_y = c.get_value("s", "invert_y", invert_y)

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
