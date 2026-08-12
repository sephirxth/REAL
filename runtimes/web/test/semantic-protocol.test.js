import assert from 'node:assert/strict';
import test from 'node:test';

import { parseCommand, runParsedCommand, tokenize } from '../src/semantic-protocol.js';

test('tokenizer preserves quoted semantic arguments', () => {
  assert.deepEqual(tokenize('call spawn "heavy tank" 3'), ['call', 'spawn', 'heavy tank', '3']);
});

test('semantic targets and adapter commands share one protocol', async () => {
  const selected = [];
  const adapter = {
    listTargets: ({ tag } = {}) => [{ id: 'ui.gold', tags: ['resource'], tag }],
    selectTarget: async (id) => { selected.push(id); return { id }; },
    commands: { spawn: async (_context, args) => ({ spawned: args[0] }) },
  };
  const targetResult = await runParsedCommand({ adapter }, parseCommand('target ui.gold'));
  const commandResult = await runParsedCommand({ adapter }, parseCommand('call spawn slime'));
  assert.equal(targetResult.ok, true);
  assert.deepEqual(selected, ['ui.gold']);
  assert.deepEqual(commandResult.value, { spawned: 'slime' });
});

test('unknown commands fail explicitly', async () => {
  const result = await runParsedCommand({ adapter: {} }, parseCommand('telepathy'));
  assert.equal(result.ok, false);
  assert.match(result.error, /Unknown command/);
});
