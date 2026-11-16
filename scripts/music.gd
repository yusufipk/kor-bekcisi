extends Node
## Music lives in an autoload so it starts on the title screen and keeps playing
## through pauses, level-ups, deaths and scene reloads. Tracks crossfade; there is
## never a silent gap. Per-track gain comes from measured integrated loudness
## (ffmpeg ebur128) so every track lands at TARGET_LUFS before the Music bus.
##
## Continuous sounds in the game: only this music. No ambient loops exist.

const TARGET_LUFS := -16.0
const MEASURED_LUFS := {"early": -14.3, "late": -12.2, "boss": -11.7}

var a: AudioStreamPlayer
var b: AudioStreamPlayer
var cur := ""
var tw: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	a = AudioStreamPlayer.new()
	b = AudioStreamPlayer.new()
	for p in [a, b]:
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)

func gain_db(id: String) -> float:
	return TARGET_LUFS - float(MEASURED_LUFS.get(id, TARGET_LUFS))

func play(id: String, fade := 2.0) -> void:
	if id == cur:
		return
	var path := "res://audio/music/%s.mp3" % id
	if not ResourceLoader.exists(path):
		return
	cur = id
	var s: AudioStreamMP3 = load(path)
	s.loop = true
	var out := a if a.playing else b
	var inn := b if out == a else a
	if tw and tw.is_valid():
		tw.kill()
	inn.stream = s
	inn.volume_db = gain_db(id) - 18.0
	inn.play()
	tw = create_tween().set_parallel(true)
	tw.tween_property(inn, "volume_db", gain_db(id), fade)
	if out.playing:
		tw.tween_property(out, "volume_db", -60.0, fade)
		tw.chain().tween_callback(out.stop)
