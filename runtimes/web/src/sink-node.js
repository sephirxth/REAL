import fs from 'node:fs';
import path from 'node:path';

export function createNodeSink(runDirectory) {
  const directory = path.join(runDirectory, 'observability');
  const snapshotDirectory = path.join(directory, 'snapshots');
  const artifactDirectory = path.join(directory, 'artifacts');
  fs.mkdirSync(snapshotDirectory, { recursive: true });
  fs.mkdirSync(artifactDirectory, { recursive: true });
  const timelinePath = path.join(directory, 'timeline.jsonl');
  fs.writeFileSync(timelinePath, '');

  return {
    directory,
    manifest: (record) => fs.writeFileSync(path.join(directory, 'session_manifest.json'), JSON.stringify(record, null, 2)),
    event: (record) => fs.appendFileSync(timelinePath, `${JSON.stringify(record)}\n`),
    snapshot: (record) => fs.writeFileSync(path.join(snapshotDirectory, `${record.snapshot_id}.json`), JSON.stringify(record, null, 2)),
    artifact: (record) => fs.writeFileSync(path.join(artifactDirectory, `${record.artifact_id}.json`), JSON.stringify(record, null, 2)),
    verdict: (record) => fs.writeFileSync(path.join(directory, 'verdict.json'), JSON.stringify(record, null, 2)),
    close() {},
  };
}
