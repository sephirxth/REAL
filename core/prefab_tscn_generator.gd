## R.E.A.L. Prefab TSCN Generator
## 从 PrefabFactory 注册表自动生成极简 .tscn 文件
## 让预制体在编辑器 FileSystem 中可见、可拖拽
##
## 使用方式：
##   1. 在编辑器中运行此脚本（@tool）
##   2. 或通过 C4 命令：type: generate_prefab_tscn
@tool
extends Node

const PREFABS_DIR := "res://prefabs/"
const SCRIPTS_DIR := "res://core/prefab_scripts/"


## 为所有注册的预制体生成极简 TSCN
## factory_registry: Dictionary of {name: factory_callable}
## dimension_mode: "2d" or "3d"
static func generate_all(factory_registry: Dictionary, dimension_mode: String = "3d") -> Dictionary:
	var results := {"success": [], "failed": []}

	# 确保目录存在
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREFABS_DIR))

	for prefab_name in factory_registry:
		var success := generate_one(prefab_name, dimension_mode)
		if success:
			results.success.append(prefab_name)
		else:
			results.failed.append(prefab_name)

	print("[PrefabTSCN] Generated %d prefabs, %d failed" % [results.success.size(), results.failed.size()])
	return results


## 生成单个预制体的极简 TSCN
static func generate_one(prefab_name: String, dimension_mode: String = "3d") -> bool:
	var tscn_path := PREFABS_DIR + prefab_name + ".tscn"
	var script_path := SCRIPTS_DIR + prefab_name + ".gd"

	# 检查脚本是否存在
	var script_exists := FileAccess.file_exists(script_path)

	# 根据维度模式选择根节点类型
	var root_type: String
	if dimension_mode == "2d":
		root_type = "Area2D"  # 默认 2D 预制体用 Area2D
	else:
		root_type = "Area3D"  # 默认 3D 预制体用 Area3D

	# 生成极简 TSCN 内容
	var content: String
	if script_exists:
		content = _make_tscn_with_script(prefab_name, root_type, script_path)
	else:
		content = _make_tscn_minimal(prefab_name, root_type)

	# 写入文件
	var file := FileAccess.open(tscn_path, FileAccess.WRITE)
	if not file:
		push_error("[PrefabTSCN] Failed to write: %s" % tscn_path)
		return false

	file.store_string(content)
	file.close()

	print("[PrefabTSCN] Generated: %s" % tscn_path)
	return true


## 生成带脚本引用的极简 TSCN
static func _make_tscn_with_script(prefab_name: String, root_type: String, script_path: String) -> String:
	# 极简 TSCN：只有根节点 + 脚本引用
	# 符合"容器哲学"：TSCN 只是容器，Script 才是灵魂
	return """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="%s" id="1_script"]

[node name="%s" type="%s"]
script = ExtResource("1_script")
""" % [script_path, prefab_name.capitalize().replace("_", ""), root_type]


## 生成无脚本的极简 TSCN（占位用）
static func _make_tscn_minimal(prefab_name: String, root_type: String) -> String:
	return """[gd_scene format=3]

[node name="%s" type="%s"]
""" % [prefab_name.capitalize().replace("_", ""), root_type]


## 从现有场景解析预制体信息（用于导出）
static func parse_scene_prefabs(scene_root: Node, dimension_mode: String = "3d") -> Array[Dictionary]:
	var prefabs: Array[Dictionary] = []

	for child in scene_root.get_children():
		# 跳过系统节点
		if child.name.begins_with("_"):
			continue

		var prefab_data := _extract_prefab_data(child, dimension_mode)
		if not prefab_data.is_empty():
			prefabs.append(prefab_data)

	return prefabs


static func _extract_prefab_data(node: Node, dimension_mode: String) -> Dictionary:
	var data := {}

	# 获取预制体类型（从脚本或节点名推断）
	var script: Script = node.get_script()
	if script:
		var script_path: String = script.resource_path
		# 从路径提取预制体名：res://core/prefab_scripts/enemy.gd -> enemy
		var prefab_name := script_path.get_file().get_basename()
		data["prefab"] = prefab_name
	else:
		# 从节点名推断：Enemy_1 -> enemy
		var node_name: String = node.name
		var base_name := node_name.split("_")[0].to_lower()
		data["prefab"] = base_name

	# 获取位置
	if dimension_mode == "2d" and node is Node2D:
		var pos := (node as Node2D).position
		data["position"] = [snapped(pos.x, 0.1), snapped(pos.y, 0.1)]
		if (node as Node2D).rotation != 0:
			data["rotation"] = snapped((node as Node2D).rotation_degrees, 0.1)
		if (node as Node2D).scale != Vector2.ONE:
			data["scale"] = [snapped((node as Node2D).scale.x, 0.01), snapped((node as Node2D).scale.y, 0.01)]
	elif dimension_mode == "3d" and node is Node3D:
		var pos := (node as Node3D).position
		data["position"] = [snapped(pos.x, 0.1), snapped(pos.y, 0.1), snapped(pos.z, 0.1)]
		if (node as Node3D).rotation != Vector3.ZERO:
			var rot := (node as Node3D).rotation_degrees
			data["rotation"] = [snapped(rot.x, 0.1), snapped(rot.y, 0.1), snapped(rot.z, 0.1)]
		if (node as Node3D).scale != Vector3.ONE:
			var s := (node as Node3D).scale
			data["scale"] = [snapped(s.x, 0.01), snapped(s.y, 0.01), snapped(s.z, 0.01)]

	return data
