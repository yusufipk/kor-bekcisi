class_name Models
extends RefCounted
## Loads generated GLBs and normalises them: measured from the mesh bounds,
## scaled to a target height, centred on x/z, base on y = 0.

static func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)

static func _bounds(root: Node3D) -> AABB:
	var list: Array = []
	_meshes(root, list)
	var first := true
	var box := AABB()
	for mi in list:
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else _rel_xf(root, mi)
		var b: AABB = xf * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box

static func _rel_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

## Static prop as a node, normalised to `height` metres.
static func prop(path: String, height: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scn: PackedScene = load(path)
	var inst: Node3D = scn.instantiate()
	var holder := Node3D.new()
	holder.add_child(inst)
	var box := _bounds(inst)
	var s := height / maxf(box.size.y, 0.001)
	inst.scale = Vector3.ONE * s
	var c := box.get_center()
	inst.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	return holder

## Single merged mesh (for MultiMesh) with transforms and normalisation baked in.
## Returns [ArrayMesh, Texture2D or null, footprint radius] or [] if missing.
static func merged_mesh(path: String, height: float, yaw := 0.0) -> Array:
	if not ResourceLoader.exists(path):
		return []
	var scn: PackedScene = load(path)
	var inst: Node3D = scn.instantiate()
	var box := _bounds(inst)
	var s := height / maxf(box.size.y, 0.001)
	var c := box.get_center()
	var norm := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3.ZERO) * Transform3D(Basis(), Vector3(-c.x, -box.position.y, -c.z))
	var list: Array = []
	_meshes(inst, list)
	var st := SurfaceTool.new()
	var tex: Texture2D = null
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mi in list:
		var mesh: Mesh = mi.mesh
		var xf := norm * _rel_xf(inst, mi)
		for si in mesh.get_surface_count():
			st.append_from(mesh, si, xf)
			if tex == null:
				var mat = mi.get_active_material(si)
				if mat is BaseMaterial3D and mat.albedo_texture:
					tex = mat.albedo_texture
	var out := st.commit()
	inst.free()
	var r := maxf(box.size.x, box.size.z) * s * 0.5
	return [out, tex, r]

## Hero model with every clip merged into one AnimationPlayer.
## Returns [Node3D or null, AnimationPlayer or null, {state: anim name}].
static func hero() -> Array:
	var path := "res://art/models/kahraman.glb"
	if not ResourceLoader.exists(path):
		return [null, null, {}]
	var model := prop(path, 1.75)
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var names := {}
	if anim == null:
		return [model, null, names]
	var lib: AnimationLibrary = anim.get_animation_library("")
	for a in anim.get_animation_list():
		names["run"] = a
		anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	for extra in [["idle", "kahraman_bekleme"], ["jump", "kahraman_zipla"], ["slide", "kahraman_kayma"]]:
		var p2 := "res://art/models/%s.glb" % extra[1]
		if not ResourceLoader.exists(p2):
			continue
		var tmp: Node = load(p2).instantiate()
		var ap: AnimationPlayer = tmp.find_child("AnimationPlayer", true, false)
		if ap and ap.get_animation_list().size() > 0:
			var src: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
			src.loop_mode = Animation.LOOP_LINEAR if extra[0] == "idle" else Animation.LOOP_NONE
			lib.add_animation(extra[0], src)
			names[extra[0]] = extra[0]
		tmp.free()
	for k in names.keys():
		# The jump clip lifts the hips itself; physics already does that.
		strip_root_motion(anim.get_animation(names[k]), k == "jump")
	return [model, anim, names]

## Keep the hero in place: clips with hip translation fight the controller.
static func strip_root_motion(a: Animation, lock_y := false) -> void:
	if a == null:
		return
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path := str(a.track_get_path(i))
		if not path.contains("Hips"):
			continue
		var n := a.track_get_key_count(i)
		if n == 0:
			continue
		var first: Vector3 = a.track_get_key_value(i, 0)
		for k in n:
			var v: Vector3 = a.track_get_key_value(i, k)
			a.track_set_key_value(i, k, Vector3(first.x, first.y if lock_y else v.y, first.z))

## Skinned GLBs carry a 0.01 armature scale that mesh bounds do not see, so
## measure the rest skeleton in world space and rescale to the wanted height.
## The model must be inside the tree.
static func fit_skinned(model: Node3D, height: float) -> void:
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	if sk == null or model.get_child_count() == 0:
		return
	var inner: Node3D = model.get_child(0)
	var lo := INF
	var hi := -INF
	for b in sk.get_bone_count():
		var p: Vector3 = sk.global_transform * sk.get_bone_global_rest(b).origin
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var span := hi - lo
	if span <= 0.0001:
		return
	# Bones stop at the head joint; the top of the head sits about 8 % higher.
	inner.scale *= height / (span * 1.08)
	var foot := INF
	for b in sk.get_bone_count():
		foot = minf(foot, (sk.global_transform * sk.get_bone_global_rest(b).origin).y)
	inner.position.y -= foot - model.global_position.y
