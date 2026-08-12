## R.E.A.L. Visual Evidence Capture - Universal Version
## Screenshot + entity annotation evidence for inspecting spatial relationships.
##
## Usage:
##   1. Add as autoload (optional): Project > Project Settings > Autoload > Add "VisualEvidenceCapture"
##   2. Set camera: VisualEvidenceCapture.set_camera(camera)
##   3. Update positions: VisualEvidenceCapture.update_entity_position("Player", pos, "label")
##   4. EvidenceRecorder will call capture_screenshot() automatically
extends Node

# Dimension mode: "2d" or "3d"
var dimension_mode: String = "3d"

var _camera_3d: Camera3D
var _camera_2d: Camera2D
var _annotation_layer: CanvasLayer
var _annotation_control: Control

# Entity position cache (for annotations)
var _entity_positions: Dictionary = {}  # id -> {world_pos, label}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_setup_annotation_layer")


func _setup_annotation_layer() -> void:
	_annotation_layer = CanvasLayer.new()
	_annotation_layer.layer = 100
	add_child(_annotation_layer)

	_annotation_control = Control.new()
	_annotation_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_annotation_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_annotation_control.focus_mode = Control.FOCUS_NONE
	_annotation_control.connect("draw", _on_annotation_draw)
	_annotation_layer.add_child(_annotation_control)


## Set dimension mode: "2d" or "3d"
func set_dimension_mode(mode: String) -> void:
	dimension_mode = mode


## Register entity position (call each frame)
func update_entity_position(id: String, world_pos, label: String = "") -> void:
	_entity_positions[id] = {
		"world_pos": world_pos,
		"label": label if label else id
	}


## Remove entity
func remove_entity(id: String) -> void:
	_entity_positions.erase(id)


## Set 3D camera
func set_camera(camera: Camera3D) -> void:
	_camera_3d = camera


## Set 2D camera
func set_camera_2d(camera: Camera2D) -> void:
	_camera_2d = camera


## Core: capture a clean screenshot and a separate annotated debug image.
func capture_screenshot(session_dir: String, trigger_name: String, tick: int) -> String:
	if DisplayServer.get_name() == "headless":
		print("[VisualEvidence] Headless mode - skipping screenshot")
		return ""

	var viewport := get_viewport()
	if not viewport:
		push_error("[VisualEvidence] No viewport available")
		return ""

	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image()
	if not image:
		push_error("[VisualEvidence] Failed to get viewport image")
		return ""

	var filename := "screenshot_%s_T%d.png" % [trigger_name, tick]
	var filepath := session_dir + "/" + filename

	var error := image.save_png(filepath)
	if error != OK:
		push_error("[VisualEvidence] Failed to save screenshot: %s" % filepath)
		return ""

	print("[VisualEvidence] Clean screenshot saved: %s" % filename)

	_draw_annotations_on_image(image)
	var debug_filename := "screenshot_%s_T%d_debug.png" % [trigger_name, tick]
	var debug_filepath := session_dir + "/" + debug_filename
	var debug_error := image.save_png(debug_filepath)
	if debug_error != OK:
		push_error("[VisualEvidence] Failed to save debug screenshot: %s" % debug_filepath)
	else:
		print("[VisualEvidence] Debug screenshot saved: %s" % debug_filename)

	return filepath


## Draw annotations on image
func _draw_annotations_on_image(image: Image) -> void:
	var image_size := Vector2(image.get_width(), image.get_height())
	var viewport := get_viewport()
	var logical_size := viewport.get_visible_rect().size if viewport else image_size
	var image_scale := Vector2(
		image_size.x / maxf(logical_size.x, 1.0),
		image_size.y / maxf(logical_size.y, 1.0)
	)

	for id in _entity_positions:
		var data: Dictionary = _entity_positions[id]
		var world_pos = data.world_pos
		var label: String = data.label

		var screen_pos: Vector2 = _world_to_screen(world_pos, logical_size)
		if screen_pos.x >= 0 and screen_pos.x < logical_size.x and \
		   screen_pos.y >= 0 and screen_pos.y < logical_size.y:
			_draw_entity_marker(image, screen_pos * image_scale, label)


func _world_to_screen(world_pos, viewport_size: Vector2) -> Vector2:
	if dimension_mode == "2d":
		# 2D: world pos is already in screen-like coordinates
		# Adjust for camera offset if camera exists
		if _camera_2d:
			var cam_pos := _camera_2d.global_position
			var cam_zoom := _camera_2d.zoom
			var screen_center := viewport_size / 2.0
			var offset := (Vector2(world_pos.x, world_pos.y) - cam_pos) * cam_zoom
			return screen_center + offset
		return Vector2(world_pos.x, world_pos.y)
	else:
		# 3D: project world to screen
		if _has_valid_camera_projection(_camera_3d) and not _camera_3d.is_position_behind(world_pos):
			return _camera_3d.unproject_position(world_pos)
		return Vector2(-1, -1)  # Off-screen


func _has_valid_camera_projection(camera: Camera3D) -> bool:
	if not camera or not is_instance_valid(camera):
		return false
	var det: float = camera.global_transform.basis.determinant()
	return det == det and absf(det) > 0.000001


## Draw single entity marker on image
func _draw_entity_marker(image: Image, pos: Vector2, _label: String) -> void:
	var x := int(pos.x)
	var y := int(pos.y)
	var width := image.get_width()
	var height := image.get_height()

	var cross_size := 10
	var color := Color.RED

	for i in range(-cross_size, cross_size + 1):
		var px := x + i
		if px >= 0 and px < width and y >= 0 and y < height:
			image.set_pixel(px, y, color)
		var py := y + i
		if x >= 0 and x < width and py >= 0 and py < height:
			image.set_pixel(x, py, color)

	var box_size := 20
	for i in range(-box_size, box_size + 1):
		var px := x + i
		var py := y - box_size
		if px >= 0 and px < width and py >= 0 and py < height:
			image.set_pixel(px, py, color)
		py = y + box_size
		if px >= 0 and px < width and py >= 0 and py < height:
			image.set_pixel(px, py, color)
		px = x - box_size
		py = y + i
		if px >= 0 and px < width and py >= 0 and py < height:
			image.set_pixel(px, py, color)
		px = x + box_size
		if px >= 0 and px < width and py >= 0 and py < height:
			image.set_pixel(px, py, color)


## Generate annotation map (for log file)
func get_annotation_map() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	var viewport := get_viewport()
	if not viewport:
		return result

	var viewport_size := viewport.get_visible_rect().size

	for id in _entity_positions:
		var data: Dictionary = _entity_positions[id]
		var world_pos = data.world_pos
		var label: String = data.label

		var screen_pos := _world_to_screen(world_pos, viewport_size)
		if screen_pos.x >= 0 and screen_pos.x < viewport_size.x and \
		   screen_pos.y >= 0 and screen_pos.y < viewport_size.y:
			result.append({
				"id": id,
				"label": label,
				"screen_x": int(screen_pos.x),
				"screen_y": int(screen_pos.y),
				"world_pos": world_pos
			})

	return result


func _on_annotation_draw() -> void:
	pass
