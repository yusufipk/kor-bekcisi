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
