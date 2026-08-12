## R.E.A.L. Runtime Action Executor - Universal Version
## Execute runtime verification actions over UDP or a Web JavaScript bridge.
##
## Usage:
##   1. Add as autoload: Project > Project Settings > Autoload > Add "RuntimeActionExecutor"
##   2. Register entities: RuntimeActionExecutor.register_entity("Player", node, state_dict)
##   3. Send commands via UDP: echo -e "type: set\nentity: Player\nfield: health\nvalue: 100" | nc -u localhost 19999
extends Node

signal command_received(command: Dictionary)
signal command_executed(result: Dictionary)

const DEFAULT_RUNTIME_ACTION_PORT := 19999
const RUNTIME_ACTION_RESULT_FILE := "user://commands/result.yaml"

# Dimension mode: "2d" or "3d"
var dimension_mode: String = "3d"

var _entity_refs: Dictionary = {}
var _state_refs: Dictionary = {}
var _spawn_counter: int = 0
var _command_counter: int = 0
var _probe_counter: int = 0
var _runtime_action_udp: PacketPeerUDP
var _runtime_action_port: int = DEFAULT_RUNTIME_ACTION_PORT
var _runtime_action_bind_host: String = "127.0.0.1"
var _evidence_recorder: Node
var _prefab_factory: Node
var _edit_mode_controller: Node
var _is_web: bool = false
var _debug_collision_enabled: bool = false
var _collision_visualizers: Array = []
var _timescale_adapter: Callable = Callable()
var _pause_adapter: Callable = Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep runtime actions responsive during pause.
	_evidence_recorder = get_node_or_null("/root/EvidenceRecorder")
	_prefab_factory = get_node_or_null("/root/PrefabFactory")
	_edit_mode_controller = get_node_or_null("/root/EditModeController")
	_is_web = OS.has_feature("web")

	if _is_check_only_run():
		print("[RuntimeAction] Check-only mode - skipping runtime initialization")
		call_deferred("_quit_check_only_run")
		return

	_runtime_action_port = _resolve_runtime_action_port()

	if _is_web:
		_setup_js_bridge()
	else:
		_setup_udp()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://commands"))
		if _runtime_action_udp != null:
			print("[RuntimeAction] Listening on udp://%s:%d" % [_runtime_action_bind_host, _runtime_action_port])


func _resolve_runtime_action_port() -> int:
	for key in ["RUNTIME_ACTION_UDP_PORT", "RUNTIME_ACTION_PORT"]:
		var raw := OS.get_environment(key).strip_edges()
		if raw.is_valid_int():
			var parsed := int(raw)
			if parsed > 0 and parsed < 65536:
				return parsed
	return DEFAULT_RUNTIME_ACTION_PORT


func _setup_udp() -> void:
	_runtime_action_bind_host = OS.get_environment("RUNTIME_ACTION_BIND_HOST").strip_edges()
	if _runtime_action_bind_host.is_empty():
		_runtime_action_bind_host = "127.0.0.1"
	_runtime_action_udp = PacketPeerUDP.new()
	var err := _runtime_action_udp.bind(_runtime_action_port, _runtime_action_bind_host)
	if err != OK:
		push_error("[RuntimeAction] Failed to bind udp://%s:%d: %s" % [_runtime_action_bind_host, _runtime_action_port, err])
		_runtime_action_udp = null


func _setup_js_bridge() -> void:
	var js_code := """
	window.Game = {
		execute: function(cmd) {
			window._game_cmd_queue = window._game_cmd_queue || [];
			window._game_cmd_queue.push(JSON.stringify(cmd));
			console.log('[R.E.A.L.] Command queued:', cmd);
		},
		get: function(entity, field) {
			this.execute({type: 'get', entity: entity, field: field});
		},
		set: function(entity, field, value) {
			this.execute({type: 'set', entity: entity, field: field, value: value});
		},
		pause: function() { this.execute({type: 'pause'}); },
		resume: function() { this.execute({type: 'resume'}); },
		capture: function(reason) { this.execute({type: 'capture', reason: reason || 'WEB_TRIGGER'}); },
		timescale: function(scale) { this.execute({type: 'timescale', scale: scale}); },
		spawn: function(prefab, x, y, z, props) {
			this.execute({type: 'spawn', prefab: prefab, position: [x||0, y||0, z||0], properties: props||{}});
		},
		help: function() {
			console.log('R.E.A.L. Runtime Action Commands:');
			console.log('  Game.get("Player", "health")      - Read entity state');
			console.log('  Game.set("Player", "health", 100) - Set entity field');
			console.log('  Game.spawn("enemy", 100, 200)     - Spawn prefab');
			console.log('  Game.pause()                      - Pause game');
			console.log('  Game.resume()                     - Resume game');
			console.log('  Game.capture("reason")            - Trigger log capture');
			console.log('  Game.timescale(0.5)               - Set time scale');
			console.log('  Game.execute({type:"...", ...})   - Raw command');
		}
	};
	window._game_cmd_queue = [];
	console.log('[R.E.A.L.] Runtime actions ready. Type Game.help() for commands.');
	"""
	JavaScriptBridge.eval(js_code)
	print("[RuntimeAction] JavaScript bridge initialized - use Game.help() in browser console")


func _is_check_only_run() -> bool:
	if OS.get_environment("REAL_CHECK_ONLY").strip_edges() == "1":
		return true
	for arg in OS.get_cmdline_args():
		if arg == "--check-only":
			return true
	return false


func _quit_check_only_run() -> void:
	if get_tree():
		get_tree().quit()


func _process(_delta: float) -> void:
	if _is_web:
		_poll_js_commands()
	else:
		if _runtime_action_udp == null:
			return
		while _runtime_action_udp.get_available_packet_count() > 0:
			var packet := _runtime_action_udp.get_packet()
			var sender_ip := _runtime_action_udp.get_packet_ip()
			var sender_port := _runtime_action_udp.get_packet_port()
			var content := packet.get_string_from_utf8()
			_process_yaml(content, sender_ip, sender_port)


func _poll_js_commands() -> void:
	var js_check := """
	(function() {
		if (window._game_cmd_queue && window._game_cmd_queue.length > 0) {
			return window._game_cmd_queue.shift();
		}
		return null;
	})()
	"""
	var result = JavaScriptBridge.eval(js_check)
	if result != null and result is String:
		var json := JSON.new()
		var err := json.parse(result)
		if err == OK:
			var cmd: Dictionary = json.data
			print("[RuntimeAction] Received command via JavaScript")
			var exec_result := execute(cmd)
			var js_log := "console.log('[R.E.A.L.] Result:', %s);" % JSON.stringify(exec_result)
			JavaScriptBridge.eval(js_log)


