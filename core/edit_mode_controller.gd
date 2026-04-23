## R.E.A.L. Edit Mode Controller
## 运行时编辑模式：让用户在游戏运行时调整实体位置
##
## 功能：
##   - 暂停游戏逻辑但保持渲染
##   - 显示实体 Gizmo（可拖拽手柄）
##   - 点击选中，拖拽移动
##   - "完成编辑"按钮导出布局
##
## 使用：
##   C4 命令：type: edit_mode, enabled: true
##   或代码：EditModeController.set_edit_mode(true)
extends Node

signal edit_mode_changed(enabled: bool)
signal layout_exported(result: Dictionary)

# 维度模式
var dimension_mode: String = "3d"

# 编辑状态
var _edit_mode_enabled: bool = false
var _selected_entity: Node = null
var _dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _entity_start_pos = null  # Vector2 or Vector3

# 实体注册（与 ActionExecutor 共享）
var _entity_refs: Dictionary = {}  # id -> node

# UI
var _ui_layer: CanvasLayer
var _finish_button: Button
var _info_label: Label

# Gizmo
var _gizmo_nodes: Dictionary = {}  # entity_id -> gizmo_node
const GIZMO_COLOR := Color(0, 1, 0.5, 0.8)
const GIZMO_SELECTED_COLOR := Color(1, 1, 0, 1)
const GIZMO_SIZE_2D := 20.0
const GIZMO_SIZE_3D := 0.3


func _ready() -> void:
	_setup_ui()
	set_process_input(false)  # 只在编辑模式下处理输入


func set_dimension_mode(mode: String) -> void:
	dimension_mode = mode


## 注册实体（通常由 ActionExecutor 调用）
func register_entity(id: String, node: Node) -> void:
	_entity_refs[id] = node
	if _edit_mode_enabled:
		_create_gizmo(id, node)


func unregister_entity(id: String) -> void:
	_remove_gizmo(id)
	_entity_refs.erase(id)


## 设置编辑模式
func set_edit_mode(enabled: bool) -> void:
	if enabled == _edit_mode_enabled:
		return

	_edit_mode_enabled = enabled

	if enabled:
		_enter_edit_mode()
	else:
		_exit_edit_mode()

	edit_mode_changed.emit(enabled)


func is_edit_mode() -> bool:
	return _edit_mode_enabled


# ============================================
# 进入/退出编辑模式
# ============================================

func _enter_edit_mode() -> void:
	print("[EditMode] Entering edit mode")

	# 暂停游戏逻辑（但保持渲染和输入）
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS  # 自己不被暂停

	# 显示 UI
	_ui_layer.visible = true
	_info_label.text = "Edit Mode: Click to select, drag to move"

	# 为所有实体创建 Gizmo
	for id in _entity_refs:
		_create_gizmo(id, _entity_refs[id])

	# 启用输入处理
	set_process_input(true)


func _exit_edit_mode() -> void:
	print("[EditMode] Exiting edit mode")

	# 恢复游戏
	get_tree().paused = false

	# 隐藏 UI
	_ui_layer.visible = false

	# 移除所有 Gizmo
	for id in _gizmo_nodes.keys():
		_remove_gizmo(id)

	# 清除选中
	_selected_entity = null
	_dragging = false

	# 禁用输入处理
	set_process_input(false)


# ============================================
# UI 设置
# ============================================

func _setup_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 100
	_ui_layer.visible = false
	_ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui_layer)

	# 完成按钮
	_finish_button = Button.new()
	_finish_button.text = "Finish Editing"
	_finish_button.position = Vector2(20, 20)
	_finish_button.size = Vector2(150, 40)
	_finish_button.pressed.connect(_on_finish_pressed)
	_finish_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui_layer.add_child(_finish_button)

	# 信息标签
	_info_label = Label.new()
	_info_label.position = Vector2(20, 70)
	_info_label.add_theme_color_override("font_color", Color.WHITE)
	_info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_info_label.add_theme_constant_override("shadow_offset_x", 1)
	_info_label.add_theme_constant_override("shadow_offset_y", 1)
	_ui_layer.add_child(_info_label)


