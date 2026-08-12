import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { createObserver } from '../src/createObserver.js';
import { createNodeSink } from '../src/sink-node.js';

function memorySink() {
  const records = { manifests: [], events: [], snapshots: [], artifacts: [], verdicts: [] };
  return {
    records,
    manifest: (value) => records.manifests.push(structuredClone(value)),
    event: (value) => records.events.push(value),
    snapshot: (value) => records.snapshots.push(value),
    artifact: (value) => records.artifacts.push(value),
    verdict: (value) => records.verdicts.push(value),
    close() {},
  };
}

test('observer correlates timeline, snapshots, deltas, artifacts, and verdict', () => {
  const sink = memorySink();
  const model = { tick: 4, gold: 10 };
  const observer = createObserver({
    runId: 'run-test',
    sessionId: 'session-test',
    sink,
    adapter: {
      manifest: () => ({ build_id: 'fixture', seed: 7, scene: 'battle' }),
      tick: () => model.tick,
      observe: () => ({ resources: { gold: model.gold } }),
    },
  });

  observer.emit('battle_started', { enemy: 'slime' });
  observer.snapshot('initial');
  model.tick += 1;
  model.gold = 13;
  const snapshot = observer.snapshot('reward');
  const artifact = observer.artifact('screenshot', 'screens/reward.png', { snapshot_id: snapshot.snapshot_id });
  const verdict = observer.verdict([{ id: 'gold-increased', pass: true }], { evidence_refs: [artifact.artifact_id] });
  observer.end();

  assert.equal(snapshot.deltas['resources.gold'].delta, 3);
  assert.equal(sink.records.events.at(-1).type, 'resource_delta');
  assert.equal(artifact.snapshot_id, snapshot.snapshot_id);
  assert.equal(verdict.verdict, 'pass');
  assert.equal(sink.records.manifests.at(-1).ended_at !== null, true);
});

test('disabled observer is a no-op without adapter or sink', () => {
  const observer = createObserver({ enabled: false });
  assert.equal(observer.enabled, false);
  assert.equal(observer.snapshot('ignored'), null);
});

test('node sink creates the canonical evidence bundle', () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'real-web-'));
  const sink = createNodeSink(temporary);
  sink.manifest({ run_id: 'run-test' });
  sink.event({ type: 'ready' });
  sink.snapshot({ snapshot_id: 'snap-1' });
  sink.artifact({ artifact_id: 'art-1' });
  sink.verdict({ verdict: 'pass' });
  assert.equal(fs.existsSync(path.join(sink.directory, 'session_manifest.json')), true);
  assert.equal(fs.existsSync(path.join(sink.directory, 'timeline.jsonl')), true);
  assert.equal(fs.existsSync(path.join(sink.directory, 'snapshots', 'snap-1.json')), true);
  assert.equal(fs.existsSync(path.join(sink.directory, 'artifacts', 'art-1.json')), true);
  assert.equal(fs.existsSync(path.join(sink.directory, 'verdict.json')), true);
});
