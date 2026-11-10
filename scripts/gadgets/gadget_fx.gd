class_name GadgetFX
extends RefCounted
## Expanding pulse shell used by the disruptor and scanner.


static func pulse(owner: Node, pos: Vector3, radius: float, color: Color) -> void:
	var root: Node = owner.get_tree().current_scene if owner.get_tree().current_scene else owner
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 32
	s.rings = 16
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	m.rim_enabled = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.3
	var t := mi.create_tween().set_parallel(true)
	t.tween_property(mi, "scale", Vector3.ONE * radius, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(m, "albedo_color:a", 0.0, 0.7)
	t.chain().tween_callback(mi.queue_free)