## Set dimension mode: "2d" or "3d"
func set_dimension_mode(mode: String) -> void:
	dimension_mode = mode


## Optional project-owned time adapter. Without one, Engine.time_scale is used.
func set_timescale_adapter(adapter: Callable) -> void:
	_timescale_adapter = adapter


## Optional project-owned pause adapter. It receives one Boolean: paused.
func set_pause_adapter(adapter: Callable) -> void:
	_pause_adapter = adapter


## Register entity reference
func register_entity(id: String, node: Node, state: Dictionary = {}) -> void:
	_entity_refs[id] = node
	_state_refs[id] = state
	# 同步到 EditModeController
	if _edit_mode_controller:
		_edit_mode_controller.register_entity(id, node)


## Unregister entity
func unregister_entity(id: String) -> void:
	_entity_refs.erase(id)
	_state_refs.erase(id)
	if _edit_mode_controller:
		_edit_mode_controller.unregister_entity(id)


## Update a tracked entity's state dictionary in place.
func update_entity_state(id: String, updates: Dictionary) -> void:
	if not _state_refs.has(id):
		return
	_state_refs[id].merge(updates, true)


## Execute command directly
func execute(command: Dictionary) -> Dictionary:
	var normalized_command := _ensure_command_ids(command)
	var cmd_type: String = normalized_command.get("type", "")
	var result := {"success": false, "message": "Unknown command", "command": normalized_command}
	command_received.emit(normalized_command.duplicate(true))

	match cmd_type:
		"get":
			result = _cmd_get(normalized_command)
		"set":
			result = _cmd_set(normalized_command)
		"teleport":
			result = _cmd_teleport(normalized_command)
		"spawn":
			result = _cmd_spawn(normalized_command)
		"destroy":
			result = _cmd_destroy(normalized_command)
		"emit":
			result = _cmd_emit(normalized_command)
		"pause":
			result = _cmd_pause(normalized_command)
		"resume":
			result = _cmd_resume(normalized_command)
		"timescale":
			result = _cmd_timescale(normalized_command)
		"capture":
			result = _cmd_capture(normalized_command)
		"debug_collision":
			result = _cmd_debug_collision(normalized_command)
		"persist":
			result = _cmd_persist(normalized_command)
		"edit_mode":
			result = _cmd_edit_mode(normalized_command)
		"export_layout":
			result = _cmd_export_layout(normalized_command)
		"input_key":
			result = _cmd_input_key(normalized_command)
		"input_mouse":
			result = _cmd_input_mouse(normalized_command)
		"input_drag":
			result = _cmd_input_drag(normalized_command)
		"input_action":
			result = _cmd_input_action(normalized_command)
		"call":
			result = _cmd_call(normalized_command)
		_:
			result.message = "Unknown command type: %s" % cmd_type

	result["command"] = normalized_command.duplicate(true)
	print("[RuntimeAction] Execute: %s -> %s" % [cmd_type, "OK" if result.success else result.message])
	command_executed.emit(result)
	return result


func _ensure_command_ids(command: Dictionary) -> Dictionary:
	var normalized := command.duplicate(true)
	if str(normalized.get("command_id", "")).strip_edges() == "":
		_command_counter += 1
		normalized["command_id"] = "cmd_%06d" % _command_counter
	if normalized.get("type", "") == "capture" and str(normalized.get("probe_id", "")).strip_edges() == "":
		_probe_counter += 1
		normalized["probe_id"] = "probe_%06d" % _probe_counter
	return normalized


func _process_yaml(content: String, sender_ip: String = "", sender_port: int = 0) -> void:
	if content.strip_edges().is_empty():
		return

	print("[RuntimeAction] Received command via UDP from %s:%d" % [sender_ip, sender_port])
	var commands := _parse_yaml(content)
	var results: Array[Dictionary] = []

	for cmd in commands:
		var result := execute(cmd)
		if cmd.has("request_id"):
			result["request_id"] = cmd["request_id"]
		results.append(result)

	_write_results(results)

	if sender_ip != "" and sender_port > 0:
		_send_udp_response(sender_ip, sender_port, results)


# ============================================
# Command implementations
# ============================================

func _cmd_set(cmd: Dictionary) -> Dictionary:
	var entity_id: String = cmd.get("entity", "")
	var field: String = cmd.get("field", "")
	var value = cmd.get("value")

	if not _state_refs.has(entity_id) and not _entity_refs.has(entity_id):
		return {"success": false, "message": "Entity not found: %s" % entity_id}

	var node: Node = _entity_refs.get(entity_id, null)
	var live_result := _try_set_live_entity_field(entity_id, node, field, value)
	if not live_result.is_empty():
		return live_result
	if not _state_refs.has(entity_id):
		return {"success": false, "message": "Entity state not tracked: %s" % entity_id}

	var state: Dictionary = _state_refs[entity_id]
	var old_value = state.get(field, null)
	state[field] = value

	if _evidence_recorder: _evidence_recorder.log_event("runtime_action.set", {"entity": entity_id, "field": field, "old": old_value, "new": value})
	return {"success": true, "message": "Set %s.%s = %s (was %s)" % [entity_id, field, value, old_value]}


func _try_set_live_entity_field(entity_id: String, node: Node, field: String, value) -> Dictionary:
	if node == null or field.is_empty():
		return {}
	var old_value = _read_live_property(node, field)
	var new_value = value
	if node.has_method("_runtime_set_field"):
		new_value = node.call("_runtime_set_field", field, value)
	elif _has_live_property(node, field):
		node.set(field, value)
		new_value = node.get(field)
	else:
		return {}
	if _state_refs.has(entity_id):
		_state_refs[entity_id][field] = new_value
	if _evidence_recorder:
		_evidence_recorder.update_entity(entity_id, {field: new_value})
		_evidence_recorder.log_event("runtime_action.set", {"entity": entity_id, "field": field, "old": old_value, "new": new_value})
	return {"success": true, "message": "Set %s.%s = %s (was %s)" % [entity_id, field, new_value, old_value], "value": new_value}


