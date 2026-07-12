'use strict';

const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const ROOT = path.resolve(__dirname, '..');
const PREPARE_SIDECAR = path.join(ROOT, 'scripts', 'prepare-sidecar.sh');
const PREPARE_NODE = path.join(ROOT, 'scripts', 'prepare-node-runtime.sh');

function temporaryDirectory(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function relativeFiles(root) {
  const files = [];
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(absolute);
      else files.push(path.relative(root, absolute));
    }
  }
  visit(root);
  return files.sort();
}

test('prepare-sidecar stages only the allowlisted runtime tree', () => {
  const destination = temporaryDirectory('typeless-sidecar-test-');
  execFileSync(PREPARE_SIDECAR, [destination], { cwd: ROOT, stdio: 'pipe' });

  assert.deepEqual(relativeFiles(destination), [
    'LICENSE',
    'lib/application-service.js',
    'lib/common.js',
    'lib/core-errors.js',
    'lib/local-api-security.js',
    'lib/operation-confirmations.js',
    'lib/patch-transaction.js',
    'lib/public-dto.js',
    'lib/runtime-data.js',
    'lib/task-runner.js',
    'sidecar/command-registry.js',
    'sidecar/main.js',
    'sidecar/protocol.js',
  ]);
});

test('prepare-node-runtime accepts an injected Darwin arm64 Node executable', () => {
  const destination = path.join(temporaryDirectory('typeless-node-test-'), 'node');
  execFileSync(PREPARE_NODE, [destination], {
    cwd: ROOT,
    env: { ...process.env, NODE_RUNTIME_PATH: process.execPath },
    stdio: 'pipe',
  });

  assert.equal(fs.statSync(destination).mode & 0o111, 0o111);
  assert.equal(execFileSync(destination, ['--version'], { encoding: 'utf8' }).trim(), process.version);
});

test('prepare-node-runtime rejects a non-Mach-O executable', () => {
  const directory = temporaryDirectory('typeless-node-invalid-');
  const fakeRuntime = path.join(directory, 'node');
  const destination = path.join(directory, 'output-node');
  fs.writeFileSync(fakeRuntime, '#!/bin/sh\necho fake\n', { mode: 0o755 });

  const result = spawnSync(PREPARE_NODE, [destination], {
    cwd: ROOT,
    env: { ...process.env, NODE_RUNTIME_PATH: fakeRuntime },
    encoding: 'utf8',
  });

  assert.notEqual(result.status, 0);
  assert.match(`${result.stdout}${result.stderr}`, /Mach-O.*arm64|arm64.*Mach-O/);
  assert.equal(fs.existsSync(destination), false);
});
