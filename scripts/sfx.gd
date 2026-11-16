extends Node
## Sound effects with a voice pool and per-sound rate limiting, so a hundred hits
## in one frame do not turn into noise. Generated files load from res://audio/sfx;
## a few short sounds are synthesized here.
##
## Continuous sounds in the game (keep this list current):
##   - music (Music autoload, Music bus): one track at a time, crossfaded, never stops
## There is no ambient loop and no looping effect.

const VOICES := 24
var players: Array = []
var streams := {}
var last_play := {}
var min_gap := {"hit": 0.035, "kill": 0.04, "pickup": 0.045, "shoot": 0.06, "zap": 0.08, "nova": 0.1, "meteor": 0.08, "whoosh": 0.12, "hurt": 0.15, "explode": 0.06, "charge": 0.2}
# Files in audio/sfx measure about -17 LUFS (pickup.ogg -24.9; ffmpeg ebur128);
# music plays at -16 LUFS before the bus. These offsets keep frequent sounds
# under the music, put the pickup blip about 8 dB below it (it was 16 dB below
# and got lost) and the boss roar about 3 dB above it.
var base_db := {"hit": -14.0, "kill": -12.0, "pickup": 1.5, "shoot": -20.0, "zap": -12.0, "nova": -9.0, "meteor": -9.0, "whoosh": -18.0, "hurt": -4.0, "levelup": -6.0, "chest": -4.0, "roar": 3.0, "slam": -4.0, "jump": -18.0, "slide": -14.0, "shrine": -6.0, "select": -12.0, "ui": -16.0, "evolve": -3.0, "explode": -8.0, "charge": -8.0, "crystal": -7.0, "serpent": -1.0, "quake": 0.0}
var voice_i := 0
var listener_pos := Vector3.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	for n in ["hit", "kill", "pickup", "levelup", "hurt", "chest", "roar", "slam", "meteor", "zap", "nova", "evolve", "explode", "charge", "crystal", "serpent", "quake"]:
		var path := "res://audio/sfx/%s.ogg" % n
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	streams["shoot"] = _synth_shoot()
	streams["jump"] = _synth_sweep(320.0, 760.0, 0.12, 0.35)
	streams["whoosh"] = _synth_noise_whoosh(0.28)
	if not streams.has("slide"):
		streams["slide"] = _synth_noise_whoosh(0.32)
	streams["select"] = _synth_sweep(500.0, 1000.0, 0.09, 0.4)
	streams["ui"] = _synth_sweep(700.0, 700.0, 0.04, 0.3)
	streams["shrine"] = _synth_chord()
	if not streams.has("levelup"):
		streams["levelup"] = _synth_chord()
	if not streams.has("evolve"):
		streams["evolve"] = _synth_evolve()
	if not streams.has("crystal"):
		streams["crystal"] = _synth_crystal()
	for k in ["hit", "kill", "pickup", "levelup", "hurt", "chest", "roar", "slam", "meteor", "zap", "nova", "explode", "charge", "crystal", "serpent", "quake"]:
		if not streams.has(k):
			streams[k] = _synth_sweep(400.0, 200.0, 0.1, 0.4)

func play(name: String, pos: Vector3 = Vector3.INF, vol := 1.0, pitch_var := 0.12, pitch := 1.0) -> void:
	var s = streams.get(name)
	if s == null:
		return
	var now := Time.get_ticks_msec() * 0.001
	var gap: float = min_gap.get(name, 0.0)
	if gap > 0.0 and now - last_play.get(name, -1.0) < gap:
		return
	last_play[name] = now
	var db: float = base_db.get(name, -8.0) + linear_to_db(maxf(vol, 0.01))
	if pos != Vector3.INF:
		var d := pos.distance_to(listener_pos)
		db -= clampf((d - 8.0) * 0.5, 0.0, 14.0)
	var p: AudioStreamPlayer = players[voice_i]
	voice_i = (voice_i + 1) % VOICES
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch * randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()

func _wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 44100
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	w.data = bytes
	return w

func _synth_shoot() -> AudioStreamWAV:
	var n := int(44100 * 0.09)
	var d := PackedFloat32Array()
	d.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(1400.0, 380.0, t)
		ph += f / 44100.0
		d[i] = (sin(ph * TAU) * 0.5 + randf_range(-0.25, 0.25) * (1.0 - t)) * pow(1.0 - t, 2.0) * 0.6
	return _wav(d)

func _synth_sweep(f0: float, f1: float, dur: float, amp: float) -> AudioStreamWAV:
	var n := int(44100 * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += lerpf(f0, f1, t) / 44100.0
		d[i] = sin(ph * TAU) * amp * (1.0 - t) * minf(1.0, t * 40.0)
	return _wav(d)

func _synth_noise_whoosh(dur: float) -> AudioStreamWAV:
	var n := int(44100 * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		var cut := 0.04 + 0.25 * sin(t * PI)
		lp += (randf_range(-1, 1) - lp) * cut
		d[i] = lp * sin(t * PI) * 1.4
	return _wav(d)

func _synth_chord() -> AudioStreamWAV:
	var n := int(44100 * 1.1)
	var d := PackedFloat32Array()
	d.resize(n)
	var fr := [523.25, 659.25, 783.99, 1046.5]
	for i in n:
		var t := float(i) / 44100.0
		var v := 0.0
		for k in fr.size():
			var on := clampf((t - k * 0.06) * 30.0, 0.0, 1.0)
			v += sin(t * fr[k] * TAU) * on
		d[i] = v * 0.12 * exp(-t * 2.5)
	return _wav(d)

## Rising sweep into a bright major chord: the evolution fanfare.
func _synth_evolve() -> AudioStreamWAV:
	var n := int(44100 * 1.8)
	var d := PackedFloat32Array()
	d.resize(n)
	var ph := 0.0
	var fr := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for i in n:
		var t := float(i) / 44100.0
		var v := 0.0
		if t < 0.5:
			ph += lerpf(200.0, 1046.5, t / 0.5) / 44100.0
			v += sin(ph * TAU) * 0.35 * (t / 0.5)
		else:
			var k := t - 0.5
			for j in fr.size():
				var on := clampf((k - j * 0.04) * 40.0, 0.0, 1.0)
				v += sin(t * fr[j] * TAU) * on * 0.16 + sin(t * fr[j] * 2.0 * TAU) * on * 0.04
			v *= exp(-k * 1.8)
		d[i] = v
	return _wav(d)

## Glassy pings with a little noise: a crystal breaking.
func _synth_crystal() -> AudioStreamWAV:
	var n := int(44100 * 0.7)
	var d := PackedFloat32Array()
	d.resize(n)
	var pings := [[0.0, 2349.0], [0.03, 3136.0], [0.07, 2637.0], [0.12, 3951.0], [0.18, 2093.0]]
	for i in n:
		var t := float(i) / 44100.0
		var v := randf_range(-1.0, 1.0) * 0.25 * exp(-t * 30.0)
		for p in pings:
			if t >= p[0]:
				var k: float = t - p[0]
				v += sin(k * p[1] * TAU) * 0.2 * exp(-k * 9.0)
		d[i] = v
	return _wav(d)
