## R.E.A.L. Evidence Recorder - Universal Version
## Structured runtime evidence recording based on axiomatic derivation.
## Output format adapts to Claude Code's Glob/Grep/Read capabilities
##
## Usage:
##   1. Add as autoload: Project > Project Settings > Autoload > Add "EvidenceRecorder"
##   2. Call EvidenceRecorder.set_tick(tick) each frame
##   3. Call EvidenceRecorder.log_event("EventType", {data}) for events
##   4. Press F9 to capture snapshot
extends Node

const MAX_EVENT_HISTORY := 100
const LOG_DIR := "user://logs"
const OBSERVABILITY_DIRNAME := "observability"
const SNAPSHOTS_DIRNAME := "snapshots"
const ARTIFACTS_DIRNAME := "artifacts"
const SESSION_MANIFEST_FILENAME := "session_manifest.json"
const TIMELINE_FILENAME := "timeline.jsonl"

# Dimension mode: "2d" or "3d"
var dimension_mode: String = "3d"

var _session_dir: String
var _session_id: String = ""
var _run_id: String = ""
var _trigger_count: int = 0
var _start_time: float = 0.0
var _current_tick: int = 0
var _event_history: Array[Dictionary] = []
var _tracked_entities: Dictionary = {}  # id -> entity_data
var _anomaly_bounds: Dictionary = {}
var _config: Dictionary = {}
var _visual_evidence_capture: Node = null
var _enable_screenshots: bool = true
var _is_web: bool = false
var _started_at: String = ""
var _observability_dir: String = ""
var _snapshots_dir: String = ""
var _artifacts_dir: String = ""
var _session_manifest_path: String = ""
var _timeline_path: String = ""
var _latest_snapshot_path: String = ""
var _latest_artifact_path: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_time = Time.get_ticks_msec() / 1000.0
	_is_web = OS.has_feature("web")
	_init_session()
	_setup_hotkey()

	if _is_web:
		_setup_web_log_viewer()


func _init_session() -> void:
	var datetime := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_started_at = Time.get_datetime_string_from_system()
	_session_id = "session_" + datetime
	_run_id = _resolve_run_id(_session_id)
	_session_dir = LOG_DIR + "/" + _session_id

	var global_session := ProjectSettings.globalize_path(_session_dir)
	var global_log_dir := ProjectSettings.globalize_path(LOG_DIR)
	DirAccess.make_dir_recursive_absolute(global_session)
	_init_observability_paths()
	_init_observability_storage()

	_create_latest_symlink(global_log_dir, global_session)
	_write_session_manifest()

	print("[EvidenceRecording] Session: %s" % global_session)


func _create_latest_symlink(log_dir: String, session_path: String) -> void:
	var latest_link := log_dir + "/latest"

	if FileAccess.file_exists(latest_link) or DirAccess.dir_exists_absolute(latest_link):
		DirAccess.remove_absolute(latest_link)

	if not OS.has_feature("web") and not OS.has_feature("windows"):
		var err := OS.execute("ln", ["-sfn", session_path, latest_link])
		if err == OK:
			print("[EvidenceRecording] Symlink: %s -> latest" % session_path.get_file())


func _setup_hotkey() -> void:
	if not InputMap.has_action("debug_capture"):
		InputMap.add_action("debug_capture")
		var event := InputEventKey.new()
		event.keycode = KEY_F9
		InputMap.action_add_event("debug_capture", event)


func _setup_web_log_viewer() -> void:
	var js_code := """
	window.GameEvidence = {
		history: [],
		captures: [],
		showHistory: function(n) {
			var count = n || 20;
			console.log('[R.E.A.L.] Recent ' + count + ' events:');
			this.history.slice(-count).forEach(function(e, i) {
				console.log('  [T:' + e.tick + '] ' + e.type, e.data || '');
			});
		},
		showCaptures: function() {
			console.log('[R.E.A.L.] Captures:', this.captures.length);
			this.captures.forEach(function(c, i) {
				console.log('  ' + (i+1) + '. ' + c.trigger + ' at T:' + c.tick);
			});
		}
	};
	console.log('[R.E.A.L.] Evidence recording ready. Use GameEvidence.showHistory() or GameEvidence.showCaptures()');
	"""
	JavaScriptBridge.eval(js_code)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_capture"):
		capture("MANUAL", {"description": "Manual trigger (F9)"})


# ============================================
# Public API
# ============================================

## Set dimension mode: "2d" or "3d"
func set_dimension_mode(mode: String) -> void:
	dimension_mode = mode
	_write_session_manifest()


