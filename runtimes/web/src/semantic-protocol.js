export const BUILTIN_COMMANDS = new Set([
  'help', 'state', 'inspect', 'targets', 'target', 'snapshot', 'call', 'clear',
]);

export function tokenize(text) {
  const tokens = [];
  const pattern = /"([^"\\]*(?:\\.[^"\\]*)*)"|'([^'\\]*(?:\\.[^'\\]*)*)'|(\S+)/g;
  let match;
  while ((match = pattern.exec(text))) {
    tokens.push((match[1] ?? match[2] ?? match[3] ?? '').replace(/\\(["'\\])/g, '$1'));
  }
  return tokens;
}

export function parseCommand(input) {
  const raw = String(input ?? '').trim();
  if (!raw) return { name: '', args: [], raw };
  const args = tokenize(raw);
  return { name: args.shift() ?? '', args, raw };
}

async function runAdapterCommand(context, name, args) {
  const command = context.adapter?.commands?.[name];
  if (!command) return { ok: false, error: `Adapter command not found: ${name}` };
  return { ok: true, value: await command(context, args) };
}

async function runSnapshot(context, args) {
  const [verb, name = 'default'] = args;
  if (verb === 'save') {
    if (!context.adapter?.saveSnapshot) return { ok: false, error: 'Adapter does not support saveSnapshot' };
    return { ok: true, value: await context.adapter.saveSnapshot(name) };
  }
  if (verb === 'load') {
    if (!context.adapter?.loadSnapshot) return { ok: false, error: 'Adapter does not support loadSnapshot' };
    return { ok: true, value: await context.adapter.loadSnapshot(name) };
  }
  return { ok: false, error: 'Usage: snapshot save <name> | snapshot load <name>' };
}

export async function runParsedCommand(context, parsed) {
  const adapter = context.adapter;
  if (!parsed.name) return { ok: true, value: null };
  if (parsed.name === 'help') {
    return { ok: true, value: { builtins: [...BUILTIN_COMMANDS], adapter: Object.keys(adapter?.commands ?? {}) } };
  }
  if (parsed.name === 'state') return { ok: true, value: await adapter?.getState?.() };
  if (parsed.name === 'inspect') return { ok: true, value: await adapter?.inspect?.(parsed.args.join(' ')) };
  if (parsed.name === 'targets') {
    if (!adapter?.listTargets) return { ok: false, error: 'Adapter does not support listTargets' };
    const [tag] = parsed.args;
    return { ok: true, value: await adapter.listTargets(tag ? { tag } : {}) };
  }
  if (parsed.name === 'target') {
    if (!adapter?.selectTarget) return { ok: false, error: 'Adapter does not support selectTarget' };
    const query = parsed.args.join(' ');
    if (!query) return { ok: false, error: 'Usage: target <semantic-id|alias>' };
    return { ok: true, value: await adapter.selectTarget(query) };
  }
  if (parsed.name === 'snapshot') return runSnapshot(context, parsed.args);
  if (parsed.name === 'call') {
    const [name, ...args] = parsed.args;
    return runAdapterCommand(context, name, args);
  }
  if (parsed.name === 'clear') return { ok: true, clear: true, value: null };
  if (adapter?.commands?.[parsed.name]) return runAdapterCommand(context, parsed.name, parsed.args);
  return { ok: false, error: `Unknown command: ${parsed.name}` };
}
