'use strict';

const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { RuntimeDataError, initializeRuntimeData } = require('../lib/runtime-data');

const ROOT = fs.mkdtempSync(path.join(os.tmpdir(), 'tt-runtime-data-'));
const HOME = path.join(ROOT, 'home');
const CODE = path.join(ROOT, 'code');
const DEFAULT_DATA = path.join(HOME, 'Library', 'Application Support', 'Typeless Switch');

function reset() {
  fs.rmSync(HOME, { recursive: true, force: true });
  fs.rmSync(CODE, { recursive: true, force: true });
  fs.mkdirSync(HOME, { recursive: true });
  fs.mkdirSync(CODE, { recursive: true });
}

function mode(filePath) {
  return fs.statSync(filePath).mode & 0o777;
}

beforeEach(reset);
after(() => fs.rmSync(ROOT, { recursive: true, force: true }));

test('default path initializes the native Application Support directory without copying project files', () => {
  fs.writeFileSync(path.join(CODE, 'accounts.json'), '[{"id":"old-project-data"}]');

  const result = initializeRuntimeData({ codeDir: CODE, homeDir: HOME, env: {} });

  assert.strictEqual(result.dataDir, DEFAULT_DATA);
  assert.strictEqual(result.overridden, false);
  assert.deepStrictEqual(result.migration, { status: 'none' });
  assert.strictEqual(mode(DEFAULT_DATA), 0o700);
  assert.ok(!fs.existsSync(path.join(DEFAULT_DATA, 'accounts.json')));
  assert.ok(fs.existsSync(path.join(CODE, 'accounts.json')));
});

test('existing native runtime files are tightened to private permissions', () => {
  fs.mkdirSync(path.join(DEFAULT_DATA, 'profiles', 'u1'), { recursive: true, mode: 0o755 });
  fs.writeFileSync(path.join(DEFAULT_DATA, 'accounts.json'), '[]', { mode: 0o644 });
  fs.writeFileSync(path.join(DEFAULT_DATA, 'profiles', 'u1', 'state'), '{}', { mode: 0o644 });
  fs.writeFileSync(path.join(DEFAULT_DATA, 'Typeless词库主清单.csv'), 'term\n', { mode: 0o644 });

  initializeRuntimeData({ codeDir: CODE, homeDir: HOME, env: {} });

  assert.strictEqual(mode(DEFAULT_DATA), 0o700);
  assert.strictEqual(mode(path.join(DEFAULT_DATA, 'profiles')), 0o700);
  assert.strictEqual(mode(path.join(DEFAULT_DATA, 'profiles', 'u1')), 0o700);
  assert.strictEqual(mode(path.join(DEFAULT_DATA, 'accounts.json')), 0o600);
  assert.strictEqual(mode(path.join(DEFAULT_DATA, 'profiles', 'u1', 'state')), 0o600);
  assert.strictEqual(mode(path.join(DEFAULT_DATA, 'Typeless词库主清单.csv')), 0o600);
});

test('TYPELESS_DATA_DIR uses an explicit private native data directory', () => {
  const custom = path.join(ROOT, 'custom-data');
  const result = initializeRuntimeData({
    codeDir: CODE,
    homeDir: HOME,
    env: { TYPELESS_DATA_DIR: custom },
  });

  assert.strictEqual(result.dataDir, custom);
  assert.strictEqual(result.overridden, true);
  assert.deepStrictEqual(result.migration, { status: 'none' });
  assert.strictEqual(mode(custom), 0o700);
});

test('symbolic links in native runtime entries are rejected', (t) => {
  fs.mkdirSync(DEFAULT_DATA, { recursive: true });
  fs.writeFileSync(path.join(ROOT, 'outside.json'), 'secret');
  try {
    fs.symlinkSync(path.join(ROOT, 'outside.json'), path.join(DEFAULT_DATA, 'accounts.json'));
  } catch (error) {
    if (error.code === 'EPERM') return t.skip('symbolic links are unavailable');
    throw error;
  }

  assert.throws(
    () => initializeRuntimeData({ codeDir: CODE, homeDir: HOME, env: {} }),
    (error) => error instanceof RuntimeDataError && error.code === 'RUNTIME_DATA_ENTRY_UNSUPPORTED',
  );
});

test('the native runtime root itself cannot be a symbolic link', (t) => {
  const target = path.join(ROOT, 'runtime-target');
  fs.mkdirSync(target, { recursive: true });
  try {
    fs.mkdirSync(path.dirname(DEFAULT_DATA), { recursive: true });
    fs.symlinkSync(target, DEFAULT_DATA);
  } catch (error) {
    if (error.code === 'EPERM') return t.skip('symbolic links are unavailable');
    throw error;
  }

  assert.throws(
    () => initializeRuntimeData({ codeDir: CODE, homeDir: HOME, env: {} }),
    (error) => error instanceof RuntimeDataError && error.code === 'RUNTIME_DATA_PATH_INVALID',
  );
});
