extends Node
## Boot scene: applies settings, then routes to the main menu or an automation task
## (used by tests / capture tooling via --sp-* user arguments).


func _ready() -> void:
	await get_tree().process_frame
	if Game.automation.has("capture"):
		var tool: Node = preload("res://scripts/core/capture_tool.gd").new()
		tool.name = "CaptureTool"
		Game.add_child(tool)
	if Game.automation.has("mission"):
		var id := str(Game.automation["mission"])
		var cp := {}
		Game.deploy(id, cp)
		return
	if Game.automation.has("briefing"):
		Game.open_briefing(str(Game.automation["briefing"]))
		return
	if Game.automation.has("results_preview"):
		# Dev-only: renders the results screen with sample numbers for visual QA.
		Game.last_results = {"mission_id": "m01", "title": "Silent Entry", "time": 734.0, "kills": 2, "headshots": 1,
			"detections": 1, "alarms": 0, "deaths": 1, "accuracy": 0.62, "gadget_uses": 5, "optional_done": 2, "optional_total": 3,
			"objectives": [{"text": "Reach the facility perimeter", "optional": false, "done": true, "failed": false},
				{"text": "Pass the checkpoint undetected", "optional": true, "done": false, "failed": true}],
			"intel": 2, "score": 1280, "grade": "B", "style": "Tactical"}
		Game.change_scene(Game.RESULTS)
		return
	if Game.automation.has("scene"):
		Game.change_scene(str(Game.automation["scene"]))
		return
	Game.goto_main_menu()
