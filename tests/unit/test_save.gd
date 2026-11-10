extends TestCase
## Unit tests: versioned save system, validation, progression, checkpoints.


func before_each() -> void:
	SaveSystem.delete_save()


func _write_raw(text: String) -> void:
	var f := FileAccess.open(SaveSystem.save_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_missing_file_gives_defaults() -> void:
	eq(SaveSystem.load_game(), "missing", "SAV-01 status")
	check(not SaveSystem.has_progress(), "SAV-01 no progress")
	check(SaveSystem.is_unlocked("m01") and not SaveSystem.is_unlocked("m02"), "SAV-01 only m01 unlocked")


func test_roundtrip_and_unlock_progression() -> void:
	SaveSystem.new_campaign()
	SaveSystem.record_mission_complete("m01", "A", 400.0, 1400, 2, 3, 1)
	SaveSystem.load_game()
	eq(SaveSystem.last_load_status, "ok", "SAV-02 reload ok")
	check(SaveSystem.is_completed("m01"), "SAV-02 m01 completed")
	check(SaveSystem.is_unlocked("m02"), "SAV-02 m02 unlocked")
	eq(SaveSystem.get_current_mission(), "m02", "SAV-02 current advanced")
	eq(SaveSystem.get_record("m01")["grade"], "A", "SAV-02 grade stored")


func test_best_record_kept() -> void:
	SaveSystem.new_campaign()
	SaveSystem.record_mission_complete("m01", "S", 300.0, 1800, 3, 0, 0)
	SaveSystem.record_mission_complete("m01", "C", 900.0, 700, 0, 9, 4)
	var r := SaveSystem.get_record("m01")
	eq(r["grade"], "S", "SAV-03 best grade kept")
	near(float(r["best_time"]), 300.0, 0.01, "SAV-03 best time kept")
	eq(int(r["score"]), 1800, "SAV-03 best score kept")


func test_campaign_complete_flag() -> void:
	SaveSystem.new_campaign()
	for id in ["m01", "m02", "m03"]:
		SaveSystem.record_mission_complete(id, "B", 500.0, 1000, 0, 0, 0)
	check(SaveSystem.is_campaign_complete(), "SAV-04 campaign complete")
	SaveSystem.load_game()
	check(SaveSystem.is_campaign_complete(), "SAV-04 survives reload")


func test_corrupted_file() -> void:
	_write_raw("{ this is not json")
	eq(SaveSystem.load_game(), "corrupt", "SAV-05 corrupt detected")
	check(not SaveSystem.has_progress(), "SAV-05 defaults used")
	check(FileAccess.file_exists(SaveSystem.save_path + ".corrupt.bak"), "SAV-05 backup written")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.save_path + ".corrupt.bak"))


func test_unsupported_version() -> void:
	_write_raw(JSON.stringify({"version": 99, "campaign": {"started": true}}))
	eq(SaveSystem.load_game(), "unsupported_version", "SAV-06 newer version rejected")
	check(not SaveSystem.has_progress(), "SAV-06 defaults used")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.save_path + ".unsupported.bak"))


func test_invalid_references_repaired() -> void:
	_write_raw(JSON.stringify({"version": 2, "campaign": {"started": true, "unlocked": ["m01", "m99", 5],
		"completed": {"m01": {"grade": "Z", "best_time": -5, "score": 10}, "bogus": {}},
		"current": "m42"}, "checkpoint": {"mission": "m77", "state": {}}}))
	eq(SaveSystem.load_game(), "repaired", "SAV-07 repaired status")
	check(not SaveSystem.is_unlocked("m99"), "SAV-07 unknown mission removed")
	check(SaveSystem.is_unlocked("m02"), "SAV-07 successor of completed mission unlocked")
	eq(SaveSystem.get_record("m01")["grade"], "D", "SAV-07 invalid grade sanitised")
	check(float(SaveSystem.get_record("m01")["best_time"]) >= 0.0, "SAV-07 negative time clamped")
	check(Campaign.is_valid(SaveSystem.get_current_mission()), "SAV-07 current mission valid")
	check(not SaveSystem.has_checkpoint(), "SAV-07 invalid checkpoint dropped")


func test_v1_migration() -> void:
	_write_raw(JSON.stringify({"version": 1, "unlocked": ["m01", "m02"], "completed": ["m01"]}))
	SaveSystem.load_game()
	check(SaveSystem.is_completed("m01") and SaveSystem.is_unlocked("m02"), "SAV-08 v1 data migrated")


func test_checkpoint_does_not_touch_progress() -> void:
	SaveSystem.new_campaign()
	SaveSystem.store_checkpoint("m01", {"elapsed": 12.0, "player": {"pos": [1, 2, 3]}})
	check(SaveSystem.has_checkpoint(), "SAV-09 checkpoint stored")
	check(not SaveSystem.is_completed("m01"), "SAV-09 progress unchanged by checkpoint")
	SaveSystem.load_game()
	eq(str(SaveSystem.get_checkpoint()["mission"]), "m01", "SAV-09 checkpoint survives reload")
	SaveSystem.store_checkpoint("m03", {})
	eq(str(SaveSystem.get_checkpoint()["mission"]), "m01", "SAV-09 locked mission checkpoint refused")
	SaveSystem.record_mission_complete("m01", "B", 100, 1000, 0, 0, 0)
	check(not SaveSystem.has_checkpoint(), "SAV-09 completion clears checkpoint")


func test_atomic_save_creates_file() -> void:
	SaveSystem.new_campaign()
	check(FileAccess.file_exists(SaveSystem.save_path), "SAV-10 save file exists")
	check(not FileAccess.file_exists(SaveSystem.save_path + ".tmp"), "SAV-10 temp file cleaned")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.save_path))
	eq(int(parsed["version"]), SaveSystem.VERSION, "SAV-10 version field written")
