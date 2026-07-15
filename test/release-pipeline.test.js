'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const ROOT = path.resolve(__dirname, '..');

test('发布 Sidecar 使用 LaunchServices 启动 Typeless', () => {
  const common = fs.readFileSync(path.join(ROOT, 'lib', 'common.js'), 'utf8');
  assert.match(common, /executable:\s*['"]\/usr\/bin\/open['"]/);
  assert.doesNotMatch(common, /spawn\(TYPELESS_BIN/);
});
