extends CharacterBody3D
## Fast third-person mover: run, jump (clears low enemies), slide (dash with i-frames).

const BASE_SPEED := 8.5
const ACCEL := 70.0
const AIR_ACCEL := 30.0
const JUMP_V := 10.5
const GRAVITY := 30.0
const SLIDE_SPEED := 21.0
const SLIDE_TIME := 0.38
const SLIDE_CD := 0.85

var hp := 120.0
var max_hp := 120.0
var invuln_t := 0.0
var slide_t := 0.0
var slide_cd := 0.0
var slide_dir := Vector3.FORWARD
var coyote := 0.0
var jump_buf := 0.0
var facing := 0.0
var was_on_floor := true
var air_jumps := 0
var dead := false
var cam_yaw := 0.0
var bot_input := Vector2.ZERO     # demo bot steering
var bot_jump := false
var bot_slide := false
var model: Node3D
var anim: AnimationPlayer
var anim_names := {}
var cur_anim := ""
var hurt_flash := 0.0
var move_input := Vector2.ZERO

func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	collision_layer = 1
	collision_mask = 2 | 4
	floor_snap_length = 0.3

func set_model(m: Node3D, a: AnimationPlayer, names: Dictionary) -> void:
	model = m
	anim = a
	anim_names = names
	add_child(m)

func _speed() -> float:
	return BASE_SPEED * Game.inst.st.speed

func _physics_process(dt: float) -> void:
	if dead:
		velocity.x = move_toward(velocity.x, 0, 30 * dt)
		velocity.z = move_toward(velocity.z, 0, 30 * dt)
		velocity.y -= GRAVITY * dt
		move_and_slide()
		return
	var g = Game.inst
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if g.demo:
		inp = bot_input
	move_input = inp
	var basis_y := Basis(Vector3.UP, cam_yaw)
	var wish := basis_y * Vector3(inp.x, 0, inp.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	invuln_t -= dt
	slide_cd -= dt
	hurt_flash = maxf(0.0, hurt_flash - dt * 3.0)
	var on_floor := is_on_floor()
	if on_floor:
		coyote = 0.12
		air_jumps = g.st.air_jumps
	else:
		coyote -= dt
	if Input.is_action_just_pressed("jump") or (g.demo and bot_jump):
		jump_buf = 0.14
	bot_jump = false
	jump_buf -= dt
	if jump_buf > 0.0:
		if coyote > 0.0:
			velocity.y = JUMP_V
			coyote = 0.0
			jump_buf = 0.0
			Sfx.play("jump", global_position, 0.6)
			g.fx.dust(global_position, 6)
		elif air_jumps > 0:
			velocity.y = JUMP_V * 0.9
			air_jumps -= 1
			jump_buf = 0.0
			Sfx.play("jump", global_position, 0.6)
			g.fx.burst(global_position + Vector3(0, 0.3, 0), Color(0.6, 1.0, 0.95), 8, 0.8)
	var want_slide = Input.is_action_just_pressed("slide") or (g.demo and bot_slide)
	bot_slide = false
	if want_slide and slide_cd <= 0.0 and slide_t <= 0.0:
		slide_t = SLIDE_TIME
		slide_cd = SLIDE_CD * g.st.slide_cd
		slide_dir = wish.normalized() if wish.length() > 0.1 else Vector3(sin(facing), 0, cos(facing))
		Sfx.play("slide", global_position, 0.7)
		g.fx.dust(global_position, 10)
		g.on_slide(global_position, slide_dir)
	var hv := Vector3(velocity.x, 0, velocity.z)
	if slide_t > 0.0:
		slide_t -= dt
		var k := slide_t / SLIDE_TIME
		hv = slide_dir * lerpf(_speed() * 1.1, SLIDE_SPEED * g.st.speed, k)
		if Engine.get_physics_frames() % 3 == 0:
			g.fx.dust(global_position, 2)
	else:
		var target := wish * _speed()
		var a := ACCEL if on_floor else AIR_ACCEL
		hv = hv.move_toward(target, a * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y -= GRAVITY * dt
	if not on_floor and velocity.y < 0.0:
		velocity.y -= GRAVITY * 0.35 * dt   # snappier fall
	move_and_slide()
	# Island edge: soft wall
	var flat := Vector2(global_position.x, global_position.z)
	var lim: float = g.world.island_radius - 1.5
	if flat.length() > lim:
		flat = flat.normalized() * lim
		global_position.x = flat.x
		global_position.z = flat.y
	if global_position.y < -5.0:
		global_position = Vector3(0, 2, 0)
		velocity = Vector3.ZERO
	if is_on_floor() and not was_on_floor:
		g.fx.dust(global_position, 5)
		if model:
			model.scale = Vector3(1.15, 0.85, 1.15) * model.get_meta("base_scale", 1.0)
	was_on_floor = is_on_floor()
	if hv.length() > 0.5:
		facing = lerp_angle(facing, atan2(hv.x, hv.z), minf(1.0, dt * 14.0))
	if model:
		model.rotation.y = facing
		var bs: float = model.get_meta("base_scale", 1.0)
		model.scale = model.scale.lerp(Vector3.ONE * bs, minf(1.0, dt * 10.0))
		# Blink while invulnerable after a hit
		model.visible = not (invuln_t > 0.0 and slide_t <= 0.0 and int(invuln_t * 20.0) % 2 == 0)
	_update_anim(hv.length(), is_on_floor())
	if g.st.regen > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + g.st.regen * dt)

func _update_anim(spd: float, on_floor: bool) -> void:
	if anim == null:
		return
	var want := "idle"
	if slide_t > 0.0 and anim_names.has("slide"):
		want = "slide"
	elif not on_floor and anim_names.has("jump"):
		want = "jump"
	elif spd > 1.0:
		want = "run"
	if not anim_names.has(want):
		want = "run"
	if want != cur_anim:
		cur_anim = want
		anim.play(anim_names[want], 0.1)
		# Skip the clips' wind-up: jump starts at take-off, slide at the low pose.
		if want == "jump":
			anim.seek(0.5, true)
		elif want == "slide":
			anim.seek(0.4, true)
	if want == "run":
		anim.speed_scale = clampf(spd / 8.5, 0.6, 1.6)
	else:
		anim.speed_scale = 1.0

func is_invulnerable() -> bool:
	return invuln_t > 0.0 or slide_t > 0.0 or dead

func hurt(dmg: float, from: Vector3) -> void:
	if is_invulnerable():
		return
	var g = Game.inst
	if g.state != Game.S_PLAY or g.won:
		return
	hp -= dmg * g.st.armor
	invuln_t = 0.7
	hurt_flash = 1.0
	g.stats_damage_taken += dmg * g.st.armor
	if g.demo:
		print("HURT t=%.0f dmg=%.0f hp=%.0f" % [g.t, dmg * g.st.armor, hp])
	var away := (global_position - from)
	away.y = 0
	if away.length() > 0.01:
		velocity += away.normalized() * 6.0
	g.shake(0.35)
	Sfx.play("hurt", global_position, 0.9)
	g.fx.burst(global_position + Vector3(0, 1, 0), Color(1, 0.3, 0.3), 10, 1.0)
	if g.demo and g.demo_cfg.get("god", false):
		hp = maxf(hp, 1.0)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		g.on_player_died()

func heal(v: float) -> void:
	hp = minf(max_hp, hp + v)
