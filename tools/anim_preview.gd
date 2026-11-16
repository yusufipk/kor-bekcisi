extends Node3D
## Dev-only: four heroes side by side, one clip each, under bright light,
## to check that every clip sits on the same skeleton.

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.75, 0.8, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 10)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var shots := [["jump", 0.3], ["jump", 0.55], ["jump", 0.8], ["jump", 1.1], ["slide", 0.2], ["slide", 0.45], ["slide", 0.75], ["slide", 1.05]]
	for i in shots.size():
		var h := Models.hero()
		var model: Node3D = h[0]
		model.position = Vector3(-6.3 + i * 1.8, 0, 0)
		add_child(model)
		Models.fit_skinned(model, 1.75)
		var anim: AnimationPlayer = h[1]
		var names: Dictionary = h[2]
		anim.play(names[shots[i][0]])
		anim.seek(shots[i][1], true)
		anim.pause()
		var l := Label3D.new()
		l.text = "%s %.2f" % shots[i]
		l.font_size = 40
		l.position = model.position + Vector3(0, 2.3, 0)
		add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 8.0)
	cam.fov = 60.0
	cam.rotation_degrees = Vector3(-8, 0, 0)
	add_child(cam)
