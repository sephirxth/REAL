export { createObserver } from './createObserver.js';
export { createBrowserSink, drainConsoleToSink, parseRealLine, REAL_CONSOLE_PREFIX } from './sink-browser.js';
export { createNodeSink } from './sink-node.js';
export { installSemanticConsole } from './semantic-console.js';
export { parseCommand, runParsedCommand } from './semantic-protocol.js';