## Set current tick (call each frame)
func set_tick(tick: int) -> void:
	_current_tick = tick


## Set game config (for HEADER output)
func set_config(config: Dictionary) -> void:
	_config = config
	_write_session_manifest()


## Register entity for tracking
func register_entity(id: String, data: Dictionary) -> void:
	_tracked_entities[id] = data


## Update entity state
func update_entity(id: String, updates: Dictionary) -> void:
	if _tracked_entities.has(id):
		_tracked_entities[id].merge(updates, true)


## Unregister entity
func unregister_entity(id: String) -> void:
	_tracked_entities.erase(id)


## Log event (for HISTORY)
func log_event(event_type: String, data: Dictionary = {}) -> void:
	var caller := _get_caller_info()
	var event := {
		"tick": _current_tick,
		"time": _elapsed_time(),
		"type": event_type,
		"data": data,
		"caller": caller
	}
	_event_history.append(event)
	if _event_history.size() > MAX_EVENT_HISTORY:
		_event_history.pop_front()
	_append_timeline_event(event)


func _get_caller_info() -> Dictionary:
	var stack := get_stack()
	if stack.size() >= 3:
		var frame: Dictionary = stack[2]
		return {
			"file": frame.source.get_file(),
			"line": frame.line,
			"func": frame.function
		}
	return {}


## Log warning
func log_warn(message: String, data: Dictionary = {}) -> void:
	log_event("WARN:" + message, data)


## Log error
func log_error(message: String, data: Dictionary = {}) -> void:
	log_event("ERR:" + message, data)


## Set anomaly bounds
func set_anomaly_bounds(bounds: Dictionary) -> void:
	_anomaly_bounds = bounds


## Set the visual evidence capture provider.
func set_visual_evidence_capture(provider: Node) -> void:
	_visual_evidence_capture = provider


## Enable/disable screenshots
func set_screenshots_enabled(enabled: bool) -> void:
	_enable_screenshots = enabled


## Detect anomalies
func detect_anomalies() -> Array[Dictionary]:
	var anomalies: Array[Dictionary] = []

	for id in _tracked_entities:
		var entity: Dictionary = _tracked_entities[id]
		var entity_type: String = entity.get("type", "*")
		var bounds: Dictionary = _anomaly_bounds.get(entity_type, _anomaly_bounds.get("*", {}))

		for field in bounds:
			if not entity.has(field):
				continue
			var value = entity[field]
			var field_bounds: Dictionary = bounds[field]

			if value is float or value is int:
				if field_bounds.has("min") and value < field_bounds.min:
					anomalies.append({"id": id, "field": field, "value": value, "bounds": field_bounds, "violation": "min"})
				if field_bounds.has("max") and value > field_bounds.max:
					anomalies.append({"id": id, "field": field, "value": value, "bounds": field_bounds, "violation": "max"})

	return anomalies


## Check and auto-capture anomalies
func check_and_capture() -> void:
	var anomalies := detect_anomalies()
	if not anomalies.is_empty():
		var summary := _make_anomaly_summary(anomalies)
		capture(summary, {"anomalies": anomalies})


## Core capture function
func capture(trigger_summary: String, context: Dictionary = {}) -> String:
	_trigger_count += 1
	var seq := "%03d" % _trigger_count
	var summary := trigger_summary.to_upper().replace(" ", "_")
	var capture_stem := "trigger_%s_%s_T%d" % [seq, summary, _current_tick]
	var filename := capture_stem + ".log"
	var filepath := _session_dir + "/" + filename
	var capture_context := context.duplicate(true)
	capture_context["reason"] = String(capture_context.get("reason", trigger_summary))

	var initial_content := _build_log_content(trigger_summary, capture_context)
	_write_capture_file(filepath, initial_content)
	var snapshot_path := _write_snapshot(capture_stem, trigger_summary, capture_context, "", [])
	var artifact_path := _write_artifact_metadata(capture_stem, trigger_summary, capture_context, "", [])
	_append_capture_snapshot_event(trigger_summary, capture_context, snapshot_path, artifact_path, "")
	if snapshot_path != "":
		_latest_snapshot_path = snapshot_path
		_write_session_manifest()

	# Visual evidence screenshot.
	var screenshot_path := ""
	var annotations: Array[Dictionary] = []
	if _enable_screenshots and _visual_evidence_capture and _visual_evidence_capture.has_method("capture_screenshot"):
		screenshot_path = await _visual_evidence_capture.capture_screenshot(_session_dir, summary, _current_tick)
		if _visual_evidence_capture.has_method("get_annotation_map"):
			annotations = _visual_evidence_capture.get_annotation_map()

	var content := _build_log_content(trigger_summary, capture_context, screenshot_path, annotations)
	_write_capture_file(filepath, content)
	if screenshot_path != "" or not annotations.is_empty():
		snapshot_path = _write_snapshot(capture_stem, trigger_summary, capture_context, screenshot_path, annotations)
		artifact_path = _write_artifact_metadata(capture_stem, trigger_summary, capture_context, screenshot_path, annotations)
		if snapshot_path != "":
			_latest_snapshot_path = snapshot_path
			_write_session_manifest()
	print("[EvidenceRecording] Captured: %s" % filename)
	return filepath


