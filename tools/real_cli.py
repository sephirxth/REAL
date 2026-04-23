#!/usr/bin/env python3
"""Minimal agent-native CLI prototype for R.E.A.L.

Purpose:
- Discover latest capture logs (C1)
- Inspect a capture as structured JSON/text (C2 bridge)
- Run lightweight oracle assertions on a capture (O in S/N/O)
- Send a few controlled actions to ActionExecutor over UDP (C4)

This is intentionally minimal and dependency-free.
"""

from __future__ import annotations

import argparse
import json
import operator
import re
import socket
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


APPDATA_ROOT = Path.home() / ".local/share/godot/app_userdata"
DEFAULT_ACTION_HOST = "127.0.0.1"
DEFAULT_ACTION_PORT = 19999


@dataclass
class Event:
    tick: Optional[int] = None
    offset: Optional[str] = None
    kind: str = "INFO"
    message: str = ""
    data: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Capture:
    path: Optional[str] = None
    meta: Dict[str, Any] = field(default_factory=dict)
    config: Dict[str, Any] = field(default_factory=dict)
    entities: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    history: List[Event] = field(default_factory=list)


def parse_scalar(text: str) -> Any:
    text = text.strip()
    if text.lower() in ("true", "false"):
        return text.lower() == "true"
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d+\.\d+", text):
        return float(text)
    if text.startswith('"') and text.endswith('"'):
        return text[1:-1]
    if text.startswith("(") and text.endswith(")"):
        parts = [p.strip() for p in text[1:-1].split(",") if p.strip()]
        return [parse_scalar(p) for p in parts]
    if text.startswith("[") and text.endswith("]"):
        parts = [p.strip() for p in text[1:-1].split(",") if p.strip()]
        return [parse_scalar(p) for p in parts]
    return text


def parse_kv_blob(blob: str) -> Dict[str, Any]:
    # Parse key=value pairs while preserving tuples like pos=(1, 2)
    out: Dict[str, Any] = {}
    pattern = re.compile(r'(\w+)=((?:"[^"]*")|(?:\([^)]*\))|(?:\[[^\]]*\])|(?:[^\s]+))')
    for key, value in pattern.findall(blob):
        out[key] = parse_scalar(value)
    return out


def parse_capture_text(text: str, path: Optional[str] = None) -> Capture:
    cap = Capture(path=path)
    current_entity: Optional[str] = None

    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("[META]"):
            cap.meta.update(parse_kv_blob(line[len("[META]"):].strip()))
            current_entity = None
            continue

        if line.startswith("[CONFIG]"):
            cap.config.update(parse_kv_blob(line[len("[CONFIG]"):].strip()))
            current_entity = None
            continue

        if line.startswith("[ENTITY]"):
            data = parse_kv_blob(line[len("[ENTITY]"):].strip())
            entity_id = str(data.pop("id", ""))
            current_entity = entity_id or None
            cap.entities[entity_id] = data
            continue

        if line.strip().startswith("|") and current_entity:
            tail = line.split("|", 1)[1].strip()
            cap.entities[current_entity].update(parse_kv_blob(tail))
            continue

        evt_match = re.match(r'^\[T:(\d+)\]\s+\[([^\]]+)\]\s+\[([^\]]+)\]\s*(.*)$', line)
        if evt_match:
            tick = int(evt_match.group(1))
            offset = evt_match.group(2).strip()
            kind = evt_match.group(3).strip()
            tail = evt_match.group(4).strip()
            data = parse_kv_blob(tail)
            message = tail
            cap.history.append(Event(tick=tick, offset=offset, kind=kind, message=message, data=data))
            current_entity = None
            continue

    return cap


def parse_capture_file(path: Path) -> Capture:
    return parse_capture_text(path.read_text(encoding="utf-8"), str(path))


def capture_summary(cap: Capture) -> Dict[str, Any]:
    entity_types: Dict[str, int] = {}
    for ent in cap.entities.values():
        t = str(ent.get("type", "unknown"))
        entity_types[t] = entity_types.get(t, 0) + 1

    return {
        "path": cap.path,
        "meta": cap.meta,
        "config": cap.config,
        "entity_count": len(cap.entities),
        "entity_types": entity_types,
        "entities": cap.entities,
        "history_count": len(cap.history),
        "history": [asdict(h) for h in cap.history],
    }


