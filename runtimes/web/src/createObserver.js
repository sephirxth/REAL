const SCHEMA_VERSION = 'real-observability/0.1';

const NOOP = Object.freeze({
  enabled: false,
  emit() {},
  snapshot() { return null; },
  artifact() { return null; },
  verdict() { return null; },
  end() {},
});

const rand = (n = 6) => Math.random().toString(36).slice(2, 2 + n);
const makeRunId = () => `run-${Date.now().toString(36)}-${rand()}`;
const makeSessionId = () => `sess-${Date.now().toString(36)}-${rand()}`;

function diffNumbers(previous, next, prefix = '', out = {}) {
  if (next == null || typeof next !== 'object') return out;
  for (const key of Object.keys(next)) {
    const path = prefix ? `${prefix}.${key}` : key;
    const nextValue = next[key];
    const previousValue = previous == null ? undefined : previous[key];
    if (typeof nextValue === 'number') {
      const from = typeof previousValue === 'number' ? previousValue : null;
      if (from !== nextValue) {
        out[path] = { from, to: nextValue, delta: from == null ? null : nextValue - from };
      }
    } else if (nextValue && typeof nextValue === 'object') {
      diffNumbers(previousValue, nextValue, path, out);
    }
  }
  return out;
}

export function createObserver(options = {}) {
  const { adapter, enabled = true, sink } = options;
  if (!enabled) return NOOP;
  if (!sink) throw new Error('createObserver: sink is required when enabled');
  if (!adapter || typeof adapter.observe !== 'function') {
    throw new Error('createObserver: adapter.observe() is required when enabled');
  }

  const runId = options.runId || makeRunId();
  const sessionId = options.sessionId || makeSessionId();
  const recentLimit = options.recentEvents ?? 8;
  let sequence = 0;
  let snapshotCount = 0;
  let artifactCount = 0;
  let previousState = null;
  const recentEvents = [];
  const tick = () => {
    try { return typeof adapter.tick === 'function' ? adapter.tick() : null; }
    catch { return null; }
  };

  let adapterManifest = {};
  try { adapterManifest = adapter.manifest?.() || {}; }
  catch { adapterManifest = {}; }
  const manifest = {
    run_id: runId,
    session_id: sessionId,
    build_id: adapterManifest.build_id ?? 'dev',
    content_revision: adapterManifest.content_revision ?? null,
    seed: adapterManifest.seed ?? null,
    scene: adapterManifest.scene ?? null,
    config_profile: adapterManifest.config_profile ?? null,
    platform: adapterManifest.platform ?? null,
    git_rev: options.gitRev ?? null,
    url: options.url ?? null,
    started_at: new Date().toISOString(),
    ended_at: null,
    schema_version: SCHEMA_VERSION,
  };
  sink.manifest(manifest);

  function emit(type, data = {}, ext = {}) {
    const record = {
      run_id: runId,
      session_id: sessionId,
      seq: sequence++,
      tick: tick(),
      ts: Date.now(),
      type,
      data: data || {},
      ext: ext || {},
      caller: ext?.caller || data?.caller || null,
    };
    recentEvents.push(record);
    if (recentEvents.length > recentLimit) recentEvents.shift();
    sink.event(record);
    return record;
  }

  function snapshot(trigger, metadata = {}) {
    let state;
    try { state = adapter.observe(); }
    catch (error) { state = { _error: String(error?.message || error) }; }
    const deltas = diffNumbers(previousState, state);
    previousState = state;
    const snapshotId = `snap-${String(snapshotCount++).padStart(4, '0')}-${rand(4)}`;
    const record = {
      snapshot_id: snapshotId,
      run_id: runId,
      session_id: sessionId,
      seq: sequence++,
      tick: tick(),
      ts: Date.now(),
      trigger: trigger ?? null,
      probe_id: metadata.probe_id ?? null,
      command_id: metadata.command_id ?? null,
      state,
      deltas,
      anomalies: metadata.anomalies ?? [],
      artifact_id: metadata.artifact_id ?? null,
      recent_events: recentEvents.slice(-recentLimit),
    };
    sink.snapshot(record);
    if (metadata.emitResourceDeltas !== false) {
      for (const [path, delta] of Object.entries(deltas)) {
        if (path.startsWith('resources.')) {
          emit('resource_delta', { name: path.slice(10), ...delta }, {
            caller: 'sdk:autodiff', snapshot_id: snapshotId,
          });
        }
      }
    }
    return record;
  }

  function artifact(kind, relativePath, metadata = {}) {
    const record = {
      artifact_id: metadata.artifact_id || `art-${String(artifactCount++).padStart(4, '0')}-${rand(4)}`,
      run_id: runId,
      session_id: sessionId,
      probe_id: metadata.probe_id ?? null,
      command_id: metadata.command_id ?? null,
      kind,
      path: relativePath,
      snapshot_id: metadata.snapshot_id ?? null,
      trigger: metadata.trigger ?? null,
      tick: metadata.tick ?? tick(),
      ts: Date.now(),
      annotations: metadata.annotations ?? {},
    };
    sink.artifact(record);
    return record;
  }

  function verdict(checks = [], recovery = {}) {
    const items = Array.isArray(checks) ? checks : [];
    const failed = items.filter((check) => check && !check.pass);
    const record = {
      run_id: runId,
      session_id: sessionId,
      verdict: recovery.verdict ?? (items.length === 0 ? 'inconclusive' : failed.length ? 'fail' : 'pass'),
      health: {
        build_ready: recovery.health?.build_ready ?? null,
        runtime_ready: recovery.health?.runtime_ready ?? null,
        input_ready: recovery.health?.input_ready ?? null,
        capture_ready: recovery.health?.capture_ready ?? null,
        probe_ack: recovery.health?.probe_ack ?? null,
      },
      checks: items,
      failed_checks: failed,
      evidence_refs: recovery.evidence_refs ?? [],
      recommendation: recovery.recommendation ?? '',
      recovery_cursor: recovery.recovery_cursor ?? null,
      ts: Date.now(),
    };
    sink.verdict(record);
    return record;
  }

  function end() {
    manifest.ended_at = new Date().toISOString();
    sink.manifest(manifest);
    sink.close?.();
  }

  return { enabled: true, runId, sessionId, emit, snapshot, artifact, verdict, end };
}

export default createObserver;
