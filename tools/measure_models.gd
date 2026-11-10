extends SceneTree
## Prints the bounding box of every Poly Haven model (metres, unscaled).

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	var d := DirAccess.open("res://assets/models/polyhaven")
	for id in d.get_directories():
		var p := "res://assets/models/polyhaven/%s/%s_1k.gltf" % [id, id]
		if not ResourceLoader.exists(p):
			print(id, " MISSING")
			continue
		var n := (load(p) as PackedScene).instantiate() as Node3D
		root.add_child(n)
		var bb := AABB()
		var first := true
		for c in n.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			var b := mi.global_transform * mi.get_aabb()
			bb = b if first else bb.merge(b)
			first = false
		print("%-28s size=(%.2f, %.2f, %.2f) pos=(%.2f, %.2f, %.2f)" % [id, bb.size.x, bb.size.y, bb.size.z, bb.position.x, bb.position.y, bb.position.z])
		n.queue_free()
	quit()