func _has_live_property(node: Node, field: String) -> bool:
	for property in node.get_property_list():
		if String(property.get("name", "")) == field:
			return true
	return false


func _read_live_property(node: Node, field: String):
	if node.has_method("_runtime_get_field"):
		return node.call("_runtime_get_field", field)
	if _has_live_property(node, field):
		return node.get(field)
	return null


func _cmd_get(cmd: Dictionary) -> Dictionary:
	var entity_id: String = cmd.get("entity", "")
	var field: String = cmd.get("field", "")

	if entity_id.is_empty() or field.is_empty():
		return {"success": false, "message": "get requires entity and field"}
	if not _entity_refs.has(entity_id) and not _state_refs.has(entity_id):
		return {"success": false, "message": "Entity not found: %s" % entity_id}

	var value = null
	var found := false
	var node: Node = _entity_refs.get(entity_id, null)
	if node and (node.has_method("_runtime_get_field") or _has_live_property(node, field)):
		value = _read_live_property(node, field)
		found = true
	elif _state_refs.has(entity_id):
		var state: Dictionary = _state_refs[entity_id]
		if state.has(field):
			value = state.get(field)
			found = true

	if not found:
		return {"success": false, "message": "Field not found: %s.%s" % [entity_id, field]}

	var value_text := _variant_to_response_text(value)
	if _evidence_recorder:
		_evidence_recorder.log_event("runtime_action.get", {"entity": entity_id, "field": field, "value": value_text})
	return {
		"success": true,
		"message": "%s.%s = %s" % [entity_id, field, value_text],
		"value": value,
	}


func _cmd_teleport(cmd: Dictionary) -> Dictionary:
	var entity_id: String = cmd.get("entity", "")
	var pos = cmd.get("position", [0, 0, 0] if dimension_mode == "3d" else [0, 0])

	if not _entity_refs.has(entity_id):
		return {"success": false, "message": "Entity not found: %s" % entity_id}

	var node: Node = _entity_refs[entity_id]

	if dimension_mode == "2d":
		var new_pos: Vector2
		if pos is Array:
			new_pos = Vector2(pos[0], pos[1])
		elif pos is Dictionary:
			new_pos = Vector2(pos.get("x", 0), pos.get("y", 0))
		else:
			return {"success": false, "message": "Invalid position format"}

		if node is Node2D:
			var old_pos := (node as Node2D).global_position
			(node as Node2D).global_position = new_pos
			if _state_refs.has(entity_id):
				_state_refs[entity_id]["position"] = new_pos
			if _evidence_recorder:
				_evidence_recorder.update_entity(entity_id, {"position": new_pos})
				_evidence_recorder.log_event("runtime_action.teleport", {"entity": entity_id, "from": old_pos, "to": new_pos})
			return {"success": true, "message": "Teleported %s to %s" % [entity_id, new_pos]}
	else:
		var new_pos: Vector3
		if pos is Array:
			new_pos = Vector3(pos[0], pos[1], pos[2] if pos.size() > 2 else 0)
		elif pos is Dictionary:
			new_pos = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		else:
			return {"success": false, "message": "Invalid position format"}

		if node is Node3D:
			var old_pos := (node as Node3D).global_position
			(node as Node3D).global_position = new_pos
			if _state_refs.has(entity_id):
				_state_refs[entity_id]["position"] = new_pos
			if _evidence_recorder:
				_evidence_recorder.update_entity(entity_id, {"position": new_pos})
				_evidence_recorder.log_event("runtime_action.teleport", {"entity": entity_id, "from": old_pos, "to": new_pos})
			return {"success": true, "message": "Teleported %s to %s" % [entity_id, new_pos]}

	return {"success": false, "message": "Entity is not valid Node2D/Node3D: %s" % entity_id}


func _cmd_spawn(cmd: Dictionary) -> Dictionary:
	var prefab_name: String = cmd.get("prefab", "")
	var pos = cmd.get("position", [0, 0, 0] if dimension_mode == "3d" else [0, 0])
	var properties_value: Variant = cmd.get("properties", {})
	var properties: Dictionary = properties_value if properties_value is Dictionary else {}
	var custom_id: String = cmd.get("id", "")

	if not _prefab_factory:
		return {"success": false, "message": "PrefabFactory not available"}

	var instance: Node = _prefab_factory.create(prefab_name, properties)
	if not instance:
		return {"success": false, "message": "Unknown prefab: %s (available: %s)" % [prefab_name, _prefab_factory.list()]}

	_spawn_counter += 1
	var entity_id := custom_id if custom_id != "" else "%s_%d" % [prefab_name, _spawn_counter]
	instance.name = entity_id

	# Set position based on dimension mode
	if dimension_mode == "2d":
		var spawn_pos: Vector2
		if pos is Array and pos.size() >= 2:
			spawn_pos = Vector2(pos[0], pos[1])
		elif pos is Dictionary:
			spawn_pos = Vector2(pos.get("x", 0), pos.get("y", 0))
		else:
			spawn_pos = Vector2.ZERO

		if instance is Node2D:
			(instance as Node2D).position = spawn_pos
	else:
		var spawn_pos: Vector3
		if pos is Array and pos.size() >= 3:
			spawn_pos = Vector3(pos[0], pos[1], pos[2])
		elif pos is Dictionary:
			spawn_pos = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		else:
			spawn_pos = Vector3.ZERO

		if instance is Node3D:
			(instance as Node3D).position = spawn_pos

	get_tree().current_scene.add_child(instance)

	var state := {"type": prefab_name, "position": pos}
	state.merge(properties, true)
	register_entity(entity_id, instance, state)
	if _evidence_recorder:
		_evidence_recorder.register_entity(entity_id, state)
		_evidence_recorder.log_event("runtime_action.spawn", {"id": entity_id, "prefab": prefab_name, "position": pos})

	return {"success": true, "message": "Spawned %s at %s" % [entity_id, pos], "id": entity_id}


func _cmd_destroy(cmd: Dictionary) -> Dictionary:
	var entity_id: String = cmd.get("entity", "")
	if not _entity_refs.has(entity_id):
		return {"success": false, "message": "Entity not found: %s" % entity_id}

	var node: Node = _entity_refs[entity_id]
	if _evidence_recorder:
		_evidence_recorder.log_event("runtime_action.destroy", {"entity": entity_id})
		_evidence_recorder.unregister_entity(entity_id)
	node.queue_free()
	_entity_refs.erase(entity_id)
	_state_refs.erase(entity_id)
	return {"success": true, "message": "Destroyed %s" % entity_id}


