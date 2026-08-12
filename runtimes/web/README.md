# R.E.A.L. Web runtime

Dependency-free ES modules for Phaser and other browser games. This runtime combines:

- a structured timeline, semantic snapshots, numeric deltas, artifacts, and verdicts;
- a browser console bridge that automation can capture without an extra server;
- a semantic command console with a game-owned adapter;
- a Node filesystem sink for durable evidence bundles.

## Add it to a game

Copy `runtimes/web/src/` into the project, or import it directly from a checked-out R.E.A.L. repository:

```js
import {
  createBrowserSink,
  createObserver,
  installSemanticConsole,
} from './vendor/real-web/index.js';

const adapter = {
  id: 'my-phaser-game',
  manifest: () => ({ build_id: 'dev', scene: game.scene.getScenes(true)[0]?.scene.key }),
  tick: () => game.loop.frame,
  observe: () => ({
    phase: model.phase,
    resources: { gold: model.gold },
    player: { x: player.x, y: player.y, health: player.health },
  }),
  getState() { return this.observe(); },
  listTargets: ({ tag } = {}) => targetRegistry.filter((target) => !tag || target.tags.includes(tag)),
  selectTarget: (semanticId) => editor.selectBySemanticId(semanticId),
  commands: {
    'set-gold': (_context, [value]) => { model.gold = Number(value); },
    'goto-scene': (_context, [key]) => game.scene.start(key),
  },
};

const observer = createObserver({ adapter, sink: createBrowserSink() });
const debug = installSemanticConsole({ game, adapter });

observer.emit('battle_started', { enemy: 'slime' });
const snapshot = observer.snapshot('after_spawn');
observer.artifact('screenshot', 'screens/after_spawn.png', {
  snapshot_id: snapshot.snapshot_id,
});
```

The browser sink writes one-line `[REAL]` records. A Playwright probe can collect its console output and use `drainConsoleToSink(lines, createNodeSink(runDir))` to persist:

```text
observability/
├── session_manifest.json
├── timeline.jsonl
├── snapshots/*.json
├── artifacts/*.json
└── verdict.json
```

Open the console with Ctrl/Command + backtick, or call `window.__REAL_CONSOLE__.open()`. Prefer stable semantic IDs such as `ui.resource.gold.hud.value`; hierarchy names and screen coordinates are implementation details.

Disable both facilities in production builds. `createObserver({ enabled: false })` returns a static no-op implementation; only call `installSemanticConsole` behind the same development flag.

## Provenance

The observer was consolidated from the portable SDK proven in Tank Epochs. The semantic console was consolidated from the archived `phaser-debug-plugin` experiment and generalized so its protocol is not coupled to Phaser internals.
