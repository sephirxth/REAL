---
name: real-implementation
description: R.E.A.L. game implementation layer for Godot 4. Use when initializing a game, implementing runtime-observable gameplay, or adding evidence and safe action interfaces for an agent or evaluator.
---

# R.E.A.L. implementation protocol

R.E.A.L. makes game code inspectable, reproducible, and controllable by an external agent. It does not replace the game engine, planner, harness, or evaluator.

## Bootstrap

Clone this repository and run:

```bash
python3 scripts/install.py /absolute/path/to/the/godot-project
```

Read the repository `README.md` completely before integrating gameplay. New projects use the evidence-oriented autoloads in `core/`; do not install `legacy/core/`.

## Required integration

1. Set the 2D/3D mode on `EvidenceRecorder`, `VisualEvidenceCapture`, `RuntimeActionExecutor`, and `EditModeController`.
2. Register every gameplay entity with a stable semantic ID in both `EvidenceRecorder` and `RuntimeActionExecutor`.
3. Update meaningful state at a stable simulation tick, not only when rendering.
4. Log domain events at the point they become true.
5. Connect `VisualEvidenceCapture` to `EvidenceRecorder` and update annotated entity positions.
6. Expose test-only methods only through `_runtime_verification_methods()`.

## Safety

- Keep runtime actions bound to `127.0.0.1`.
- Keep project-writing actions disabled unless a trusted local session explicitly sets `RUNTIME_ACTION_ALLOW_PROJECT_WRITES=1`.
- Treat screenshots, snapshots, and command results as correlated evidence; preserve run/request/probe identifiers.
- Missing evidence is not a pass.
- Do not add project-specific imports to the framework runtime. Use adapters such as `set_timescale_adapter()`.

## Completion gate

Before declaring integration complete:

- run `python3 -m unittest discover -s tests -p 'test_*.py'` in the R.E.A.L. repository;
- run its Godot smoke test with the project's intended Godot binary;
- trigger a capture in the game and verify the manifest, timeline, snapshot, artifact metadata, clean screenshot, and debug screenshot as applicable;
- execute one read-only runtime action and verify its correlated result.
