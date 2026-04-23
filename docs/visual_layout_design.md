# R.E.A.L. Visual Layout System - 设计文档

## 核心场景

AI 调空间关系调不好 → 唤出 GUI → 人类微调 → AI 存储结果

## 关键洞察

**问题**：AI 用代码生成的对象不在 TSCN 里，无法在编辑器中可视化调整。

**解决**：不是"在空 TSCN 里从头拖拽"，而是：
1. AI 先用代码生成初始布局
2. 游戏运行时进入"编辑模式"
3. 用户在运行时调整位置
4. 导出修改后的布局

## 工作流

```
[AI 代码生成初始布局]
         ↓
    运行游戏
         ↓
[AI 发现空间关系不对]
         ↓
    AI 说"我调不好，请帮我调整"
    AI 发送命令：进入编辑模式
    AI 退出对话（等待）
         ↓
[游戏进入编辑模式]
    - 暂停游戏逻辑
    - 显示所有实体的 Gizmo（可拖拽手柄）
    - 用户拖拽调整位置
         ↓
[用户编辑完成]
    - 方式 A：点击游戏内"完成编辑"按钮
    - 方式 B：回到对话框告诉 AI
         ↓
[导出修改]
    - 读取当前所有实体位置
    - 生成 level_data.gd（纯代码）
    - 存储到项目记忆
         ↓
[AI 继续对话]
```

## 设计决策

### 1. 预制体 TSCN

| 决策 | 说明 |
|------|------|
| **谁生成** | AI 生成（从 PrefabFactory 注册表） |
| **用户能改吗** | 能，用户可以在编辑器中修改/微调 |
| **格式** | 极简容器（符合容器哲学） |

### 2. 编辑方式

| 方式 | 适用场景 |
|------|----------|
| **运行时编辑模式** | AI 生成的布局需要微调（主要场景） |
| **TSCN 编辑器** | 用户想从头设计布局 |

### 3. 通知 AI

| 方式 | 说明 |
|------|------|
| **游戏内按钮** | 点击"完成编辑"→ 导出布局 → 写通知文件 |
| **对话框** | 用户直接回对话框说"我调好了" |

AI 在等待编辑时退出对话，不占用资源。

## 运行时编辑模式

### 进入条件

```bash
# C4 命令
echo -e "type: edit_mode\nenabled: true" | nc -u localhost 19999
```

### 编辑模式下的功能

1. **暂停游戏逻辑**（但渲染继续）
2. **显示 Gizmo**：每个实体显示可拖拽的位置手柄
3. **选中高亮**：点击实体选中，显示属性面板
4. **拖拽移动**：直接拖拽调整位置
5. **完成按钮**：UI 上显示"完成编辑"按钮

### 退出时

1. 读取所有实体当前位置
2. 生成 `level_data.gd`
3. 写入 `layout_snapshot.json`（AI 可读）
4. 写入通知文件（可选）

## 数据流

```
PrefabFactory.create()     →  运行时实体
         ↓
    edit_mode: true
         ↓
用户拖拽调整               →  实体.position 改变
         ↓
    "完成编辑"
         ↓
LayoutExporter.export()    →  level_data.gd
                           →  layout_snapshot.json
```

## 文件结构

```
R.E.A.L/
├── core/
│   ├── prefab_factory.gd         # 预制体工厂
│   ├── prefab_tscn_generator.gd  # 生成极简 TSCN
│   ├── layout_exporter.gd        # 导出布局到代码
│   └── edit_mode_controller.gd   # 运行时编辑模式
├── addons/
│   └── real_editor/              # EditorPlugin（可选）
├── prefabs/                      # AI 生成的极简 TSCN
│   ├── enemy.tscn
│   └── ...
└── levels/
    ├── level_data.gd             # 导出的纯代码
    └── layout_snapshot.json      # AI 可读的结构化数据
```

## AI 行为规范

### 何时唤出编辑模式

- 尝试了 2-3 次代码调整但空间关系仍不对
- 用户明确说"让我来调"
- 涉及复杂的相对位置关系

### 唤出时的话术

```
我尝试调整了位置但效果不理想。
我已打开编辑模式，你可以在游戏中直接拖拽调整。
调整完成后点击"完成编辑"或回来告诉我。
```

### 读取结果

编辑完成后，AI 读取 `layout_snapshot.json` 获取：
- 每个实体的最终位置
- 用户做了哪些调整

## 已实现

1. [x] `edit_mode_controller.gd` - 运行时编辑控制器
2. [x] Gizmo 渲染（2D/3D 位置手柄）
3. [x] 游戏内 UI（Finish Editing 按钮）
4. [x] C4 命令：`edit_mode`, `export_layout`
5. [x] YAML + 代码双输出

## C4 命令用法

```bash
# 进入编辑模式
echo -e "type: edit_mode\nenabled: true" | nc -u localhost 19999

# 退出编辑模式（不导出）
echo -e "type: edit_mode\nenabled: false" | nc -u localhost 19999

# 手动导出当前布局
echo -e "type: export_layout\nlevel: my_level" | nc -u localhost 19999
```

## 输出文件

导出后生成：

```
levels/
├── layout.yaml       # YAML 格式（AI 可读）
└── layout_data.gd    # GDScript 代码
```

### YAML 格式示例

```yaml
# R.E.A.L. Layout Export
# Generated: 2024-01-01T12:00:00

level: layout
dimension: 2d
entity_count: 3

entities:
  - id: enemy_1
    prefab: enemy
    position: [100, 200]

  - id: enemy_2
    prefab: enemy
    position: [300, 200]
    rotation: 45.0

  - id: item_1
    prefab: item
    position: [200, 150]
```
