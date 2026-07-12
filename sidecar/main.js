#!/usr/bin/env node
'use strict';

delete process.env.NODE_OPTIONS;

const { CoreError, normalizeCoreError } = require('../lib/core-errors');
const { JsonLineDecoder, createJsonLineSender, createRpcHandler } = require('./protocol');

const rawStdoutWrite = process.stdout.write.bind(process.stdout);
const send = createJsonLineSender(chunk => rawStdoutWrite(chunk));
console.log = (...args) => console.error(...args);

function readArgument(name) {
  const prefix = `--${name}=`;
  const value = process.argv.slice(2).find(argument => argument.startsWith(prefix));
  return value ? value.slice(prefix.length) : null;
}

function failStartup(message) {
  console.error(`[sidecar] ${message}`);
  process.exitCode = 2;
}

const transport = readArgument('transport');
const parentPid = Number.parseInt(readArgument('parent-pid') || '', 10);

if (transport !== 'stdio') {
  failStartup('only --transport=stdio is supported');
} else if (!Number.isSafeInteger(parentPid) || parentPid <= 0) {
  failStartup('--parent-pid must be a positive integer');
} else {
  start(parentPid);
}

function start(ownerPid) {
  let shuttingDown = false;
  let parentTimer = null;

  function shutdown() {
    if (shuttingDown) return;
    shuttingDown = true;
    if (parentTimer) clearInterval(parentTimer);
    process.stdin.pause();
    process.stdin.destroy();
    process.exitCode = 0;
  }

  const { createCommandRegistry } = require('./command-registry');
  const registry = createCommandRegistry({
    sendNotification: send,
    onShutdown: shutdown,
  });
  const handle = createRpcHandler({ execute: registry.execute, send });
  const decoder = new JsonLineDecoder({
    onFrame: frame => {
      handle(frame).catch(error => {
        send({ jsonrpc: '2.0', id: null, error: normalizeCoreError(error) });
      });
    },
  });

  process.stdin.on('data', chunk => {
    try {
      decoder.push(chunk);
    } catch (error) {
      const normalized = error instanceof CoreError
        ? normalizeCoreError(error)
        : normalizeCoreError(new Error('decoder failed'));
      send({ jsonrpc: '2.0', id: null, error: normalized });
    }
  });
  process.stdin.on('error', error => {
    console.error(`[sidecar] stdin error: ${error.message}`);
    shutdown();
  });
  process.stdin.on('end', shutdown);
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  parentTimer = setInterval(() => {
    try {
      process.kill(ownerPid, 0);
    } catch (error) {
      if (error.code === 'ESRCH') shutdown();
    }
  }, 2_000);
  parentTimer.unref();
  process.stdin.resume();
}