func _cmd_emit(cmd: Dictionary) -> Dictionary:
	var event_name: String = cmd.get("event", "")
	var data: Dictionary = cmd.get("data", {})
	if _evidence_recorder: _evidence_recorder.log_event("runtime_action.emit", {"event": event_name, "data": data})
	if _evidence_recorder: _evidence_recorder.log_event(event_name, data)
	return {"success": true, "message": "Emitted event: %s" % event_name}


## Invoke a method on a registered entity. The game must opt the method in via
## `_runtime_verification_methods() -> Array` returning the verification allowlist.
## This is the orthogonal "causation" primitive — it removes the need for ad-hoc
## input-injection workarounds when evaluator must trigger gameplay logic
## directly (e.g. fill inventory to test capacity pressure).
func _cmd_call(cmd: Dictionary) -> Dictionary:
	var entity_id: String = cmd.get("entity", "")
	var method: String = cmd.get("method", "")
	var args_raw: Variant = cmd.get("args", [])
	var args: Array = (args_raw as Array) if args_raw is Array else []

	if entity_id.is_empty() or method.is_empty():
		return {"success": false, "message": "call requires entity and method"}
	if not _entity_refs.has(entity_id):
		return {"success": false, "message": "Entity not found: %s" % entity_id}

	var node: Node = _entity_refs[entity_id]
	if not is_instance_valid(node):
		return {"success": false, "message": "Entity stale: %s" % entity_id}
	if not node.has_method(method):
		return {"success": false, "message": "%s has no method %s" % [entity_id, method]}
	if not _is_runtime_verification_method(node, method):
		return {
			"success": false,
			"message": "Method not runtime-verification exposed: %s.%s — game must list it in _runtime_verification_methods()" % [entity_id, method],
		}

	var ret: Variant = node.callv(method, args)
	var ret_text: String = _variant_to_response_text(ret)
	if _evidence_recorder:
		_evidence_recorder.log_event("runtime_action.call", {
			"entity": entity_id,
			"method": method,
			"args": args,
			"return": ret,
			"return_text": ret_text,
		})
	return {
		"success": true,
		"message": "%s.%s(...) -> %s" % [entity_id, method, ret_text],
		"return": ret,
		"value": ret,
	}


func _is_runtime_verification_method(node: Node, method: String) -> bool:
	if not node.has_method("_runtime_verification_methods"):
		return false
	var allowed: Variant = node.call("_runtime_verification_methods")
	if allowed is Array:
		return method in (allowed as Array)
	if allowed is PackedStringArray:
		return method in (allowed as PackedStringArray)
	return false


func _cmd_pause(_cmd: Dictionary) -> Dictionary:
	if _pause_adapter.is_valid():
		_pause_adapter.call(true)
	else:
		get_tree().paused = true
	if _evidence_recorder: _evidence_recorder.log_event("runtime_action.pause", {})
	return {"success": true, "message": "Game paused"}


func _cmd_resume(_cmd: Dictionary) -> Dictionary:
	if _pause_adapter.is_valid():
		_pause_adapter.call(false)
	else:
		get_tree().paused = false
	if _evidence_recorder: _evidence_recorder.log_event("runtime_action.resume", {})
	return {"success": true, "message": "Game resumed"}


func _cmd_timescale(cmd: Dictionary) -> Dictionary:
	var requested_scale: float = float(cmd.get("scale", 1.0))
	var scale := clampf(requested_scale, 0.05, 64.0)
	if _timescale_adapter.is_valid():
		_timescale_adapter.call(scale)
	else:
		Engine.time_scale = scale
	if _evidence_recorder:
		_evidence_recorder.log_event("runtime_action.timescale", {
			"requested_scale": requested_scale,
			"scale": scale,
			"engine_time_scale": Engine.time_scale,
		})
	return {"success": true, "message": "Time scale set to %s" % scale}


func _cmd_capture(cmd: Dictionary) -> Dictionary:
	if not _evidence_recorder:
		return {"success": false, "message": "EvidenceRecorder not available"}
	var reason: String = cmd.get("reason", "RUNTIME_ACTION_TRIGGER")
	var capture_context_value = cmd.get("context", {})
	var capture_context: Dictionary = capture_context_value.duplicate(true) if capture_context_value is Dictionary else {}
	capture_context["source"] = "runtime_action"
	capture_context["command_id"] = cmd.get("command_id", "")
	capture_context["probe_id"] = cmd.get("probe_id", "")
	if cmd.has("request_id"):
		capture_context["request_id"] = cmd["request_id"]
	_evidence_recorder.capture(reason, capture_context)
	return {"success": true, "message": "Captured: %s" % reason}


func _cmd_debug_collision(cmd: Dictionary) -> Dictionary:
	var enabled: bool = cmd.get("enabled", not _debug_collision_enabled)

	if enabled == _debug_collision_enabled:
		return {"success": true, "message": "Collision debug already %s" % ("ON" if enabled else "OFF")}

	_debug_collision_enabled = enabled

	if enabled:
		_show_collision_visualizers()
	else:
		_hide_collision_visualizers()

	if _evidence_recorder: _evidence_recorder.log_event("runtime_action.debug_collision", {"enabled": enabled})
	return {"success": true, "message": "Collision debug %s (%d shapes)" % [("ON" if enabled else "OFF"), _collision_visualizers.size()]}


func _cmd_persist(cmd: Dictionary) -> Dictionary:
	## Persist runtime-spawned entities to code
	if not _project_writes_enabled():
		return {"success": false, "message": "persist disabled; set RUNTIME_ACTION_ALLOW_PROJECT_WRITES=1 to opt in"}
	var output_path: String = cmd.get("output", "res://level_data.gd")
	var exclude: Array = cmd.get("exclude", ["Player"])

	var spawns: Array[Dictionary] = []
	for entity_id in _entity_refs:
		if entity_id in exclude:
			continue

		var node: Node = _entity_refs[entity_id]
		var state: Dictionary = _state_refs.get(entity_id, {})

		var pos_array: Array = []
		if dimension_mode == "2d" and node is Node2D:
			var pos: Vector2 = (node as Node2D).global_position
			pos_array = [snapped(pos.x, 0.01), snapped(pos.y, 0.01)]
		elif dimension_mode == "3d" and node is Node3D:
			var pos: Vector3 = (node as Node3D).global_position
			pos_array = [snapped(pos.x, 0.01), snapped(pos.y, 0.01), snapped(pos.z, 0.01)]
		else:
			continue

		spawns.append({
			"prefab": state.get("type", "unknown"),
			"position": pos_array,
		})

	if spawns.is_empty():
		return {"success": false, "message": "No entities to persist"}

	var code := _generate_level_code(spawns)

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "message": "Cannot write to %s" % output_path}

	file.store_string(code)
	file.close()

	if _evidence_recorder:
		_evidence_recorder.log_event("runtime_action.persist", {"count": spawns.size(), "output": output_path})

	return {"success": true, "message": "Persisted %d entities to %s" % [spawns.size(), output_path], "entities": spawns}