func _append_capture_snapshot_event(trigger_summary: String, capture_context: Dictionary, snapshot_path: String, artifact_path: String, screenshot_path: String) -> void:
	_append_timeline_event({
		"tick": _current_tick,
		"time": _elapsed_time(),
		"type": "Capture.snapshot",
		"reason": trigger_summary,
		"trigger_summary": {
			"reason": trigger_summary,
			"normalized": trigger_summary.to_upper().replace(" ", "_"),
			"source": str(capture_context.get("source", "")),
		},
		"data": {
			"reason": trigger_summary,
			"command_id": str(capture_context.get("command_id", "")),
			"probe_id": str(capture_context.get("probe_id", "")),
			"request_id": str(capture_context.get("request_id", "")),
			"snapshot_path": _global_or_empty(snapshot_path),
			"artifact_path": _global_or_empty(artifact_path),
			"screenshot_path": screenshot_path,
		},
		"caller": {},
	})


# ============================================
# Internal methods
# ============================================

func _elapsed_time() -> float:
	return (Time.get_ticks_msec() / 1000.0) - _start_time


func _resolve_run_id(fallback: String) -> String:
	for key in ["RUNTIME_EVIDENCE_RUN_ID", "RUN_ID", "GODOT_PROCESS_TAG"]:
		var value := OS.get_environment(key).strip_edges()
		if value != "":
			return value
	return fallback


func _init_observability_paths() -> void:
	_observability_dir = _session_dir + "/" + OBSERVABILITY_DIRNAME
	_snapshots_dir = _observability_dir + "/" + SNAPSHOTS_DIRNAME
	_artifacts_dir = _observability_dir + "/" + ARTIFACTS_DIRNAME
	_session_manifest_path = _observability_dir + "/" + SESSION_MANIFEST_FILENAME
	_timeline_path = _observability_dir + "/" + TIMELINE_FILENAME


func _init_observability_storage() -> void:
	for path in [_observability_dir, _snapshots_dir, _artifacts_dir]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	if not FileAccess.file_exists(_timeline_path):
		var timeline_file := FileAccess.open(_timeline_path, FileAccess.WRITE)
		if timeline_file:
			timeline_file.close()
		else:
			push_error("[EvidenceRecording] Failed to initialize timeline: %s" % _timeline_path)


func _format_float(val: float) -> String:
	if absf(val) < 0.01:
		return "0"
	return "%.2f" % val


func _format_vector(v) -> String:
	if v is Vector2:
		return "(%s, %s)" % [_format_float(v.x), _format_float(v.y)]
	elif v is Vector3:
		return "(%s, %s, %s)" % [_format_float(v.x), _format_float(v.y), _format_float(v.z)]
	return str(v)


func _make_anomaly_summary(anomalies: Array[Dictionary]) -> String:
	if anomalies.is_empty():
		return "ANOMALY"
	var first: Dictionary = anomalies[0]
	return "%s_%s_%s" % [first.id, first.field, first.violation]


