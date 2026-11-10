class_name SoundEvent
extends RefCounted
## A single perceivable sound: position, intensity, perception radius and type.

enum Type { FOOTSTEP, SPRINT, GUNSHOT, SUPPRESSED_SHOT, IMPACT, DOOR, ALARM, DISTRACTION, BODY_FALL, GADGET, ENEMY_GUNSHOT, VOICE }

## Suspicion added (at full loudness) by each event type. Tuned in GDD §8.
const SUSPICION_WEIGHT := {
	Type.FOOTSTEP: 18.0,
	Type.SPRINT: 30.0,
	Type.GUNSHOT: 100.0,
	Type.SUPPRESSED_SHOT: 45.0,
	Type.IMPACT: 35.0,
	Type.DOOR: 25.0,
	Type.ALARM: 100.0,
	Type.DISTRACTION: 40.0,
	Type.BODY_FALL: 45.0,
	Type.GADGET: 20.0,
	Type.ENEMY_GUNSHOT: 100.0,
	Type.VOICE: 30.0,
}

var position: Vector3
var radius: float = 5.0
var type: int = Type.FOOTSTEP
var intensity: float = 1.0
var source: Node
var time: float = 0.0


func is_combat_sound() -> bool:
	return type in [Type.GUNSHOT, Type.ENEMY_GUNSHOT, Type.ALARM]


static func type_name(t: int) -> String:
	return Type.keys()[t] if t >= 0 and t < Type.size() else "UNKNOWN"
