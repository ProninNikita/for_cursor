class_name RTCombatEventCollector
extends RefCounted

var timeline: Array[Dictionary] = []
var max_process_usec: int = 0

func reset() -> void:
	timeline.clear()
	max_process_usec = 0

func record_timeline(time_seconds: float, kind: String, text: String, importance: int = 1, limit: int = 24) -> void:
	if text == "":
		return
	timeline.append({
		"time": time_seconds,
		"kind": kind,
		"text": text,
		"importance": importance
	})
	while timeline.size() > limit:
		timeline.remove_at(0)

func record_process_time(start_usec: int) -> void:
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	if elapsed_usec > max_process_usec:
		max_process_usec = elapsed_usec

func max_tick_ms() -> float:
	return float(max_process_usec) / 1000.0