func _cmd_edit_mode(cmd: Dictionary) -> Dictionary:
	## Enter/exit runtime edit mode for visual layout adjustment
	if not _project_writes_enabled():
		return {"success": false, "message": "edit_mode disabled; set RUNTIME_ACTION_ALLOW_PROJECT_WRITES=1 to opt in"}
	var enabled: bool = cmd.get("enabled", true)
	var level_name: String = cmd.get("level", "layout")

	if not _edit_mode_controller:
		# 尝试动态创建
		var _base: String = get_script().resource_path.get_base_dir()
		var EditModeScript = load(_base + "/edit_mode_controller.gd")
		if EditModeScript:
			_edit_mode_controller = EditModeScript.new()
			_edit_mode_controller.name = "EditModeController"
			_edit_mode_controller.set_dimension_mode(dimension_mode)
			get_tree().root.add_child(_edit_mode_controller)
			# 同步实体注册
			for id in _entity_refs:
				_edit_mode_controller.register_entity(id, _entity_refs[id])
		else:
			return {"success": false, "message": "EditModeController not available"}

	_edit_mode_controller.set_edit_mode(enabled)

	if _evidence_recorder:
		_evidence_recorder.log_event("runtime_action.edit_mode", {"enabled": enabled, "level": level_name})

	if enabled:
		return {"success": true, "message": "Edit mode ON - drag entities to adjust, click 'Finish Editing' when done"}
	else:
		return {"success": true, "message": "Edit mode OFF"}


func _cmd_export_layout(cmd: Dictionary) -> Dictionary:
	## Export current layout to YAML and code
	if not _project_writes_enabled():
		return {"success": false, "message": "export_layout disabled; set RUNTIME_ACTION_ALLOW_PROJECT_WRITES=1 to opt in"}
	var level_name: String = cmd.get("level", "layout")

	if not _edit_mode_controller:
		return {"success": false, "message": "EditModeController not available"}

	var result: Dictionary = _edit_mode_controller.export_layout(level_name)

	if _evidence_recorder and result.success:
		_evidence_recorder.log_event("runtime_action.export_layout", {
			"level": level_name,
			"entities": result.entity_count,
			"yaml_path": result.yaml_path
		})

	return result


func _project_writes_enabled() -> bool:
	return OS.get_environment("RUNTIME_ACTION_ALLOW_PROJECT_WRITES").strip_edges() == "1"


func _generate_level_code(spawns: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	lines.append("## Auto-generated level data")
	lines.append("## Generated by R.E.A.L. runtime action persist command")
	lines.append("extends Node")
	lines.append("")
	lines.append("")
	lines.append("func _ready() -> void:")
	lines.append("\tvar factory := get_node_or_null(\"/root/PrefabFactory\")")
	lines.append("\tif not factory:")
	lines.append("\t\tpush_error(\"[LevelData] PrefabFactory not found\")")
	lines.append("\t\treturn")
	lines.append("")
	lines.append("\t_spawn_entities(factory)")
	lines.append("")
	lines.append("")
	lines.append("func _spawn_entities(factory: Node) -> void:")

	for spawn in spawns:
		var prefab: String = spawn.prefab
		var pos: Array = spawn.position
		if dimension_mode == "2d":
			lines.append("\tfactory.create(\"%s\", {}).position = Vector2(%s, %s)" % [prefab, pos[0], pos[1]])
		else:
			lines.append("\tfactory.create(\"%s\", {}).position = Vector3(%s, %s, %s)" % [prefab, pos[0], pos[1], pos[2]])

	lines.append("")
	lines.append("\tprint(\"[LevelData] Spawned %d entities\")" % spawns.size())

	return "\n".join(lines)


func _show_collision_visualizers() -> void:
	_hide_collision_visualizers()

	var root := get_tree().current_scene
	if not root:
		return

	if dimension_mode == "2d":
		_show_collision_visualizers_2d(root)
	else:
		_show_collision_visualizers_3d(root)

	print("[RuntimeAction] Collision visualizers created: %d" % _collision_visualizers.size())


func _show_collision_visualizers_2d(root: Node) -> void:
	var shapes := _find_all_collision_shapes_2d(root)
	for shape_node in shapes:
		var visualizer := _create_shape_visualizer_2d(shape_node)
		if visualizer:
			shape_node.add_child(visualizer)
			_collision_visualizers.append(visualizer)


func _show_collision_visualizers_3d(root: Node) -> void:
	var wire_mat := StandardMaterial3D.new()
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire_mat.albedo_color = Color(0, 1, 0, 0.5)
	wire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var shapes := _find_all_collision_shapes_3d(root)
	for shape_node in shapes:
		var visualizer := _create_shape_visualizer_3d(shape_node, wire_mat)
		if visualizer:
			shape_node.add_child(visualizer)
			_collision_visualizers.append(visualizer)


func _hide_collision_visualizers() -> void:
	for vis in _collision_visualizers:
		if is_instance_valid(vis):
			vis.queue_free()
	_collision_visualizers.clear()


func _find_all_collision_shapes_2d(node: Node) -> Array:
	var result: Array = []
	if node is CollisionShape2D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_collision_shapes_2d(child))
	return result


func _find_all_collision_shapes_3d(node: Node) -> Array:
	var result: Array = []
	if node is CollisionShape3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_collision_shapes_3d(child))
	return result