def print_json(data: Any) -> None:
    print(json.dumps(data, ensure_ascii=False, indent=2))


def find_latest_capture(project: Optional[str] = None, logs_dir: Optional[str] = None) -> Optional[Path]:
    if logs_dir:
        root = Path(logs_dir).expanduser()
    elif project:
        root = APPDATA_ROOT / project / "logs"
    else:
        root = APPDATA_ROOT

    if not root.exists():
        return None

    candidates: List[Path] = []
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in (".log", ".txt", ".real"):
            candidates.append(p)

    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


OPS = {
    "eq": operator.eq,
    "ne": operator.ne,
    "gt": operator.gt,
    "ge": operator.ge,
    "lt": operator.lt,
    "le": operator.le,
    "contains": lambda a, b: b in a if isinstance(a, (str, list, tuple, dict)) else False,
}


def resolve_field(cap: Capture, entity: str, field_name: str) -> Any:
    if entity not in cap.entities:
        raise KeyError(f"entity not found: {entity}")
    ent = cap.entities[entity]
    if field_name not in ent:
        raise KeyError(f"field not found: {entity}.{field_name}")
    return ent[field_name]


def yaml_scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(yaml_scalar(v) for v in value) + "]"
    s = str(value)
    # simple quote if needed
    if any(ch in s for ch in [":", "#", "\n", '"']):
        s = s.replace('"', '\\"')
        return f'"{s}"'
    return s


def make_action_payload(args: argparse.Namespace) -> str:
    if args.action_name in ("pause", "resume"):
        return f"type: {args.action_name}\n"
    if args.action_name == "capture":
        return "\n".join([
            "type: capture",
            f"reason: {yaml_scalar(args.reason or 'CLI_CAPTURE')}",
            "",
        ])
    if args.action_name == "timescale":
        return "\n".join([
            "type: timescale",
            f"scale: {yaml_scalar(args.scale)}",
            "",
        ])
    if args.action_name == "set":
        return "\n".join([
            "type: set",
            f"entity: {yaml_scalar(args.entity)}",
            f"field: {yaml_scalar(args.field)}",
            f"value: {yaml_scalar(parse_scalar(args.value))}",
            "",
        ])
    if args.action_name == "teleport":
        position = [parse_scalar(args.x), parse_scalar(args.y)] if args.z is None else [parse_scalar(args.x), parse_scalar(args.y), parse_scalar(args.z)]
        return "\n".join([
            "type: teleport",
            f"entity: {yaml_scalar(args.entity)}",
            f"position: {yaml_scalar(position)}",
            "",
        ])
    raise ValueError(f"unsupported action: {args.action_name}")


def send_udp(host: str, port: int, payload: str) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.sendto(payload.encode("utf-8"), (host, port))
    finally:
        sock.close()


def cmd_logs_latest(args: argparse.Namespace) -> int:
    p = find_latest_capture(project=args.project, logs_dir=args.logs_dir)
    if not p:
        print_json({"ok": False, "error": "no capture found"}) if args.json else print("No capture found.")
        return 1
    if args.json:
        print_json({"ok": True, "path": str(p)})
    else:
        print(p)
    return 0


def cmd_inspect_capture(args: argparse.Namespace) -> int:
    p = Path(args.path)
    cap = parse_capture_file(p)
    summary = capture_summary(cap)
    if args.json:
        print_json(summary)
    else:
        print(f"Capture: {summary['path']}")
        print(f"Meta: {summary['meta']}")
        print(f"Entities: {summary['entity_count']} {summary['entity_types']}")
        print(f"History: {summary['history_count']}")
        for entity_id, ent in summary['entities'].items():
            print(f"- {entity_id}: {ent}")
    return 0


def cmd_oracle_assert_field(args: argparse.Namespace) -> int:
    cap = parse_capture_file(Path(args.path))
    actual = resolve_field(cap, args.entity, args.field)
    expected = parse_scalar(args.value)
    op = OPS[args.op]
    passed = op(actual, expected)
    payload = {
        "ok": passed,
        "entity": args.entity,
        "field": args.field,
        "op": args.op,
        "actual": actual,
        "expected": expected,
        "path": args.path,
    }
    if args.json:
        print_json(payload)
    else:
        print(("PASS" if passed else "FAIL") + f" {args.entity}.{args.field} {args.op} {expected} (actual={actual})")
    return 0 if passed else 2


