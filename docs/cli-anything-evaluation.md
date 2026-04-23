# CLI-Anything × R.E.A.L：agent-native CLI 化评估与最小原型方案

## TL;DR（先回答三个问题）

### 1) CLI-Anything 对 R.E.A.L 最适合映射到 C1/C2/C3/C4 的哪一层？
**结论：最适合映射到 `C2`，并向下桥接 `C1/C3/C4`，而不是取代它们。**

原因：
- `C1` 是日志/状态采集层，本质是数据生产者，不该直接等同于 agent-facing CLI。
- `C3` 是视觉 grounding，本质是视觉补充层，不适合一开始就做成大而全 CLI 主界面。
- `C4` 是动作执行后端（ActionExecutor/UDP/YAML），它是“执行器”，不是“面向 agent 的工作台”。
- `CLI-Anything` 的真正价值在于：**把已有能力整理成自描述、可组合、可脚本化、对 agent 低摩擦的接口层**。这正是 `C2` 的工作。

所以，对 R.E.A.L 来说，CLI 更像：

```text
Agent
  ↓
R.E.A.L CLI Harness   ← 这里是 CLI-Anything 最适合落的位置（C2）
  ├─ inspect / summarize / oracle    → 读 C1 / C3
  └─ act / scene ops / persist       → 调 C4
```

换句话说：**CLI 不是新的 logger，也不是新的 executor；CLI 是把 R.E.A.L 的调试原语整理成 agent 可直接消费的工作界面。**

---

### 2) 哪些能力适合暴露为 CLI？
不是“全都暴露”，而是优先暴露**符合调试第一性原理 S / N / O**、且低频高价值的能力。

#### 最适合第一批 CLI 化（Yes）

| 能力 | 属于哪类 | 为什么适合 CLI | MVP? |
|---|---|---|---|
| `logs latest` / `capture list` | S | 发现最近 capture、减少 agent 先找文件的摩擦 | ✓ |
| `inspect capture` / `inspect entity` | S | 把日志转成结构化 JSON，便于 agent 推理 | ✓ |
| `oracle assert-*` | O | 让“是否符合预期”变成明确可判定命令，而不是让 LLM 纯靠读日志口头判断 | ✓ |
| `act pause/resume/capture/timescale` | N / execution | 低频、确定性强、直接对应 C4 | ✓ |
| `act set/teleport/spawn/destroy` | execution | 已有 ActionExecutor 语义，适合包装成显式命令 | ✓（部分） |
| `scene snapshot` / `scene export` | S | 导出当前 scene/entity index，利于 agent 全局理解 | 后续 |
| `persist` | execution | 把临时调试结果转成代码/配置是高价值操作，但要谨慎 | 后续 |
| `check invariant` / `check goal` | O | 面向玩法调试、冒烟测试、回归验证很有价值 | 后续 |

#### 暂时不该 CLI 化（No / Not Yet）

| 能力 | 为什么不该先做 CLI |
|---|---|
| 高频 frame-by-frame 单步调试 | LLM 是低频高延迟物种，这类操作更适合人类或引擎内调试器 |
| 复杂视觉标注编辑 | 这是 C3 的视觉/GUI 工作，不适合先做成纯 CLI |
| 任意 Godot API 暴露 | 这会把 CLI 变成“远程脚本执行器”，边界太大、风险太高 |
| 伪 replay（只有日志没有 deterministic restore） | 如果当前没有真正可恢复世界状态的后端，做 `replay` 会变成假能力 |
| 一上来做 REPL 大全套 | 现在 R.E.A.L 仓库几乎是空的，先做能力证明比先造壳子更重要 |

---

### 3) 最小可行原型应该长什么样，而不是一口气全做？
**结论：先做一个“C1/C4 桥接型 CLI”，而不是完整 CLI-Anything 大工程。**

MVP 只需要证明三件事：
1. Agent 能更快拿到结构化调试上下文（`inspect`）
2. Agent 能把判断变成可执行裁决（`oracle`）
3. Agent 能发少量、明确、可审计的动作（`act`）

建议的最小命令集：

```bash
# 发现最新 capture
python tools/real_cli.py logs latest --project <godot-project>

# 解析 capture -> JSON
python tools/real_cli.py inspect capture <path> --json

# oracle：断言某个实体字段满足预期
python tools/real_cli.py oracle assert-field <path> Player health ge 1 --json

# act：发动作到 ActionExecutor（先覆盖 4~5 个低风险动作）
python tools/real_cli.py act pause
python tools/real_cli.py act capture --reason smoke_test
python tools/real_cli.py act set Player health 100
python tools/real_cli.py act teleport Player 100 200
```

