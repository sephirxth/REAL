#!/usr/bin/env python3
"""Install the current R.E.A.L. runtime into a Godot project."""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


RUNTIME_FILES = (
    "evidence_recorder.gd",
    "visual_evidence_capture.gd",
    "prefab_factory.gd",
    "prefab_tscn_generator.gd",
    "layout_exporter.gd",
    "edit_mode_controller.gd",
    "runtime_action_executor.gd",
)

AUTOLOADS = (
    ("EvidenceRecorder", "evidence_recorder.gd"),
    ("VisualEvidenceCapture", "visual_evidence_capture.gd"),
    ("PrefabFactory", "prefab_factory.gd"),
    ("EditModeController", "edit_mode_controller.gd"),
    ("RuntimeActionExecutor", "runtime_action_executor.gd"),
)


def render_project_config(text: str) -> str:
    lines = text.splitlines()
    header = "[autoload]"
    entries = [f'{name}="*res://addons/real/{filename}"' for name, filename in AUTOLOADS]
    names = {name for name, _ in AUTOLOADS}

    try:
        start = lines.index(header)
    except ValueError:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend([header, *entries, ""])
        return "\n".join(lines).rstrip() + "\n"

    end = len(lines)
    for index in range(start + 1, len(lines)):
        if lines[index].startswith("[") and lines[index].endswith("]"):
            end = index
            break

    body = []
    for line in lines[start + 1 : end]:
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key not in names:
            body.append(line)

    while body and not body[-1].strip():
        body.pop()
    replacement = [header, *body, *entries, ""]
    return "\n".join(lines[:start] + replacement + lines[end:]).rstrip() + "\n"


def install(project: Path, *, force: bool = False, dry_run: bool = False) -> list[str]:
    project = project.resolve()
    config = project / "project.godot"
    if not config.is_file():
        raise ValueError(f"not a Godot project (project.godot missing): {project}")

    repo_root = Path(__file__).resolve().parents[1]
    source_dir = repo_root / "core"
    target_dir = project / "addons" / "real"
    actions: list[str] = []

    for filename in RUNTIME_FILES:
        source = source_dir / filename
        target = target_dir / filename
        if not source.is_file():
            raise RuntimeError(f"release is incomplete: {source} is missing")
        if target.exists() and target.read_bytes() != source.read_bytes() and not force:
            raise FileExistsError(
                f"refusing to replace modified file: {target}; rerun with --force"
            )
        actions.append(f"copy {source.relative_to(repo_root)} -> {target}")

    current_config = config.read_text(encoding="utf-8")
    next_config = render_project_config(current_config)
    if next_config != current_config:
        actions.append("update project.godot [autoload]")

    if not dry_run:
        target_dir.mkdir(parents=True, exist_ok=True)
        for filename in RUNTIME_FILES:
            shutil.copy2(source_dir / filename, target_dir / filename)
        if next_config != current_config:
            config.write_text(next_config, encoding="utf-8")

    return actions


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="Godot project directory")
    parser.add_argument("--force", action="store_true", help="replace modified runtime files")
    parser.add_argument("--dry-run", action="store_true", help="show changes without writing")
    args = parser.parse_args()

    try:
        actions = install(args.project, force=args.force, dry_run=args.dry_run)
    except (ValueError, RuntimeError, FileExistsError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    prefix = "would " if args.dry_run else ""
    for action in actions:
        print(prefix + action)
    print("R.E.A.L. is ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