func _build_log_content(trigger_summary: String, context: Dictionary, screenshot_path: String = "", annotations: Array[Dictionary] = []) -> String:
	var lines: PackedStringArray = []
	var elapsed := _elapsed_time()

	# === HEADER ===
	lines.append("# === HEADER ===")
	lines.append("[META] trigger=\"%s\" tick=%d time=%.2fs mode=%s" % [trigger_summary, _current_tick, elapsed, dimension_mode])

	var config_parts: PackedStringArray = []
	for key in _config:
		config_parts.append("%s=%s" % [key, _config[key]])
	if not config_parts.is_empty():
		lines.append("[CONFIG] %s" % " ".join(config_parts))

	if context.has("description"):
		lines.append("[DESC] %s" % context.description)

	if screenshot_path:
		lines.append("[SCREENSHOT] %s" % screenshot_path.get_file())

	lines.append("")

	# === VISUAL EVIDENCE ANNOTATIONS ===
	if not annotations.is_empty():
		lines.append("# === VISUAL ===")
		for ann in annotations:
			var world_str := _format_vector(ann.world_pos)
			lines.append("[MARKER] id=%s label=%s screen=(%d,%d) world=%s" % [
				ann.id,
				ann.label,
				ann.screen_x,
				ann.screen_y,
				world_str
			])
		lines.append("")

	# === SNAPSHOT ===
	lines.append("# === SNAPSHOT ===")

	var anomalies: Array = context.get("anomalies", [])
	var anomaly_map := {}
	for a in anomalies:
		anomaly_map["%s.%s" % [a.id, a.field]] = a

	for id in _tracked_entities:
		var entity: Dictionary = _tracked_entities[id]
		lines.append_array(_format_entity(id, entity, anomaly_map))

	lines.append("")

	# === HISTORY ===
	lines.append("# === HISTORY ===")

	for event in _event_history:
		lines.append(_format_event(event, elapsed))

	var violation_fields: PackedStringArray = []
	for a in anomalies:
		violation_fields.append("%s.%s=%s" % [a.id, a.field, a.value])

	if not violation_fields.is_empty():
		lines.append("[T:%d] [NOW]   [ERR]   !!VIOLATION!! %s" % [_current_tick, " ".join(violation_fields)])
	else:
		lines.append("[T:%d] [NOW]   [INFO]  Trigger: %s" % [_current_tick, trigger_summary])

	return "\n".join(lines)


func _write_capture_file(filepath: String, content: String) -> void:
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
	else:
		push_error("[EvidenceRecording] Failed to write: %s" % filepath)


