# 2026-08-12 source consolidation

This release was assembled from the following local lines of development:

| Source | Contribution retained |
|---|---|
| `/home/youyuan/GAME_AI/R.E.A.L` | original repository history, CLI, observability contract, layout tooling, prefab factory, and legacy C1/C3/C4 API |
| `infra/godot-pipeline/runtime/real` | evidence-oriented naming, session manifest, JSONL timeline, correlated identifiers, configurable loopback runtime endpoint, project-write opt-in, clean/debug screenshot split, and project-neutral time adapter |
| `games/city-conquest-master/replica-godot/runtime/real` | logical-viewport input dispatch, high-DPI annotation scaling, and structured method return compatibility |
| `games/beast-road/real` | byte-for-byte confirmation of the original core copy; no unique implementation changes |
| uncommitted `core/edit_mode_controller.gd` fix in the original repository | explicit `String` inference for the optional 2D gizmo script path |

The consolidation also removed project-specific cognition and screen-manager behavior from the runtime executor. Projects can supply generic `_runtime_get_field` / `_runtime_set_field`, pause, and time-scale adapters instead.

The original API is preserved in `legacy/core/` for archaeology and migrations. It is not installed into new projects.

No engine binary is part of the release. The smoke test accepts an external `GODOT_BIN` and was verified with Godot 4.6 stable.