func _on_finish_pressed() -> void:
	# 导出布局
	var result := export_layout()
	layout_exported.emit(result)

	# 退出编辑模式
	set_edit_mode(false)

	print("[EditMode] Layout exported: %d entities" % result.get("entity_count", 0))


# ============================================
# Gizmo 创建/更新
# ============================================

func _create_gizmo(id: String, node: Node) -> void:
	if _gizmo_nodes.has(id):
		return

	if dimension_mode == "2d" and node is Node2D:
		var gizmo := _create_gizmo_2d()
		gizmo.process_mode = Node.PROCESS_MODE_ALWAYS
		node.add_child(gizmo)
		_gizmo_nodes[id] = gizmo
	elif dimension_mode == "3d" and node is Node3D:
		var gizmo := _create_gizmo_3d()
		gizmo.process_mode = Node.PROCESS_MODE_ALWAYS
		node.add_child(gizmo)
		_gizmo_nodes[id] = gizmo


func _create_gizmo_2d() -> Node2D:
	var gizmo := Node2D.new()
	gizmo.name = "EditGizmo"
	gizmo.z_index = 1000
	var _base := get_script().resource_path.get_base_dir()
	var gizmo_path := _base + "/gizmo_2d.gd"
	gizmo.set_script(load(gizmo_path) if ResourceLoader.exists(gizmo_path) else null)

	# 如果没有专门的脚本，用简单的绘制
	if not gizmo.get_script():
		var draw_node := _GizmoDraw2D.new()
		draw_node.gizmo_color = GIZMO_COLOR
		draw_node.gizmo_size = GIZMO_SIZE_2D
		gizmo.add_child(draw_node)

	return gizmo


func _create_gizmo_3d() -> Node3D:
	var gizmo := Node3D.new()
	gizmo.name = "EditGizmo"

	# 创建可见的球体标记
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = GIZMO_SIZE_3D
	sphere.height = GIZMO_SIZE_3D * 2
	mesh_instance.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = GIZMO_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = mat

	gizmo.add_child(mesh_instance)
	gizmo.set_meta("mesh_instance", mesh_instance)

	return gizmo


func _remove_gizmo(id: String) -> void:
	if _gizmo_nodes.has(id):
		var gizmo: Node = _gizmo_nodes[id]
		if is_instance_valid(gizmo):
			gizmo.queue_free()
		_gizmo_nodes.erase(id)


func _update_gizmo_selection(id: String, selected: bool) -> void:
	if not _gizmo_nodes.has(id):
		return

	var gizmo: Node = _gizmo_nodes[id]
	var color := GIZMO_SELECTED_COLOR if selected else GIZMO_COLOR

	if dimension_mode == "2d":
		for child in gizmo.get_children():
			if child is _GizmoDraw2D:
				child.gizmo_color = color
				child.queue_redraw()
	else:
		var mesh_instance: MeshInstance3D = gizmo.get_meta("mesh_instance", null)
		if mesh_instance and mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = color


# ============================================
# 输入处理
# ============================================

func _input(event: InputEvent) -> void:
	if not _edit_mode_enabled:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# 尝试选中实体
			var clicked_entity := _get_entity_at_position(event.position)
			if clicked_entity:
				_select_entity(clicked_entity)
				_start_drag(event.position)
			else:
				_deselect()
		else:
			# 释放拖拽
			_end_drag()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _selected_entity or not _dragging:
		return

	var delta := event.position - _drag_start_pos

	if dimension_mode == "2d" and _selected_entity is Node2D:
		(_selected_entity as Node2D).position = _entity_start_pos + delta
	elif dimension_mode == "3d" and _selected_entity is Node3D:
		# 3D 中，将屏幕移动转换为世界坐标移动
		var camera := get_viewport().get_camera_3d()
		if camera:
			# 简化处理：在 XZ 平面上移动
			var scale_factor := 0.01  # 调整灵敏度
			var world_delta := Vector3(delta.x * scale_factor, 0, delta.y * scale_factor)
			(_selected_entity as Node3D).position = _entity_start_pos + world_delta


func _get_entity_at_position(screen_pos: Vector2) -> Node:
	if dimension_mode == "2d":
		return _get_entity_at_position_2d(screen_pos)
	else:
		return _get_entity_at_position_3d(screen_pos)