这个 MVP 已经能覆盖：
- `S`：inspect
- `O`：oracle
- `N / execution`：act

它**足够证明方向**，但又**不把仓库一次性搞复杂**。

---

## 为什么不能机械照搬 CLI-Anything
CLI-Anything 的 SOP 很强，但 R.E.A.L 不是典型“GUI 软件 → 后端 CLI 化”的场景。

CLI-Anything 的典型假设是：
1. 有 GUI 软件
2. 可以找到后端引擎/数据模型
3. 通过 CLI 包装其核心能力

而 R.E.A.L 当前的现实是：
- 它本身就是“为 LLM 调试而生”的框架概念，不是成熟 GUI 产品
- 已有的真正硬能力在 `C1`（capture/log）和 `C4`（action executor）
- 仓库当前非常轻（几乎是初始化状态）

所以 R.E.A.L 不应照着 CLI-Anything 直接生成一个：
- 大型 Python package
- REPL
- publish/install/test 全家桶

现在最合理的方式是：
**借鉴 CLI-Anything 的方法论，不照搬其产物形态。**

即借它的三个核心思想：
1. 先找已有 backend，不重复造轮子
2. 先做 inspect/info，再做 mutation
3. 输出优先结构化 JSON，方便 agent 消费

而不是先去复制一个完整 click/repl/harness 框架。

---

## 从“调试第一性原理”看 CLI 边界
你给的《调试活动的第一性原理模型》把调试压缩成三件事：

- `S` State：能看见系统状态
- `N` Navigation：能把系统带到某时某地
- `O` Oracle：能判断状态是否符合预期

R.E.A.L 的 CLI 设计，应该严格围绕这三件事：

### S：State 可观测性
CLI 值得做：
- 列出 capture
- 提取实体摘要
- 把日志转 JSON
- 做 scene/entity index

### N：Navigation / 时空定位
CLI 值得做：
- 触发 capture
- pause / resume / timescale
- teleport / spawn（低频、明确）

CLI 不值得做：
- 高频 step/continue/next（太像人类交互式调试器）

### O：Oracle / 预期裁决
CLI 非常值得做：
- assert-field
- assert-entity-exists
- assert-event-seen
- check-invariant / check-goal

原因：**Oracle 是最容易被 LLM“口头化”的部分，而 CLI 可以把它变成机器可裁决、可返回 exit code 的能力。**

---

## 建议的分阶段路线

### Phase 0（现在）
做最小桥接，不做大全套：
- `logs latest`
- `inspect capture`
- `oracle assert-field`
- `act pause/resume/capture/set/teleport`

### Phase 1（下一步，如果 MVP 证明有用）
- `inspect entity <capture> <id>`
- `oracle assert-entity-exists`
- `oracle assert-event-seen`
- `act spawn/destroy/timescale`
- 统一 `--json`

### Phase 2（等 C1/C4 真正稳定以后）
- `scene export`
- `persist`（把运行态修改写回配置/代码）
- `check smoke` / `check combat-loop` / `check progression`
- 针对游戏机制的回归检查

### Phase 3（谨慎）
只在 R.E.A.L 已经有明确的 deterministic restore / snapshot restore 基础时，再考虑：
- `replay`
- `seek`
- 更完整 REPL

---

## 当前原型落地说明
本次在仓库里落了：

- `docs/cli-anything-evaluation.md`（本文件）
- `tools/real_cli.py`
- `examples/sample_capture.log`

原型只证明方向，不宣称“已经完成 CLI-Anything 化”。

### 已覆盖
- C1 → `logs latest`, `inspect capture`
- O  → `oracle assert-field`
- C4 → `act pause/resume/capture/timescale/set/teleport`

### 故意没做
- REPL
- 复杂 scene ops
- persist
- replay
- 安装发布/package 化

这是为了保持：
- 最小目录增量
- 易回滚
- 先证明价值，再决定是否扩展

---

## 结论
**R.E.A.L 值得做 CLI 化，但不是“全量 CLI-Anything 化”，而是“围绕 S/N/O 的选择性 CLI 化”。**

最合适的位置：
- **主要落在 C2（agent-facing harness）**
- 读取 C1/C3
- 驱动 C4

最合理的第一步：
- 不做大全套
- 先做一个 inspect / oracle / act 的最小桥接 CLI

这一步完成后，才能用真实 agent 任务去验证：
- token 是否减少
- 定位是否更快
- 调试闭环是否更稳

如果验证成立，再继续向 `scene ops / persist / game-specific oracle packs` 扩展。