func _create_shape_visualizer_2d(shape_node: CollisionShape2D) -> Node2D:
	var shape := shape_node.shape
	if not shape:
		return null

	var visualizer := Node2D.new()
	visualizer.name = "CollisionDebug"

	# Store shape info for drawing
	visualizer.set_meta("shape", shape)
	var _base2: String = get_script().resource_path.get_base_dir()
	var debug_path: String = _base2 + "/collision_debug_2d.gd"
	visualizer.set_script(load(debug_path) if ResourceLoader.exists(debug_path) else null)

	return visualizer


func _create_shape_visualizer_3d(shape_node: CollisionShape3D, mat: Material) -> MeshInstance3D:
	var shape := shape_node.shape
	if not shape:
		return null

	var mesh: Mesh = null

	if shape is BoxShape3D:
		var box := BoxMesh.new()
		box.size = shape.size
		mesh = box
	elif shape is SphereShape3D:
		var sphere := SphereMesh.new()
		sphere.radius = shape.radius
		sphere.height = shape.radius * 2
		mesh = sphere
	elif shape is CapsuleShape3D:
		var capsule := CapsuleMesh.new()
		capsule.radius = shape.radius
		capsule.height = shape.height
		mesh = capsule
	elif shape is CylinderShape3D:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = shape.radius
		cylinder.bottom_radius = shape.radius
		cylinder.height = shape.height
		mesh = cylinder
	else:
		return null

	var visualizer := MeshInstance3D.new()
	visualizer.name = "CollisionDebug"
	visualizer.mesh = mesh
	visualizer.material_override = mat
	visualizer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	return visualizer


# ============================================
# Result output
# ============================================

func _send_udp_response(ip: String, port: int, results: Array[Dictionary]) -> void:
	var response_lines: PackedStringArray = []
	for result in results:
		response_lines.append(_format_udp_result(result))
	var response := "\n".join(response_lines) + "\n"
	var should_send_fallback := _should_send_udp_fallback(results)

	if _runtime_action_udp != null:
		_runtime_action_udp.set_dest_address(ip, port)
		_runtime_action_udp.put_packet(response.to_utf8_buffer())
		if not should_send_fallback:
			return

	var reply_udp := PacketPeerUDP.new()
	reply_udp.set_dest_address(ip, port)
	reply_udp.put_packet(response.to_utf8_buffer())
	reply_udp.close()


func _format_udp_result(result: Dictionary) -> String:
	var req_id: String = str(result.get("request_id", ""))
	if bool(result.get("success", false)) and result.has("value"):
		var value_text := _variant_to_response_text(result.get("value"))
		return "[%s] %s" % [req_id, value_text] if req_id != "" else value_text

	var status: String = "OK" if bool(result.get("success", false)) else "FAIL"
	var message: String = str(result.get("message", ""))
	if req_id != "":
		return "[%s] %s: %s" % [req_id, status, message]
	return "%s: %s" % [status, message]


func _variant_to_response_text(value) -> String:
	if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_NIL]:
		return JSON.stringify(value)
	return str(value)


func _should_send_udp_fallback(results: Array[Dictionary]) -> bool:
	for result in results:
		if bool(result.get("success", false)) and result.has("value"):
			return true
	return false


func _write_results(results: Array[Dictionary]) -> void:
	if _is_web:
		var js_log := "console.log('[R.E.A.L.] Batch results:', %s);" % JSON.stringify(results)
		JavaScriptBridge.eval(js_log)
		return

	var lines: PackedStringArray = []
	lines.append("# Runtime Action Execution Results")
	lines.append("timestamp: %s" % Time.get_datetime_string_from_system())
	lines.append("")

	for i in results.size():
		var r: Dictionary = results[i]
		lines.append("- index: %d" % i)
		if r.has("request_id"):
			lines.append("  request_id: \"%s\"" % r.request_id)
		lines.append("  success: %s" % r.success)
		lines.append("  message: \"%s\"" % r.message)
		lines.append("")

	var file := FileAccess.open(RUNTIME_ACTION_RESULT_FILE, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines))
		file.close()


# ============================================
# Simple YAML parser
# ============================================

func _parse_yaml(content: String) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var current_cmd: Dictionary = {}
	var in_list := false

	for line in content.split("\n"):
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			continue

		if stripped.begins_with("- "):
			if not current_cmd.is_empty():
				commands.append(current_cmd)
			current_cmd = {}
			in_list = true
			var rest := stripped.substr(2).strip_edges()
			if ":" in rest:
				_parse_kv(rest, current_cmd)
			continue

		if in_list and (line.begins_with("  ") or line.begins_with("\t")):
			_parse_kv(stripped, current_cmd)
			continue

		if ":" in stripped:
			_parse_kv(stripped, current_cmd)

	if not current_cmd.is_empty():
		commands.append(current_cmd)

	return commands


func _parse_kv(line: String, dict: Dictionary) -> void:
	var idx := line.find(":")
	if idx == -1:
		return
	var key := line.substr(0, idx).strip_edges()
	var val := line.substr(idx + 1).strip_edges()
	dict[key] = _parse_value(val)


func _parse_value(s: String) -> Variant:
	if s.is_empty() or s == "null" or s == "~":
		return null
	if s == "true" or s == "yes":
		return true
	if s == "false" or s == "no":
		return false
	if (s.begins_with("\"") and s.ends_with("\"")) or (s.begins_with("'") and s.ends_with("'")):
		return s.substr(1, s.length() - 2)
	if s.begins_with("[") and s.ends_with("]"):
		var inner := s.substr(1, s.length() - 2)
		var arr: Array = []
		for item in inner.split(","):
			arr.append(_parse_value(item.strip_edges()))
		return arr
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	return s


# ============================================
# Runtime action input simulation commands
# ============================================
# These commands inject synthetic input events into the Godot engine,
# allowing AI agents to simulate human interaction (keyboard, mouse, drag).
#
# Usage via UDP:
#   echo -e "type: input_key\nkey: W\naction: press" | nc -u localhost 19999
#   echo -e "type: input_key\nkey: Enter" | nc -u localhost 19999
#   echo -e "type: input_mouse\nbutton: left\nposition: [640, 360]" | nc -u localhost 19999
#   echo -e "type: input_drag\nfrom: [1200, 200]\nto: [1200, 500]\nsteps: 10" | nc -u localhost 19999
#   echo -e "type: input_action\naction: move_forward\npressed: true" | nc -u localhost 19999

