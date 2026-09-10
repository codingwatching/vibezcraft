extends GutTest
# PerfWatchdog — the sustained-low-fps line that gives a "random extreme
# lag" report (issue #7) something to act on.

var _calls: int = 0


func before_each() -> void:
	PerfWatchdog.reset()
	DebugLog.reset()
	_calls = 0


func _stats() -> String:
	_calls += 1
	return "chunks=1"


func _run(seconds: float, fps: float) -> int:
	var reports: int = 0
	var dt: float = 1.0 / 60.0
	for _i: int in range(int(seconds / dt)):
		if PerfWatchdog.tick(dt, fps, _stats):
			reports += 1
	return reports


func test_a_healthy_frame_rate_never_reports() -> void:
	assert_eq(_run(10.0, 60.0), 0)
	assert_eq(_calls, 0, "stats are not even gathered")


func test_a_brief_dip_is_ignored() -> void:
	assert_eq(_run(1.0, 8.0), 0, "under the sustain window")
	assert_eq(_run(5.0, 60.0), 0, "and it recovered")


func test_a_sustained_slowdown_reports_once_and_rearms_later() -> void:
	assert_eq(_run(3.0, 9.0), 1, "one report after the sustain window")
	assert_eq(_run(20.0, 9.0), 0, "quiet during the rearm cooldown")
	assert_eq(_run(12.0, 9.0), 1, "one more once the cooldown lapses and it is still slow")
	assert_eq(_calls, 2, "stats gathered only when a report fires")


func test_the_report_lands_in_the_debug_log_with_the_counts() -> void:
	_run(3.0, 9.0)
	var dump: String = DebugLog.dump()
	assert_true(dump.contains("[PERF]"), "PERF category")
	assert_true(dump.contains("9 fps"), "the frame rate")
	assert_true(dump.contains("chunks=1"), "the injected counts")
	assert_true(dump.contains("slowest:"), "the probe summary")
