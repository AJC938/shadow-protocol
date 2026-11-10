extends Node
## Headless test runner scene.
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn [-- --filter=name]
## Discovers tests/unit/*.gd and tests/integration/*.gd (classes extending TestCase),
## runs every test_* method (they may await), prints results and writes
## tests/output/test_results.json. Exit code = number of failures.

const DIRS := ["res://tests/unit", "res://tests/integration"]

var results: Array = []


func _ready() -> void:
	# Watchdog: never leave a hung engine process behind.
	get_tree().create_timer(1200.0, true, false, true).timeout.connect(func():
		push_error("test watchdog timeout")
		get_tree().quit(98))
	_run.call_deferred()


## Mission tests change scenes; detach the runner from current_scene so it survives.
func _detach() -> void:
	var dummy := Node.new()
	dummy.name = "TestScene"
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy


func _run() -> void:
	# Let autoloads finish their _ready.
	_detach()
	await get_tree().process_frame
	await get_tree().process_frame
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	# Tests must not touch the player's real save/settings.
	var save_system: Node = get_tree().root.get_node_or_null("SaveSystem")
	if save_system == null:
		push_error("autoloads missing")
		get_tree().quit(99)
		return
	save_system.set("save_path", "user://test_savegame.json")
	save_system.call("delete_save")
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for dir in DIRS:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var files := Array(d.get_files())
		files.sort()
		for f in files:
			if not f.ends_with(".gd"):
				continue
			var script: GDScript = load(dir.path_join(f))
			var case: TestCase = script.new()
			case.tree = get_tree()
			var methods := []
			for m in script.get_script_method_list():
				if String(m["name"]).begins_with("test_"):
					methods.append(String(m["name"]))
			for m in methods:
				var full := "%s::%s" % [f.get_basename(), m]
				if filter != "" and not full.contains(filter):
					continue
				total += 1
				case.reset()
				var ts := Time.get_ticks_msec()
				await case.before_each()
				await case.call(m)
				await case.after_each()
				var ok := case.failures.is_empty()
				if not ok:
					failed += 1
				var ms := Time.get_ticks_msec() - ts
				results.append({"id": full, "passed": ok, "failures": case.failures.duplicate(), "notes": case.notes.duplicate(), "ms": ms})
				print("%s  %s  (%d ms)%s" % ["PASS" if ok else "FAIL", full, ms, "" if ok else "\n      " + "\n      ".join(case.failures)])
			case.free_case()
	print("\n%d tests, %d failed, %.1f s" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var f := FileAccess.open("res://tests/output/test_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"total": total, "failed": failed, "results": results}, "\t"))
		f.close()
	save_system.call("delete_save")
	get_tree().quit(failed)