## Keycode lookup table for common key names
const _KEY_MAP := {
	"A": KEY_A, "B": KEY_B, "C": KEY_C, "D": KEY_D, "E": KEY_E,
	"F": KEY_F, "G": KEY_G, "H": KEY_H, "I": KEY_I, "J": KEY_J,
	"K": KEY_K, "L": KEY_L, "M": KEY_M, "N": KEY_N, "O": KEY_O,
	"P": KEY_P, "Q": KEY_Q, "R": KEY_R, "S": KEY_S, "T": KEY_T,
	"U": KEY_U, "V": KEY_V, "W": KEY_W, "X": KEY_X, "Y": KEY_Y,
	"Z": KEY_Z,
	"0": KEY_0, "1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4,
	"5": KEY_5, "6": KEY_6, "7": KEY_7, "8": KEY_8, "9": KEY_9,
	"Enter": KEY_ENTER, "Escape": KEY_ESCAPE, "Esc": KEY_ESCAPE,
	"Space": KEY_SPACE, "Tab": KEY_TAB, "Backspace": KEY_BACKSPACE,
	"/": KEY_SLASH, "Slash": KEY_SLASH,
	".": KEY_PERIOD, "Period": KEY_PERIOD,
	"-": KEY_MINUS, "Minus": KEY_MINUS,
	"_": KEY_MINUS, ":": KEY_SEMICOLON, ";": KEY_SEMICOLON,
	"Shift": KEY_SHIFT, "Ctrl": KEY_CTRL, "Alt": KEY_ALT,
	"Up": KEY_UP, "Down": KEY_DOWN, "Left": KEY_LEFT, "Right": KEY_RIGHT,
	"F1": KEY_F1, "F2": KEY_F2, "F3": KEY_F3, "F4": KEY_F4,
	"F5": KEY_F5, "F6": KEY_F6, "F7": KEY_F7, "F8": KEY_F8,
	"F9": KEY_F9, "F10": KEY_F10, "F11": KEY_F11, "F12": KEY_F12,
}

func _get_input_viewport() -> Viewport:
	if get_tree() and get_tree().root:
		return get_tree().root
	return get_viewport()

func _dispatch_viewport_input(event: InputEvent) -> void:
	var viewport := _get_input_viewport()
	if viewport:
		# R.E.A.L coordinates are expressed in the captured canvas/viewport space.
		# Passing them through Input.parse_input_event() makes Godot interpret them
		# as physical window coordinates and apply canvas stretch a second time
		# (for example 486,780 becomes 243,390 at 2x presentation scale).
		viewport.push_input(event, true)
		if event is InputEventMouse:
			viewport.update_mouse_cursor_state()
		return
	Input.parse_input_event(event)

func _push_viewport_input(event: InputEvent) -> void:
	_dispatch_viewport_input(event)

func _push_mouse_input(event: InputEvent) -> void:
	_dispatch_viewport_input(event)


func _resolve_mouse_position(pos_raw) -> Vector2:
	if pos_raw is Array and pos_raw.size() >= 2:
		return Vector2(float(pos_raw[0]), float(pos_raw[1]))
	if pos_raw is Dictionary:
		return Vector2(float(pos_raw.get("x", 0)), float(pos_raw.get("y", 0)))
	var viewport := _get_input_viewport()
	if viewport:
		return viewport.get_visible_rect().size * 0.5
	return Vector2(640, 360)


func _normalize_mouse_command(button_name: String, action: String) -> Dictionary:
	var resolved_button := button_name.strip_edges().to_lower()
	var resolved_action := action.strip_edges().to_lower()

	if resolved_action.ends_with("_click"):
		resolved_button = resolved_action.replace("_click", "")
		resolved_action = "click"
	elif resolved_action.ends_with("_press"):
		resolved_button = resolved_action.replace("_press", "")
		resolved_action = "press"
	elif resolved_action.ends_with("_release"):
		resolved_button = resolved_action.replace("_release", "")
		resolved_action = "release"
	elif resolved_action == "tap":
		resolved_action = "click"

	if resolved_button == "":
		resolved_button = "left"

	return {
		"button": resolved_button,
		"action": resolved_action if resolved_action != "" else "click",
	}

func _mouse_button_mask(button_index: int) -> int:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return 1
		MOUSE_BUTTON_RIGHT:
			return 2
		MOUSE_BUTTON_MIDDLE:
			return 4
		MOUSE_BUTTON_XBUTTON1:
			return 128
		MOUSE_BUTTON_XBUTTON2:
			return 256
		_:
			return 0

func _is_wheel_button(button_index: int) -> bool:
	return button_index in [
		MOUSE_BUTTON_WHEEL_UP,
		MOUSE_BUTTON_WHEEL_DOWN,
		MOUSE_BUTTON_WHEEL_LEFT,
		MOUSE_BUTTON_WHEEL_RIGHT,
	]

func _push_mouse_motion(pos: Vector2, relative: Vector2 = Vector2.ZERO, button_mask: int = 0) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.relative = relative
	motion.button_mask = button_mask
	_push_mouse_input(motion)

