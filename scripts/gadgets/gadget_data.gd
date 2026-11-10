class_name GadgetData
extends Resource
## Configurable gadget definition.

enum Kind { RECON_CAMERA, SIGNAL_DISRUPTOR, TACTICAL_SCANNER }

@export var id: StringName = &"scanner"
@export var display_name: String = "Gadget"
@export var kind: Kind = Kind.TACTICAL_SCANNER
@export_multiline var description: String = ""
@export var cooldown: float = 15.0
## Effect duration in seconds (0 = instant / manual).
@export var duration: float = 6.0
## Effect / deployment range in metres.
@export var range: float = 20.0
## Uses per mission (-1 = unlimited, limited by cooldown only).
@export var charges: int = -1
@export var noise_radius: float = 3.0
