import { parseCommand, runParsedCommand } from './semantic-protocol.js';

export function installSemanticConsole(options = {}) {
  if (typeof document === 'undefined') {
    throw new Error('installSemanticConsole must run in a browser document');
  }
  const state = {
    game: options.game ?? globalThis.game ?? null,
    adapter: options.adapter ?? {},
    history: [],
    open: Boolean(options.open),
    maxHistory: options.maxHistory ?? 200,
  };
  const ui = createPanel();
  const api = {
    state,
    open: () => setOpen(state, ui, true),
    close: () => setOpen(state, ui, false),
    toggle: () => setOpen(state, ui, !state.open),
    run: (command) => runCommand(state, ui, command),
    registerAdapter(adapter) {
      state.adapter = adapter ?? {};
      log(ui, 'adapter', adapter?.id ?? 'anonymous');
      return state.adapter;
    },
    getHistory: () => state.history.slice(),
    destroy() {
      globalThis.removeEventListener('keydown', keyHandler);
      ui.root.remove();
      if (globalThis.__REAL_CONSOLE__ === api) delete globalThis.__REAL_CONSOLE__;
    },
  };
  const keyHandler = (event) => {
    if (event.key === '`' && (event.ctrlKey || event.metaKey || options.backtickOpens)) {
      event.preventDefault();
      api.toggle();
    }
  };
  globalThis.__REAL_CONSOLE__ = api;
  globalThis.addEventListener('keydown', keyHandler);
  ui.input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      const command = ui.input.value;
      ui.input.value = '';
      api.run(command);
    } else if (event.key === 'Escape') {
      api.close();
    }
  });
  setOpen(state, ui, state.open);
  log(ui, 'ready', 'R.E.A.L. semantic console installed');
  return api;
}

async function runCommand(state, ui, command) {
  const parsed = parseCommand(command);
  const record = { at: new Date().toISOString(), command: parsed.raw };
  state.history.push(record);
  while (state.history.length > state.maxHistory) state.history.shift();
  log(ui, '>', parsed.raw);
  try {
    const result = await runParsedCommand(state, parsed);
    record.result = result;
    if (result.clear) ui.output.textContent = '';
    else log(ui, result.ok ? 'ok' : 'err', result.ok ? result.value : result.error);
    return result;
  } catch (error) {
    const result = { ok: false, error: error?.stack ?? String(error) };
    record.result = result;
    log(ui, 'err', result.error);
    return result;
  }
}

function createPanel() {
  const root = document.createElement('section');
  root.dataset.realSemanticConsole = 'true';
  Object.assign(root.style, {
    position: 'fixed', left: '12px', bottom: '12px',
    width: 'min(720px, calc(100vw - 24px))', maxHeight: '52vh',
    zIndex: 2147483647, display: 'none', flexDirection: 'column', gap: '8px',
    padding: '10px', border: '2px solid #222', borderRadius: '8px',
    background: 'rgba(16, 18, 24, 0.94)', color: '#f8fafc',
    font: '12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
    boxShadow: '0 10px 30px rgba(0,0,0,0.35)',
  });
  const title = document.createElement('div');
  title.textContent = 'R.E.A.L. SEMANTIC CONSOLE';
  title.style.fontWeight = '700';
  const output = document.createElement('pre');
  Object.assign(output.style, { margin: '0', minHeight: '120px', overflow: 'auto', whiteSpace: 'pre-wrap' });
  const input = document.createElement('input');
  input.placeholder = 'help | state | targets | target <semantic-id> | call <command>';
  Object.assign(input.style, {
    width: '100%', minHeight: '30px', border: '1px solid #475569', borderRadius: '6px',
    background: '#0f172a', color: '#f8fafc', padding: '6px 8px', font: 'inherit',
  });
  root.append(title, output, input);
  document.documentElement.appendChild(root);
  return { root, output, input };
}

function setOpen(state, ui, open) {
  state.open = open;
  ui.root.style.display = open ? 'flex' : 'none';
  if (open) ui.input.focus();
}

function log(ui, tag, value) {
  const text = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
  ui.output.textContent += `[${tag}] ${text}\n`;
  ui.output.scrollTop = ui.output.scrollHeight;
}