func _format_entity(id: String, entity: Dictionary, anomaly_map: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []

	var header_parts: PackedStringArray = ["id=%s" % id]

	if entity.has("parent"):
		header_parts.append("parent=%s" % entity.parent)
	if entity.has("path"):
		header_parts.append("path=%s" % entity.path)
	if entity.has("type"):
		header_parts.append("type=%s" % entity.type)
	if entity.has("state"):
		header_parts.append("state=%s" % entity.state)

	lines.append("[ENTITY] %s" % " ".join(header_parts))

	# Position/velocity line
	var motion_parts: PackedStringArray = []
	if entity.has("position"):
		motion_parts.append("pos=%s" % _format_vector(entity.position))
	if entity.has("velocity"):
		var vel = entity.velocity
		motion_parts.append("vel=%s" % _format_vector(vel))
		var speed: float = vel.length() if vel else 0.0
		motion_parts.append("speed=%s" % _format_float(speed))

	if not motion_parts.is_empty():
		lines.append("    | %s" % " ".join(motion_parts))

	# Other fields
	var skip_fields := ["parent", "path", "type", "state", "position", "velocity"]
	var other_parts: PackedStringArray = []

	for field in entity:
		if field in skip_fields:
			continue
		var value = entity[field]
		var formatted: String

		if value is float:
			formatted = _format_float(value)
		elif value is Vector2 or value is Vector3:
			formatted = _format_vector(value)
		else:
			formatted = str(value)

		var key := "%s.%s" % [id, field]
		if anomaly_map.has(key):
			other_parts.append("%s=%s !!VIOLATION!!" % [field, formatted])
		else:
			other_parts.append("%s=%s" % [field, formatted])

	if not other_parts.is_empty():
		lines.append("    | %s" % " ".join(other_parts))

	return lines


func _format_event(event: Dictionary, current_elapsed: float) -> String:
	var tick: int = event.tick
	var event_time: float = event.time
	var event_type: String = event.type
	var data: Dictionary = event.data
	var caller: Dictionary = event.get("caller", {})

	var time_diff := event_time - current_elapsed
	var time_str: String
	if absf(time_diff) < 0.05:
		time_str = "[NOW]  "
	else:
		time_str = "[%.1fs]" % time_diff

	var level := "EVENT"
	if event_type.begins_with("WARN:"):
		level = "WARN"
		event_type = event_type.substr(5)
	elif event_type.begins_with("ERR:"):
		level = "ERR"
		event_type = event_type.substr(4)

	var caller_str := ""
	if not caller.is_empty():
		caller_str = " @%s:%d(%s)" % [caller.file, caller.line, caller.func]

	var data_parts: PackedStringArray = []
	for key in data:
		var value = data[key]
		if value is float:
			data_parts.append("%s=%s" % [key, _format_float(value)])
		elif value is Vector2 or value is Vector3:
			data_parts.append("%s=%s" % [key, _format_vector(value)])
		else:
			data_parts.append("%s=%s" % [key, value])

	var data_str := " ".join(data_parts)
	if data_str:
		return "[T:%d] %s [%-5s] %s %s%s" % [tick, time_str, level, event_type, data_str, caller_str]
	else:
		return "[T:%d] %s [%-5s] %s%s" % [tick, time_str, level, event_type, caller_str]


func _append_timeline_event(event: Dictionary) -> void:
	var line := {
		"run_id": _run_id,
		"session_id": _session_id,
		"tick": event.get("tick", _current_tick),
		"time": event.get("time", _elapsed_time()),
		"type": event.get("type", ""),
		"data": _to_json_compatible(event.get("data", {})),
		"caller": _to_json_compatible(event.get("caller", {})),
	}
	if event.has("reason"):
		line["reason"] = str(event.get("reason", ""))
	if event.has("trigger_summary"):
		line["trigger_summary"] = _to_json_compatible(event.get("trigger_summary", {}))
	_append_jsonl(_timeline_path, line)


func _write_snapshot(snapshot_name: String, trigger_summary: String, context: Dictionary, screenshot_path: String, annotations: Array[Dictionary]) -> String:
	var anomalies: Array = context.get("anomalies", [])
	var snapshot_path := _snapshots_dir + "/" + snapshot_name + ".json"
	var snapshot := {
		"run_id": _run_id,
		"session_id": _session_id,
		"trigger_summary": {
			"reason": trigger_summary,
			"normalized": trigger_summary.to_upper().replace(" ", "_"),
			"source": str(context.get("source", "")),
		},
		"tick": _current_tick,
		"time": _elapsed_time(),
		"command_id": str(context.get("command_id", "")),
		"probe_id": str(context.get("probe_id", "")),
		"context": _to_json_compatible(context),
		"anomalies": _to_json_compatible(anomalies),
		"tracked_entities": _to_json_compatible(_tracked_entities),
		"recent_events": _to_json_compatible(_event_history),
		"screenshot_path": screenshot_path,
		"annotations": _to_json_compatible(annotations),
	}
	if _write_json_file(snapshot_path, snapshot):
		return snapshot_path
	return ""


func _write_artifact_metadata(artifact_name: String, trigger_summary: String, context: Dictionary, screenshot_path: String, annotations: Array[Dictionary]) -> String:
	var artifact_path := _artifacts_dir + "/" + artifact_name + ".json"
	var artifact := {
		"run_id": _run_id,
		"session_id": _session_id,
		"probe_id": str(context.get("probe_id", "")),
		"command_id": str(context.get("command_id", "")),
		"screenshot_path": screenshot_path,
		"annotations": _to_json_compatible(annotations),
		"reason": trigger_summary,
		"trigger": trigger_summary,
		"trigger_summary": {
			"reason": trigger_summary,
			"normalized": trigger_summary.to_upper().replace(" ", "_"),
			"source": str(context.get("source", "")),
		},
		"tick": _current_tick,
	}
	if _write_json_file(artifact_path, artifact):
		_latest_artifact_path = artifact_path
		_write_session_manifest()
		return artifact_path
	return ""


func _write_session_manifest() -> void:
	if _session_manifest_path == "":
		return
	var manifest := {
		"run_id": _run_id,
		"session_id": _session_id,
		"dimension_mode": dimension_mode,
		"session_dir": ProjectSettings.globalize_path(_session_dir),
		"observability_dir": ProjectSettings.globalize_path(_observability_dir),
		"started_at": _started_at,
		"config": _to_json_compatible(_config),
		"latest_snapshot_path": _global_or_empty(_latest_snapshot_path),
		"latest_artifact_path": _global_or_empty(_latest_artifact_path),
	}
	_write_json_file(_session_manifest_path, manifest)


func _write_json_file(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("[EvidenceRecording] Failed to write json: %s" % path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func _append_jsonl(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if not file:
		push_error("[EvidenceRecording] Failed to append jsonl: %s" % path)
		return
	file.seek_end()
	file.store_line(JSON.stringify(payload))
	file.close()


func _global_or_empty(path: String) -> String:
	if path == "":
		return ""
	return ProjectSettings.globalize_path(path)


func _to_json_compatible(value):
	if value == null:
		return null
	if value is bool or value is int or value is float or value is String:
		return value
	if value is StringName:
		return str(value)
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z}
	if value is Dictionary:
		var out := {}
		for key in value:
			out[str(key)] = _to_json_compatible(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_to_json_compatible(item))
		return out
	return str(value)
