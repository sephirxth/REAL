# R.E.A.L.

R.E.A.L. is a multi-runtime observability and control layer for agent-assisted game development. It makes a game inspectable, reproducible, and safely controllable by an LLM or an external evaluator. The repository currently ships a Godot 4 runtime and a dependency-free Web runtime for Phaser and other browser games.

The current release consolidates the original R.E.A.L. implementation, the evidence-oriented Godot automation pipeline, Web observability proven in Tank Epochs, the archived Phaser semantic-console experiment, and fixes proven in City Conquest Master. The original C1/C3/C4 files remain under `legacy/`; new Godot projects should use `core/`, while browser games should use `runtimes/web/`.

## What it provides

- structured sessions: manifest, JSONL timeline, snapshots, artifact metadata, and grep-friendly capture logs;
- correlated `run_id`, `request_id`, `probe_id`, and `command_id` evidence;
- clean screenshots plus separate annotated debug screenshots;
- loopback-only UDP runtime actions and a Web JavaScript bridge;
- entity read/write, teleport, spawn, destroy, pause, time scale, input injection, capture, and allowlisted method calls;
- explicit opt-in for commands that write into the project;
- runtime edit mode and layout export;
- a Web/Phaser observer, browser-to-Node evidence bridge, and semantic command console;
- a dependency-free CLI for finding, inspecting, asserting against, and acting on captures.

## Requirements

- Godot 4.4 or newer; Godot 4.6 is used by the smoke test.
- Python 3.10 or newer for the installer and CLI.
- Linux/macOS for UDP examples. The Web bridge works in exported browser builds.
- Node.js 20 or newer to run the Web runtime tests and filesystem sink.

## Install into a Phaser or browser game

The Web runtime is made of dependency-free ES modules. Copy `runtimes/web/src/` into the game, provide a thin adapter for semantic state and commands, and keep it behind a development flag:

```js
import { createBrowserSink, createObserver, installSemanticConsole } from './vendor/real-web/index.js';

const adapter = {
  observe: () => ({ phase: model.phase, resources: { gold: model.gold } }),
  tick: () => game.loop.frame,
  getState() { return this.observe(); },
  listTargets: () => targetRegistry,
  selectTarget: (id) => editor.selectBySemanticId(id),
  commands: { 'set-gold': (_context, [value]) => { model.gold = Number(value); } },
};

const observer = createObserver({ adapter, sink: createBrowserSink() });
installSemanticConsole({ game, adapter });
```

See [`runtimes/web/README.md`](runtimes/web/README.md) for the full integration and browser-to-Node persistence flow.

## Install into a new or existing Godot project

```bash
git clone https://github.com/sephirxth/REAL.git
cd REAL
python3 scripts/install.py /absolute/path/to/your-godot-project
```

The installer copies the runtime to `addons/real/` and idempotently adds these autoloads:

```ini
[autoload]
EvidenceRecorder="*res://addons/real/evidence_recorder.gd"
VisualEvidenceCapture="*res://addons/real/visual_evidence_capture.gd"
PrefabFactory="*res://addons/real/prefab_factory.gd"
EditModeController="*res://addons/real/edit_mode_controller.gd"
RuntimeActionExecutor="*res://addons/real/runtime_action_executor.gd"
```

Re-running the installer is safe. Use `--force` only when intentionally replacing locally modified R.E.A.L. files.

## Integrate the game loop

```gdscript
func _ready() -> void:
	EvidenceRecorder.set_dimension_mode("2d")
	VisualEvidenceCapture.set_dimension_mode("2d")
	RuntimeActionExecutor.set_dimension_mode("2d")
	EditModeController.set_dimension_mode("2d")

	var state := {"type": "player", "position": global_position, "health": 100}
	EvidenceRecorder.register_entity("Player", state)
	RuntimeActionExecutor.register_entity("Player", self, state)
	VisualEvidenceCapture.update_entity_position("Player", global_position, "Player")

func _physics_process(_delta: float) -> void:
	EvidenceRecorder.set_tick(Engine.get_physics_frames())
	EvidenceRecorder.update_entity("Player", {
		"position": global_position,
		"health": health,
	})
	VisualEvidenceCapture.update_entity_position("Player", global_position, "Player")
```

Connect the screenshot provider once your main scene is ready:

```gdscript
EvidenceRecorder.set_visual_evidence_capture(VisualEvidenceCapture)
```

Press `F9`, or call `EvidenceRecorder.capture("reason")`, to create evidence under:

```text
user://logs/session_<timestamp>/
├── session_manifest.json
├── observability/timeline.jsonl
├── snapshots/*.json
├── artifacts/*.json
├── trigger_*.log
├── screenshot_*.png
└── screenshot_*_debug.png
```

## Runtime actions

The native runtime listens on `127.0.0.1:19999` by default. Override the port with `RUNTIME_ACTION_UDP_PORT`. Binding to another interface requires the explicit `RUNTIME_ACTION_BIND_HOST` environment variable and is not recommended.

```bash
# Read state
printf 'type: get\nentity: Player\nfield: health\n' | nc -u -w1 127.0.0.1 19999

# Capture correlated evidence
printf 'type: capture\nreason: after_damage\nrequest_id: req-7\n' | nc -u -w1 127.0.0.1 19999

# Inject an input action
printf 'type: input_action\naction: move_right\npressed: true\n' | nc -u -w1 127.0.0.1 19999
```

`persist`, `edit_mode`, and `export_layout` are disabled by default because they write project files. Enable them only for a trusted local session:

```bash
RUNTIME_ACTION_ALLOW_PROJECT_WRITES=1 godot --path /path/to/project
```

Allowlisted method invocation uses a project-owned declaration:

```gdscript
func _runtime_verification_methods() -> Array[String]:
	return ["take_damage_for_test"]
```

## CLI

```bash
python3 tools/real_cli.py logs latest --project MyGame
python3 tools/real_cli.py inspect capture /path/to/trigger.log --json
python3 tools/real_cli.py oracle assert-field /path/to/trigger.log Player health ge 1
python3 tools/real_cli.py act capture --reason cli_probe
```

Use `python3 tools/real_cli.py --help` for the complete command tree.

## Verification

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
GODOT_BIN=/absolute/path/to/godot ./tests/test_godot_smoke.sh
npm --prefix runtimes/web test
```

The smoke test installs R.E.A.L. into a fresh temporary project and asks Godot to load it. It does not use a checked-in engine binary.

## Repository layout

```text
core/                         current Godot runtime
runtimes/web/                 Phaser/browser observer, sinks, and semantic console
scripts/install.py            idempotent project installer
tools/real_cli.py             capture/oracle/action CLI
tests/                        installer and Godot smoke tests
docs/                         contracts and design rationale
legacy/core/                  original C1/C3/C4 API
skills/real-implementation/   Agent instructions shipped with the framework
```

## Design boundary

R.E.A.L. is the in-game observability and action layer. It is not an agent orchestrator, planner, evaluator, or game engine. Pair it with a harness or evaluator that owns process lifecycle, evidence policy, and verdicts.

The observability contract is documented in [`docs/observability-contract-v0.1.md`](docs/observability-contract-v0.1.md). The six-plane model and storage tiers are documented in [`docs/observability-model.md`](docs/observability-model.md). Historical derivations are retained under `docs/archive/`.
