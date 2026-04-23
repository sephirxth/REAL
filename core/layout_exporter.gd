## R.E.A.L. Layout Exporter
## 将编辑器中的场景布局导出为代码
## 由 EditorPlugin 按钮或 C4 命令触发
##
## 输出：
##   1. level_data.gd - 纯代码生成逻辑
##   2. layout_snapshot.json - 结构化数据（供 AI 读取）
##   3. 通知文件 - 告诉 AI "用户编辑完成"
@tool
extends Node

const OUTPUT_DIR := "res://levels/"
const SNAPSHOT_FILE := "res://levels/layout_snapshot.json"
const NOTIFY_FILE := "res://levels/.layout_ready"  # AI 监听此文件


## 导出当前编辑的场景
## scene_root: 场景根节点
## level_name: 关卡名称（默认从场景名获取）
## dimension_mode: "2d" or "3d"
static func export_layout(scene_root: Node, level_name: String = "", dimension_mode: String = "3d", core_base_dir: String = "") -> Dictionary:
	if level_name.is_empty():
		level_name = scene_root.name.to_snake_case()

	# 确保目录存在
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	# 解析场景中的预制体
	var _base := core_base_dir if not core_base_dir.is_empty() else "res://core/real"
	var gen_path := _base + "/prefab_tscn_generator.gd"
	var PrefabTSCNGenerator = load(gen_path) if ResourceLoader.exists(gen_path) else null
	var prefabs: Array[Dictionary] = PrefabTSCNGenerator.parse_scene_prefabs(scene_root, dimension_mode)

	if prefabs.is_empty():
		return {"success": false, "message": "No prefabs found in scene"}

	# 1. 生成代码文件
	var code_path := OUTPUT_DIR + level_name + "_data.gd"
	var code_content := _generate_level_code(level_name, prefabs, dimension_mode)
	_write_file(code_path, code_content)

	# 2. 生成 JSON 快照（供 AI 读取）
	var snapshot := {
		"level_name": level_name,
		"dimension_mode": dimension_mode,
		"exported_at": Time.get_datetime_string_from_system(),
		"prefab_count": prefabs.size(),
		"prefabs": prefabs
	}
	var json_content := JSON.stringify(snapshot, "\t")
	_write_file(SNAPSHOT_FILE, json_content)

	# 3. 创建通知文件（触发 AI 读取）
	var notify_content := "Layout exported: %s\nTime: %s\nPrefabs: %d\n" % [
		level_name,
		Time.get_datetime_string_from_system(),
		prefabs.size()
	]
	_write_file(NOTIFY_FILE, notify_content)

	print("[LayoutExporter] Exported %d prefabs to %s" % [prefabs.size(), code_path])

	return {
		"success": true,
		"level_name": level_name,
		"prefab_count": prefabs.size(),
		"code_path": code_path,
		"snapshot_path": SNAPSHOT_FILE
	}


## 生成关卡代码
static func _generate_level_code(level_name: String, prefabs: Array[Dictionary], dimension_mode: String) -> String:
	var lines: PackedStringArray = []

	lines.append("## Auto-generated level layout")
	lines.append("## Exported from Godot Editor by R.E.A.L. Layout Exporter")
	lines.append("## Level: %s" % level_name)
	lines.append("## Generated: %s" % Time.get_datetime_string_from_system())
	lines.append("extends Node")
	lines.append("")
	lines.append("")
	lines.append("func _ready() -> void:")
	lines.append("\tvar factory := get_node_or_null(\"/root/PrefabFactory\")")
	lines.append("\tif not factory:")
	lines.append("\t\tpush_error(\"[%s] PrefabFactory not found\")" % level_name)
	lines.append("\t\treturn")
	lines.append("")
	lines.append("\t_spawn_layout(factory)")
	lines.append("")
	lines.append("")
	lines.append("func _spawn_layout(factory: Node) -> void:")

	# 按预制体类型分组注释
	var current_type := ""
	for prefab in prefabs:
		var prefab_type: String = prefab.get("prefab", "unknown")
		if prefab_type != current_type:
			current_type = prefab_type
			lines.append("\t# --- %s ---" % current_type)

		var pos: Array = prefab.get("position", [0, 0, 0] if dimension_mode == "3d" else [0, 0])
		var rot = prefab.get("rotation")
		var scale = prefab.get("scale")

		# 生成创建代码
		if dimension_mode == "2d":
			var spawn_line := "\tvar node := factory.create(\"%s\", {})" % prefab_type
			lines.append(spawn_line)
			lines.append("\tnode.position = Vector2(%s, %s)" % [pos[0], pos[1]])
			if rot != null:
				lines.append("\tnode.rotation_degrees = %s" % rot)
			if scale != null:
				lines.append("\tnode.scale = Vector2(%s, %s)" % [scale[0], scale[1]])
		else:
			var spawn_line := "\tvar node := factory.create(\"%s\", {})" % prefab_type
			lines.append(spawn_line)
			lines.append("\tnode.position = Vector3(%s, %s, %s)" % [pos[0], pos[1], pos[2]])
			if rot != null:
				lines.append("\tnode.rotation_degrees = Vector3(%s, %s, %s)" % [rot[0], rot[1], rot[2]])
			if scale != null:
				lines.append("\tnode.scale = Vector3(%s, %s, %s)" % [scale[0], scale[1], scale[2]])

		lines.append("\tadd_child(node)")
		lines.append("")

	lines.append("\tprint(\"[%s] Spawned %d prefabs\")" % [level_name, prefabs.size()])

	return "\n".join(lines)


static func _write_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
	else:
		push_error("[LayoutExporter] Failed to write: %s" % path)