def cmd_act(args: argparse.Namespace) -> int:
    payload = make_action_payload(args)
    if args.dry_run or args.json:
        data = {
            "ok": True,
            "host": args.host,
            "port": args.port,
            "payload": payload,
            "sent": not args.dry_run,
        }
        if args.json:
            print_json(data)
        else:
            print(payload)
    if not args.dry_run:
        send_udp(args.host, args.port, payload)
        if not args.json:
            print(f"Sent to udp://{args.host}:{args.port}")
    return 0


def add_json_flag(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--json", action="store_true", help="output JSON where applicable")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="real", description="Minimal agent-native CLI for R.E.A.L")
    add_json_flag(p)

    sub = p.add_subparsers(dest="cmd", required=True)

    logs = sub.add_parser("logs", help="discover capture logs")
    add_json_flag(logs)
    logs_sub = logs.add_subparsers(dest="logs_cmd", required=True)
    latest = logs_sub.add_parser("latest", help="print latest capture file")
    add_json_flag(latest)
    latest.add_argument("--project", help="Godot app_userdata project name")
    latest.add_argument("--logs-dir", help="override logs directory")
    latest.set_defaults(func=cmd_logs_latest)

    inspect_p = sub.add_parser("inspect", help="inspect captures")
    add_json_flag(inspect_p)
    inspect_sub = inspect_p.add_subparsers(dest="inspect_cmd", required=True)
    inspect_cap = inspect_sub.add_parser("capture", help="parse a capture file")
    add_json_flag(inspect_cap)
    inspect_cap.add_argument("path")
    inspect_cap.set_defaults(func=cmd_inspect_capture)

    oracle = sub.add_parser("oracle", help="run lightweight checks on captures")
    add_json_flag(oracle)
    oracle_sub = oracle.add_subparsers(dest="oracle_cmd", required=True)
    assert_field = oracle_sub.add_parser("assert-field", help="assert entity.field against a value")
    add_json_flag(assert_field)
    assert_field.add_argument("path")
    assert_field.add_argument("entity")
    assert_field.add_argument("field")
    assert_field.add_argument("op", choices=sorted(OPS.keys()))
    assert_field.add_argument("value")
    assert_field.set_defaults(func=cmd_oracle_assert_field)

    act = sub.add_parser("act", help="send controlled actions to ActionExecutor over UDP")
    add_json_flag(act)
    act.add_argument("--host", default=DEFAULT_ACTION_HOST)
    act.add_argument("--port", type=int, default=DEFAULT_ACTION_PORT)
    act.add_argument("--dry-run", action="store_true")
    act_sub = act.add_subparsers(dest="action_name", required=True)

    pause = act_sub.add_parser("pause")
    add_json_flag(pause)
    pause.add_argument("--dry-run", action="store_true")
    pause.set_defaults(func=cmd_act)
    resume = act_sub.add_parser("resume")
    add_json_flag(resume)
    resume.add_argument("--dry-run", action="store_true")
    resume.set_defaults(func=cmd_act)

    capture = act_sub.add_parser("capture")
    add_json_flag(capture)
    capture.add_argument("--dry-run", action="store_true")
    capture.add_argument("--reason", default="CLI_CAPTURE")
    capture.set_defaults(func=cmd_act)

    timescale = act_sub.add_parser("timescale")
    add_json_flag(timescale)
    timescale.add_argument("--dry-run", action="store_true")
    timescale.add_argument("scale")
    timescale.set_defaults(func=cmd_act)

    set_cmd = act_sub.add_parser("set")
    add_json_flag(set_cmd)
    set_cmd.add_argument("--dry-run", action="store_true")
    set_cmd.add_argument("entity")
    set_cmd.add_argument("field")
    set_cmd.add_argument("value")
    set_cmd.set_defaults(func=cmd_act)

    teleport = act_sub.add_parser("teleport")
    add_json_flag(teleport)
    teleport.add_argument("--dry-run", action="store_true")
    teleport.add_argument("entity")
    teleport.add_argument("x")
    teleport.add_argument("y")
    teleport.add_argument("z", nargs="?")
    teleport.set_defaults(func=cmd_act)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
