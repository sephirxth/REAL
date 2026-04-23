# Observability Contract v0.1

Each `Logger` session directory now contains:

- `observability/session_manifest.json`
- `observability/timeline.jsonl`
- `observability/snapshots/<snapshot_name>.json`
- `observability/artifacts/<artifact_name>.json`

## session_manifest.json

Required fields:

- `run_id`
- `session_id`
- `dimension_mode`
- `session_dir`
- `observability_dir`
- `started_at`
- `config`
- `latest_snapshot_path`
- `latest_artifact_path`

## timeline.jsonl

Each line is one JSON object with:

- `run_id`
- `session_id`
- `tick`
- `time`
- `type`
- `data`
- `caller`

## snapshots/<snapshot_name>.json

Each capture writes one snapshot with:

- `run_id`
- `session_id`
- `trigger_summary`
- `tick`
- `time`
- `command_id`
- `probe_id`
- `context`
- `anomalies`
- `tracked_entities`
- `recent_events`
- `screenshot_path`
- `annotations`

## artifacts/<artifact_name>.json

Screenshot metadata includes:

- `run_id`
- `session_id`
- `probe_id`
- `command_id`
- `screenshot_path`
- `annotations`
- `trigger`
- `tick`
