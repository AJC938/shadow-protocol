class_name LightSampler
extends RefCounted
## Approximates how lit a point is (0 dark .. 1 bright) from gameplay lights.
## Lights opt in by joining the "level_light" group. Line of sight to the light is
## checked so a wall between the player and a lamp keeps them in shadow.


static func sample(tree: SceneTree, point: Vector3, ambient: float) -> float:
	var total := ambient
	var space: PhysicsDirectSpaceState3D = null
	for n in tree.get_nodes_in_group("level_light"):
		var l := n as Light3D
		if l == null or not l.visible or l.light_energy <= 0.01:
			continue
		var lp := l.global_position
		var d := lp.distance_to(point)
		var rng := 0.0
		var contrib := 0.0
		if l is OmniLight3D:
			rng = (l as OmniLight3D).omni_range
			if d > rng:
				continue
			contrib = pow(1.0 - d / rng, 1.6)
		elif l is SpotLight3D:
			var sl := l as SpotLight3D
			rng = sl.spot_range
			if d > rng:
				continue
			var fwd := -sl.global_transform.basis.z
			var ang := rad_to_deg(fwd.angle_to((point - lp).normalized()))
			if ang > sl.spot_angle:
				continue
			contrib = pow(1.0 - d / rng, 1.3) * (1.0 - smoothstep(sl.spot_angle * 0.6, sl.spot_angle, ang))
		else:
			continue
		contrib *= clampf(l.light_energy / 2.0, 0.2, 1.5)
		if contrib < 0.03:
			continue
		if space == null:
			space = l.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(lp, point, 1 | 16)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.position.distance_to(point) > 0.5:
			continue
		total += contrib
	return clampf(total, 0.0, 1.0)
