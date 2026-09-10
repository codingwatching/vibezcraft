class_name PerfWatchdog
extends RefCounted

# Sustained-slowdown reporter for field bug reports.
#
# Issue #7 carried "random extreme lag 13 minutes into gameplay, 5-10 fps
# for a few minutes" and nothing else — the log records no frame timing,
# so the report could not be acted on. This watches the frame rate and,
# once it has stayed under LOW_FPS for SUSTAIN_SEC, writes ONE line into
# DebugLog (mirrored to stdout, so it lands in user://logs/godot.log)
# with the counts most likely to explain a slowdown plus the slowest
# PerfProbe rings. It re-arms after REARM_SEC so a multi-minute episode
# leaves a sparse trail rather than a wall of text.
#
# The report line is exactly what to paste into a bug report; the F3
# panel's "Copy Stats" includes the DebugLog tail.

const LOW_FPS: float = 15.0
const SUSTAIN_SEC: float = 2.0
const REARM_SEC: float = 30.0
const TOP_PROBES: int = 5

static var _below_sec: float = 0.0
static var _cooldown_sec: float = 0.0


static func reset() -> void:
	_below_sec = 0.0
	_cooldown_sec = 0.0


# Call once per rendered frame. `stats` is invoked lazily — only when a
# report actually fires — and returns the counts to log. Returns true on
# the frame a report was written.
static func tick(delta: float, fps: float, stats: Callable) -> bool:
	if _cooldown_sec > 0.0:
		_cooldown_sec = maxf(0.0, _cooldown_sec - delta)
	if fps >= LOW_FPS:
		_below_sec = 0.0
		return false
	_below_sec += delta
	if _below_sec < SUSTAIN_SEC or _cooldown_sec > 0.0:
		return false
	_cooldown_sec = REARM_SEC
	DebugLog.add(
		DebugLog.PERF,
		(
			"%.0f fps for %.1f s — %s — slowest: %s"
			% [fps, _below_sec, str(stats.call()), slowest_probes()]
		)
	)
	return true


# The TOP_PROBES PerfProbe rings by p95, as "label p95/max ms".
static func slowest_probes() -> String:
	var snapshot: Dictionary = PerfProbe.snapshot()
	var rows: Array = []
	for label: String in snapshot:
		rows.append([label, snapshot[label]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1].p95) > int(b[1].p95))
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(mini(TOP_PROBES, rows.size())):
		var entry: Dictionary = rows[i][1]
		parts.append(
			"%s %.1f/%.1f" % [rows[i][0], float(entry.p95) / 1000.0, float(entry.max) / 1000.0]
		)
	return ", ".join(parts) if not parts.is_empty() else "none"