func _get_entity_at_position_2d(screen_pos: Vector2) -> Node:
	var closest_entity: Node = null
	var closest_dist := INF

	for id in _entity_refs:
		var node: Node = _entity_refs[id]
		if node is Node2D:
			var entity_screen_pos := (node as Node2D).get_global_transform_with_canvas().origin
			var dist := screen_pos.distance_to(entity_screen_pos)
			if dist < GIZMO_SIZE_2D * 2 and dist < closest_dist:
				closest_dist = dist
				closest_entity = node

	return closest_entity


func _get_entity_at_position_3d(screen_pos: Vector2) -> Node:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return null

	var closest_entity: Node = null
	var closest_dist := INF

	for id in _entity_refs:
		var node: Node = _entity_refs[id]
		if node is Node3D:
			var world_pos := (node as Node3D).global_position
			if not camera.is_position_behind(world_pos):
				var entity_screen_pos := camera.unproject_position(world_pos)
				var dist := screen_pos.distance_to(entity_screen_pos)
				if dist < 50 and dist < closest_dist:  # 50 像素的点击范围
					closest_dist = dist
					closest_entity = node

	return closest_entity


func _select_entity(entity: Node) -> void:
	# 取消旧选中
	if _selected_entity:
		var old_id := _get_entity_id(_selected_entity)
		if old_id:
			_update_gizmo_selection(old_id, false)

	# 选中新实体
	_selected_entity = entity
	var new_id := _get_entity_id(entity)
	if new_id:
		_update_gizmo_selection(new_id, true)
		_info_label.text = "Selected: %s" % new_id


func _deselect() -> void:
	if _selected_entity:
		var id := _get_entity_id(_selected_entity)
		if id:
			_update_gizmo_selection(id, false)
	_selected_entity = null
	_info_label.text = "Edit Mode: Click to select, drag to move"


func _start_drag(screen_pos: Vector2) -> void:
	if not _selected_entity:
		return

	_dragging = true
	_drag_start_pos = screen_pos

	if _selected_entity is Node2D:
		_entity_start_pos = (_selected_entity as Node2D).position
	elif _selected_entity is Node3D:
		_entity_start_pos = (_selected_entity as Node3D).position


func _end_drag() -> void:
	_dragging = false


func _get_entity_id(entity: Node) -> String:
	for id in _entity_refs:
		if _entity_refs[id] == entity:
			return id
	return ""


# ============================================
# 导出布局
# ============================================

func export_layout(level_name: String = "layout") -> Dictionary:
	var entities: Array[Dictionary] = []

	for id in _entity_refs:
		var node: Node = _entity_refs[id]
		var data := {"id": id}

		# 获取预制体类型
		var script: Script = node.get_script()
		if script:
			data["prefab"] = script.resource_path.get_file().get_basename()
		else:
			data["prefab"] = "unknown"

		# 获取位置
		if dimension_mode == "2d" and node is Node2D:
			var pos := (node as Node2D).position
			data["position"] = [snapped(pos.x, 0.1), snapped(pos.y, 0.1)]
			if (node as Node2D).rotation != 0:
				data["rotation"] = snapped((node as Node2D).rotation_degrees, 0.1)
		elif dimension_mode == "3d" and node is Node3D:
			var pos := (node as Node3D).position
			data["position"] = [snapped(pos.x, 0.1), snapped(pos.y, 0.1), snapped(pos.z, 0.1)]
			if (node as Node3D).rotation != Vector3.ZERO:
				var rot := (node as Node3D).rotation_degrees
				data["rotation"] = [snapped(rot.x, 0.1), snapped(rot.y, 0.1), snapped(rot.z, 0.1)]

		entities.append(data)

	# 生成 YAML
	var yaml_content := _generate_yaml(level_name, entities)

	# 写入文件
	var yaml_path := "res://levels/%s.yaml" % level_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://levels/"))
	var file := FileAccess.open(yaml_path, FileAccess.WRITE)
	if file:
		file.store_string(yaml_content)
		file.close()
		print("[EditMode] Exported to: %s" % yaml_path)

	# 同时生成代码
	var code_content := _generate_code(level_name, entities)
	var code_path := "res://levels/%s_data.gd" % level_name
	file = FileAccess.open(code_path, FileAccess.WRITE)
	if file:
		file.store_string(code_content)
		file.close()

	return {
		"success": true,
		"level_name": level_name,
		"entity_count": entities.size(),
		"yaml_path": yaml_path,
		"code_path": code_path,
		"entities": entities
	}


