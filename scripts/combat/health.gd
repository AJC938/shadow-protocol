class_name Health
extends Node
## Reusable health component. Owners forward hits through apply_damage().

signal damaged(info: DamageInfo, remaining: float)
signal healed(amount: float)
signal died(info: DamageInfo)

@export var max_health: float = 100.0
## Fraction of damage ignored (not applied to headshots).
@export_range(0.0, 0.9) var armor: float = 0.0
@export var regen_delay: float = 0.0
@export var regen_rate: float = 0.0

var current: float = 100.0
var invulnerable: bool = false
var _since_hit: float = 999.0


func _ready() -> void:
	current = max_health


func reset(full: float = -1.0) -> void:
	current = max_health if full < 0.0 else clampf(full, 1.0, max_health)
	_since_hit = 999.0


func is_dead() -> bool:
	return current <= 0.0


func ratio() -> float:
	return current / max_health if max_health > 0.0 else 0.0


func apply_damage(info: DamageInfo) -> float:
	if is_dead() or invulnerable or info.amount <= 0.0:
		return 0.0
	var amount := info.amount
	if not info.headshot:
		amount *= 1.0 - armor
	current = maxf(0.0, current - amount)
	_since_hit = 0.0
	damaged.emit(info, current)
	if current <= 0.0:
		died.emit(info)
	return amount


func heal(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return
	var before := current
	current = minf(max_health, current + amount)
	if current > before:
		healed.emit(current - before)


func _physics_process(delta: float) -> void:
	if is_dead() or regen_rate <= 0.0:
		return
	_since_hit += delta
	if _since_hit >= regen_delay and current < max_health:
		current = minf(max_health, current + regen_rate * delta)
