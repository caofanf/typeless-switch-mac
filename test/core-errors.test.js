'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { CoreError, normalizeCoreError } = require('../lib/core-errors');

test('CoreError exposes a stable sanitized wire shape', () => {
  const error = new CoreError('ACCOUNT_NOT_FOUND', '账号不存在', {
    recoverable: true,
    suggested_action: 'accounts.list',
    context: { user_id: 'u1' },
  });
  assert.deepEqual(error.toWire(), {
    code: 'ACCOUNT_NOT_FOUND',
    message: '账号不存在',
    details: {
      recoverable: true,
      suggested_action: 'accounts.list',
      context: { user_id: 'u1' },
    },
  });
});

test('normalizeCoreError hides unknown stack and secret-bearing fields', () => {
  const normalized = normalizeCoreError(Object.assign(new Error('boom'), { token: 'secret' }));
  assert.equal(normalized.code, 'INTERNAL_ERROR');
  assert.equal(normalized.message, '内部错误');
  assert.equal(JSON.stringify(normalized).includes('secret'), false);
});