func _generate_yaml(level_name: String, entities: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []

	lines.append("# R.E.A.L. Layout Export")
	lines.append("# Generated: %s" % Time.get_datetime_string_from_system())
	lines.append("# Edit Mode export - human adjusted positions")
	lines.append("")
	lines.append("level: %s" % level_name)
	lines.append("dimension: %s" % dimension_mode)
	lines.append("entity_count: %d" % entities.size())
	lines.append("")
	lines.append("entities:")

	for entity in entities:
		lines.append("  - id: %s" % entity.id)
		lines.append("    prefab: %s" % entity.prefab)
		var pos: Array = entity.position
		if dimension_mode == "2d":
			lines.append("    position: [%s, %s]" % [pos[0], pos[1]])
		else:
			lines.append("    position: [%s, %s, %s]" % [pos[0], pos[1], pos[2]])
		if entity.has("rotation"):
			var rot = entity.rotation
			if rot is Array:
				lines.append("    rotation: [%s, %s, %s]" % [rot[0], rot[1], rot[2]])
			else:
				lines.append("    rotation: %s" % rot)
		lines.append("")

	return "\n".join(lines)


func _generate_code(level_name: String, entities: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []

	lines.append("## Auto-generated from Edit Mode")
	lines.append("## Level: %s" % level_name)
	lines.append("## Generated: %s" % Time.get_datetime_string_from_system())
	lines.append("extends Node")
	lines.append("")
	lines.append("")
	lines.append("func _ready() -> void:")
	lines.append("\tvar factory := get_node_or_null(\"/root/PrefabFactory\")")
	lines.append("\tif not factory:")
	lines.append("\t\tpush_error(\"PrefabFactory not found\")")
	lines.append("\t\treturn")
	lines.append("\t_spawn_layout(factory)")
	lines.append("")
	lines.append("")
	lines.append("func _spawn_layout(factory: Node) -> void:")

	for entity in entities:
		var prefab: String = entity.prefab
		var pos: Array = entity.position

		lines.append("\t# %s" % entity.id)
		if dimension_mode == "2d":
			lines.append("\tvar %s := factory.create(\"%s\", {})" % [entity.id, prefab])
			lines.append("\t%s.position = Vector2(%s, %s)" % [entity.id, pos[0], pos[1]])
		else:
			lines.append("\tvar %s := factory.create(\"%s\", {})" % [entity.id, prefab])
			lines.append("\t%s.position = Vector3(%s, %s, %s)" % [entity.id, pos[0], pos[1], pos[2]])

		if entity.has("rotation"):
			var rot = entity.rotation
			if rot is Array:
				lines.append("\t%s.rotation_degrees = Vector3(%s, %s, %s)" % [entity.id, rot[0], rot[1], rot[2]])
			else:
				lines.append("\t%s.rotation_degrees = %s" % [entity.id, rot])

		lines.append("\tadd_child(%s)" % entity.id)
		lines.append("")

	lines.append("\tprint(\"[%s] Spawned %d entities\")" % [level_name, entities.size()])

	return "\n".join(lines)


# ============================================
# 内部类：2D Gizmo 绘制
# ============================================

class _GizmoDraw2D extends Node2D:
	var gizmo_color := Color.GREEN
	var gizmo_size := 20.0

	func _draw() -> void:
		# 绘制十字
		draw_line(Vector2(-gizmo_size, 0), Vector2(gizmo_size, 0), gizmo_color, 2.0)
		draw_line(Vector2(0, -gizmo_size), Vector2(0, gizmo_size), gizmo_color, 2.0)
		# 绘制圆圈
		draw_arc(Vector2.ZERO, gizmo_size * 0.8, 0, TAU, 32, gizmo_color, 2.0)
