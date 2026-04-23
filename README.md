# R.E.A.L. Framework

**R**eflection-**E**nabled **A**I-**L**ogging Framework for Godot 4

让游戏代码天然可被 LLM 调试的框架。

## 架构

```
[Game Engine]
      │
      ▼
[C1: Logger] ───────── 状态序列化 + 事件记录
      │
      ▼
[C2: Claude Code] ──── Glob/Grep/Read 文件检索
      │
      ▼
[C3: Visual Grounder] ─ 截图 + 实体标注
      │
      ▼
    [LLM]
      │
      ▼
[C4: Action Executor] ─ YAML 命令执行
```

## 快速开始

### 1. 复制核心文件

```bash
cp -r core/ your_project/core/
```

### 2. 配置 Autoload

在 `Project > Project Settings > Autoload` 添加：

| 名称 | 路径 | 必须 |
|------|------|------|
| Logger | `res://core/logger.gd` | ✓ |
| ActionExecutor | `res://core/action_executor.gd` | ✓ |
| PrefabFactory | `res://core/prefab_factory.gd` | 推荐 |
| VisualGrounder | `res://core/visual_grounder.gd` | 可选 |

### 3. 设置维度模式

在主场景 `_ready()` 中：

```gdscript
func _ready() -> void:
    # 2D 游戏
    Logger.set_dimension_mode("2d")
    ActionExecutor.set_dimension_mode("2d")

    # 或 3D 游戏（默认）
    # Logger.set_dimension_mode("3d")
    # ActionExecutor.set_dimension_mode("3d")
```

### 4. 注册实体

```gdscript
var player_state := {
    "type": "player",
    "position": position,
    "health": 100
}
Logger.register_entity("Player", player_state)
ActionExecutor.register_entity("Player", self, player_state)
```

### 5. 记录事件

```gdscript
Logger.log_event("Player.jumped", {"height": 5.0})
Logger.log_warn("Health.low", {"current": 10})
```

## 核心模块

### Logger (C1)

状态序列化 + 事件记录。

```gdscript
Logger.set_tick(tick)                    # 每帧调用
Logger.register_entity("id", {...})      # 注册实体
Logger.update_entity("id", {...})        # 更新状态
Logger.log_event("type", {...})          # 记录事件
Logger.capture("REASON", {...})          # 触发捕获
```

**热键**: F9 手动捕获

**日志位置**: `~/.local/share/godot/app_userdata/{project}/logs/`

### ActionExecutor (C4)

执行 LLM 生成的调试命令。

**UDP 端口**: 19999

```bash
# 修改属性
echo -e "type: set\nentity: Player\nfield: health\nvalue: 100" | nc -u localhost 19999

# 传送
echo -e "type: teleport\nentity: Player\nposition: [100, 200]" | nc -u localhost 19999

# 暂停/恢复
echo -e "type: pause" | nc -u localhost 19999
echo -e "type: resume" | nc -u localhost 19999

# 生成预制体
echo -e "type: spawn\nprefab: enemy\nposition: [0, 0]" | nc -u localhost 19999

# 持久化到代码
echo -e "type: persist\noutput: res://level_data.gd" | nc -u localhost 19999
```

### PrefabFactory

代码定义预制体。

```gdscript
# 注册
PrefabFactory.register("enemy", _make_enemy)

# 创建
var enemy = PrefabFactory.create("enemy", {"health": 100})
```

## 支持的命令

| 命令 | 用途 | 参数 |
|------|------|------|
| `set` | 修改属性 | entity, field, value |
| `teleport` | 传送实体 | entity, position |
| `spawn` | 生成预制体 | prefab, position, properties, id |
| `destroy` | 销毁实体 | entity |
| `pause` | 暂停游戏 | - |
| `resume` | 恢复游戏 | - |
| `timescale` | 时间缩放 | scale |
| `capture` | 触发日志捕获 | reason |
| `debug_collision` | 碰撞可视化 | enabled |
| `persist` | 持久化到代码 | output, exclude |
| `input_key` | 模拟键盘输入 | key, action(tap/press/release), duration |
| `input_mouse` | 模拟鼠标点击 | button(left/right/wheel_up/wheel_down), position, action(click/press/release) |
| `input_drag` | 模拟鼠标拖拽 | from, to, steps, duration |
| `input_action` | 模拟 Godot InputAction | action, pressed, strength |

### 输入模拟示例 (C4.5)

```bash
# 按键（tap = 按下+松开）
echo -e "type: input_key\nkey: Enter" | nc -u localhost 19999
echo -e "type: input_key\nkey: W\naction: press" | nc -u localhost 19999
echo -e "type: input_key\nkey: W\naction: release" | nc -u localhost 19999

# 鼠标点击
echo -e "type: input_mouse\nbutton: left\nposition: [640, 360]" | nc -u localhost 19999

# 滚轮
echo -e "type: input_mouse\nbutton: wheel_down\nposition: [640, 360]" | nc -u localhost 19999

# 拖拽（滚动条、滑块）
echo -e "type: input_drag\nfrom: [1200, 200]\nto: [1200, 500]\nsteps: 10\nduration: 0.3" | nc -u localhost 19999

# Godot InputAction
echo -e "type: input_action\naction: move_forward\npressed: true" | nc -u localhost 19999
```

## 日志格式

```
# === HEADER ===
[META] trigger="MANUAL" tick=1234 time=20.50s mode=2d
[CONFIG] gravity=980 ...

# === SNAPSHOT ===
[ENTITY] id=Player type=player state=IDLE
    | pos=(100, 200) vel=(0, 0) speed=0
    | health=100 score=500

# === HISTORY ===
[T:1200] [-0.5s] [EVENT] Player.jumped height=5
[T:1234] [NOW]   [INFO]  Trigger: MANUAL
```

## 目录结构

```
R.E.A.L/
├── core/
│   ├── logger.gd           # C1: 日志系统
│   ├── action_executor.gd  # C4: 命令执行
│   ├── visual_grounder.gd  # C3: 截图标注
│   └── prefab_factory.gd   # 预制体工厂模板
├── templates/
│   ├── godot_2d/           # 2D 项目模板
│   └── godot_3d/           # 3D 项目模板
└── README.md
```

## Web 支持

框架自动检测 Web 环境，提供 JavaScript 接口：

```javascript
Game.set("Player", "health", 100)
Game.spawn("enemy", 100, 200)
Game.pause()
Game.resume()
Game.capture("reason")
Game.help()
```

## 参考项目

- [Abyss_Headless](../Abyss_Headless/) - 3D 深海生存游戏，完整 R.E.A.L. 实现
