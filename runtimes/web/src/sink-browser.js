const PREFIX = '[REAL] ';

function write(kind, record) {
  try {
    console.log(PREFIX + JSON.stringify({ _real: kind, record }));
  } catch (error) {
    console.log(PREFIX + JSON.stringify({
      _real: kind,
      record: { _serialize_error: String(error) },
    }));
  }
}

export function createBrowserSink() {
  return {
    manifest: (record) => write('manifest', record),
    event: (record) => write('event', record),
    snapshot: (record) => write('snapshot', record),
    artifact: (record) => write('artifact', record),
    verdict: (record) => write('verdict', record),
    close() {},
  };
}

export function parseRealLine(line) {
  if (typeof line !== 'string') return null;
  const index = line.indexOf(PREFIX);
  if (index < 0) return null;
  try {
    const payload = JSON.parse(line.slice(index + PREFIX.length));
    if (!payload || typeof payload._real !== 'string') return null;
    return { kind: payload._real, record: payload.record };
  } catch {
    return null;
  }
}

export function drainConsoleToSink(lines, sink) {
  const counts = { manifest: 0, event: 0, snapshot: 0, artifact: 0, verdict: 0 };
  for (const line of lines || []) {
    const parsed = parseRealLine(line);
    if (!parsed || !(parsed.kind in counts) || typeof sink[parsed.kind] !== 'function') continue;
    sink[parsed.kind](parsed.record);
    counts[parsed.kind] += 1;
  }
  return counts;
}

export const REAL_CONSOLE_PREFIX = PREFIX;