func _push_mouse_button(button_index: int, pressed: bool, pos: Vector2, button_mask: int = 0, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = pos
	event.global_position = pos
	event.button_mask = button_mask
	event.factor = factor
	_push_mouse_input(event)

func _push_mouse_click(button_index: int, pos: Vector2, factor: float = 1.0, hold_time: float = 0.05) -> void:
	_push_mouse_button(button_index, true, pos, _mouse_button_mask(button_index), factor)
	if get_tree():
		get_tree().create_timer(maxf(hold_time, 0.0), true).timeout.connect(
			Callable(self, "_push_mouse_button").bind(button_index, false, pos, 0, factor)
		)
	else:
		_push_mouse_button(button_index, false, pos, 0, factor)

func _resolve_keycode(key_name: String) -> int:
	var upper := key_name.strip_edges().to_upper()
	if upper.length() == 1 and _KEY_MAP.has(upper):
		return _KEY_MAP[upper]
	# Try original case
	if _KEY_MAP.has(key_name.strip_edges()):
		return _KEY_MAP[key_name.strip_edges()]
	# Try as KEY_ constant name (e.g. "KEY_W")
	if key_name.begins_with("KEY_"):
		var short := key_name.substr(4)
		if _KEY_MAP.has(short):
			return _KEY_MAP[short]
	return -1


func _resolve_key_unicode(key_name: String) -> int:
	var cleaned := key_name.strip_edges()
	if cleaned == "Space":
		return 32
	if cleaned.length() != 1:
		return 0
	return cleaned.unicode_at(0)


## Simulate keyboard input
## cmd: { key: "W", action: "press"|"release"|"tap" (default "tap"), duration: 0.1 }
func _cmd_input_key(cmd: Dictionary) -> Dictionary:
	var key_name: String = str(cmd.get("key", ""))
	var action: String = str(cmd.get("action", "tap"))
	var duration: float = float(cmd.get("duration", 0.1))

	var keycode := _resolve_keycode(key_name)
	if keycode < 0:
		return {"success": false, "message": "Unknown key: %s" % key_name}
	var unicode_value := _resolve_key_unicode(key_name)

	var viewport := get_viewport()
	if not viewport:
		return {"success": false, "message": "No viewport available"}

	if action == "press" or action == "tap":
		var press_event := InputEventKey.new()
		press_event.keycode = keycode
		press_event.physical_keycode = keycode
		press_event.unicode = unicode_value
		press_event.pressed = true
		_push_viewport_input(press_event)

	if action == "release" or action == "tap":
		var release_event := InputEventKey.new()
		release_event.keycode = keycode
		release_event.physical_keycode = keycode
		release_event.unicode = 0
		release_event.pressed = false
		if action == "tap":
			# Delay release slightly for tap
			get_tree().create_timer(duration, true).timeout.connect(Callable(self, "_push_viewport_input").bind(release_event))
		else:
			_push_viewport_input(release_event)

	return {"success": true, "message": "input_key %s %s" % [key_name, action]}


## Simulate mouse click
## cmd: { button: "left"|"right"|"middle", position: [x, y], action: "click"|"press"|"release" }
func _cmd_input_mouse(cmd: Dictionary) -> Dictionary:
	var normalized := _normalize_mouse_command(str(cmd.get("button", "")), str(cmd.get("action", "click")))
	var button_name: String = normalized.get("button", "left")
	var action: String = normalized.get("action", "click")
	var pos := _resolve_mouse_position(cmd.get("position", [640, 360]))
	var hold_time: float = maxf(float(cmd.get("duration", 0.05)), 0.0)

	var button_index: int
	match button_name.to_lower():
		"left", "left_click", "left_button": button_index = MOUSE_BUTTON_LEFT
		"right", "right_click", "right_button": button_index = MOUSE_BUTTON_RIGHT
		"middle", "middle_click", "middle_button": button_index = MOUSE_BUTTON_MIDDLE
		"wheel_up", "scroll_up": button_index = MOUSE_BUTTON_WHEEL_UP
		"wheel_down", "scroll_down": button_index = MOUSE_BUTTON_WHEEL_DOWN
		_: return {"success": false, "message": "Unknown button: %s" % button_name}

	# Move mouse to position first
	_push_mouse_motion(pos)

	if _is_wheel_button(button_index):
		if action == "release":
			return {"success": true, "message": "input_mouse %s at (%d,%d) %s" % [button_name, pos.x, pos.y, action]}
		_push_mouse_button(button_index, true, pos, 0, 1.0)
		return {"success": true, "message": "input_mouse %s at (%d,%d) %s" % [button_name, pos.x, pos.y, action]}

	if action == "click":
		_push_mouse_click(button_index, pos, 1.0, hold_time)
	elif action == "press":
		_push_mouse_button(button_index, true, pos, _mouse_button_mask(button_index), 1.0)
	elif action == "release":
		_push_mouse_button(button_index, false, pos, 0, 1.0)

	return {"success": true, "message": "input_mouse %s at (%d,%d) %s" % [button_name, pos.x, pos.y, action]}


## Simulate mouse drag (for scrollbars, sliders, etc.)
## cmd: { from: [x1, y1], to: [x2, y2], steps: 10, duration: 0.3 }
func _cmd_input_drag(cmd: Dictionary) -> Dictionary:
	var from_raw = cmd.get("from", [640, 300])
	var to_raw = cmd.get("to", [640, 500])
	var steps: int = int(cmd.get("steps", 10))
	var duration: float = float(cmd.get("duration", 0.3))

	var from_pos := Vector2(float(from_raw[0]), float(from_raw[1])) if from_raw is Array and from_raw.size() >= 2 else Vector2(640, 300)
	var to_pos := Vector2(float(to_raw[0]), float(to_raw[1])) if to_raw is Array and to_raw.size() >= 2 else Vector2(640, 500)

	steps = clampi(steps, 2, 100)
	var step_delay := duration / float(steps)
	var left_mask := _mouse_button_mask(MOUSE_BUTTON_LEFT)

	_push_mouse_motion(from_pos)

	# Press at start position
	_push_mouse_button(MOUSE_BUTTON_LEFT, true, from_pos, left_mask, 1.0)

	# Move through intermediate positions
	var previous_pos := from_pos
	for i in range(steps):
		var t := float(i + 1) / float(steps)
		var pos := from_pos.lerp(to_pos, t)
		var move_pos := pos
		var relative := move_pos - previous_pos
		previous_pos = move_pos
		get_tree().create_timer(step_delay * (i + 1)).timeout.connect(Callable(self, "_push_mouse_motion").bind(move_pos, relative, left_mask))

	# Release at end position
	get_tree().create_timer(duration + 0.05).timeout.connect(Callable(self, "_push_mouse_button").bind(MOUSE_BUTTON_LEFT, false, to_pos, 0, 1.0))

	return {"success": true, "message": "input_drag from (%d,%d) to (%d,%d) in %d steps" % [from_pos.x, from_pos.y, to_pos.x, to_pos.y, steps]}


## Simulate Godot input action (move_forward, interact, etc.)
## cmd: { action: "move_forward", pressed: true, strength: 1.0 }
func _cmd_input_action(cmd: Dictionary) -> Dictionary:
	var action_name: String = str(cmd.get("action", ""))
	var pressed: bool = bool(cmd.get("pressed", true))
	var strength: float = float(cmd.get("strength", 1.0))

	if action_name.is_empty():
		return {"success": false, "message": "No action specified"}

	if not InputMap.has_action(action_name):
		return {"success": false, "message": "Unknown action: %s" % action_name}

	if pressed:
		Input.action_press(action_name, strength)
	else:
		Input.action_release(action_name)

	return {"success": true, "message": "input_action %s %s" % [action_name, "pressed" if pressed else "released"]}
