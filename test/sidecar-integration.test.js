'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const PROJECT_ROOT = path.join(__dirname, '..');
const SIDECAR_MAIN = path.join(PROJECT_ROOT, 'sidecar', 'main.js');

function waitForLine(stream, timeoutMs = 2_000) {
  return new Promise((resolve, reject) => {
    let buffer = '';
    const timer = setTimeout(() => finish(new Error('timed out waiting for sidecar output')), timeoutMs);
    const onData = chunk => {
      buffer += chunk.toString('utf8');
      const newline = buffer.indexOf('\n');
      if (newline !== -1) finish(null, buffer.slice(0, newline));
    };
    const onEnd = () => finish(new Error('sidecar output ended before a frame arrived'));
    function finish(error, value) {
      clearTimeout(timer);
      stream.off('data', onData);
      stream.off('end', onEnd);
      if (error) reject(error); else resolve(value);
    }
    stream.on('data', onData);
    stream.on('end', onEnd);
  });
}

function waitForExit(child, timeoutMs = 2_000) {
  return new Promise((resolve, reject) => {
    if (child.exitCode !== null) return resolve({ code: child.exitCode, signal: child.signalCode });
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error('sidecar did not exit in time'));
    }, timeoutMs);
    child.once('exit', (code, signal) => {
      clearTimeout(timer);
      resolve({ code, signal });
    });
  });
}

test('stdio sidecar handshakes and shuts down without mixing protocol into stderr', async t => {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'typeless-sidecar-'));
  t.after(() => fs.rmSync(dataDir, { recursive: true, force: true }));
  const child = spawn(process.execPath, [
    SIDECAR_MAIN,
    '--transport=stdio',
    `--parent-pid=${process.pid}`,
  ], {
    cwd: PROJECT_ROOT,
    env: { ...process.env, TYPELESS_DATA_DIR: dataDir, NODE_OPTIONS: '--trace-warnings' },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  t.after(() => { if (child.exitCode === null) child.kill('SIGKILL'); });
  let stderr = '';
  child.stderr.on('data', chunk => { stderr += chunk.toString('utf8'); });

  child.stdin.write('{"jsonrpc":"2.0","id":"hello","method":"core.hello","params":{}}\n');
  const hello = JSON.parse(await waitForLine(child.stdout));

  assert.equal(hello.id, 'hello');
  assert.equal(hello.result.protocol_name, 'typeless-toolkit-core');
  assert.equal(hello.result.protocol_version, '1.0');
  assert.equal(hello.result.architecture, process.arch);
  assert.equal(hello.result.capabilities.includes('accounts.list'), true);
  assert.equal(hello.result.runtime_data_path, dataDir);
  assert.equal(typeof hello.result.recovery_summary, 'object');

  child.stdin.write('{"jsonrpc":"2.0","id":"bye","method":"core.shutdown","params":{}}\n');
  const shutdown = JSON.parse(await waitForLine(child.stdout));
  assert.deepEqual(shutdown, { jsonrpc: '2.0', id: 'bye', result: { shutting_down: true } });

  assert.deepEqual(await waitForExit(child), { code: 0, signal: null });
  assert.equal(stderr.includes('"jsonrpc"'), false);
});
