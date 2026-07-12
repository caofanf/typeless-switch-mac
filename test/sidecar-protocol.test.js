'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { CoreError } = require('../lib/core-errors');
const {
  JsonLineDecoder,
  createJsonLineSender,
  createRpcHandler,
} = require('../sidecar/protocol');

test('decoder handles split and multiple frames while ignoring empty lines', () => {
  const frames = [];
  const decoder = new JsonLineDecoder({ onFrame: value => frames.push(value) });

  decoder.push(Buffer.from('{"id":"1"'));
  decoder.push(Buffer.from('}\n\n{"id":"2"}\n'));

  assert.deepEqual(frames, [{ id: '1' }, { id: '2' }]);
});

test('decoder rejects malformed JSON with a stable error', () => {
  const decoder = new JsonLineDecoder({ onFrame: () => {} });

  assert.throws(
    () => decoder.push(Buffer.from('{broken}\n')),
    error => error instanceof CoreError
      && error.code === 'INVALID_REQUEST'
      && !error.message.includes('broken'),
  );
});

test('decoder rejects a frame over its byte limit before or at a newline', () => {
  const withoutNewline = new JsonLineDecoder({ maxFrameBytes: 4, onFrame: () => {} });
  assert.throws(() => withoutNewline.push(Buffer.from('12345')), { code: 'INVALID_REQUEST' });

  const withNewline = new JsonLineDecoder({ maxFrameBytes: 4, onFrame: () => {} });
  assert.throws(() => withNewline.push(Buffer.from('12345\n')), { code: 'INVALID_REQUEST' });
});

test('JSON line sender writes exactly one serialized line', () => {
  const writes = [];
  const send = createJsonLineSender(chunk => writes.push(chunk));

  send({ jsonrpc: '2.0', id: '1', result: { ok: true } });

  assert.deepEqual(writes, ['{"jsonrpc":"2.0","id":"1","result":{"ok":true}}\n']);
});

test('rpc handler returns a standard success response', async () => {
  const output = [];
  const calls = [];
  const handle = createRpcHandler({
    execute: async (method, params) => {
      calls.push({ method, params });
      return { ok: true };
    },
    send: message => output.push(message),
  });

  await handle({ jsonrpc: '2.0', id: '1', method: 'status.get', params: { fresh: true } });

  assert.deepEqual(calls, [{ method: 'status.get', params: { fresh: true } }]);
  assert.deepEqual(output, [{ jsonrpc: '2.0', id: '1', result: { ok: true } }]);
});

test('rpc handler returns normalized errors without leaking internals', async () => {
  const output = [];
  const handle = createRpcHandler({
    execute: async () => { throw new Error('secret internals'); },
    send: message => output.push(message),
  });

  await handle({ jsonrpc: '2.0', id: '1', method: 'x', params: {} });

  assert.equal(output[0].error.code, 'INTERNAL_ERROR');
  assert.equal(JSON.stringify(output[0]).includes('secret internals'), false);
});

test('rpc handler rejects invalid requests with a null correlation id', async () => {
  const output = [];
  const handle = createRpcHandler({ execute: async () => null, send: value => output.push(value) });

  await handle({ jsonrpc: '1.0', id: 'bad', params: {} });
  await handle([]);

  assert.equal(output.length, 2);
  assert.deepEqual(output.map(value => value.id), ['bad', null]);
  assert.deepEqual(output.map(value => value.error.code), ['INVALID_REQUEST', 'INVALID_REQUEST']);
});

test('rpc handler executes notifications without sending result or error responses', async () => {
  const output = [];
  const methods = [];
  const handle = createRpcHandler({
    execute: async method => {
      methods.push(method);
      if (method === 'failing.event') throw new Error('not public');
      return { ignored: true };
    },
    send: value => output.push(value),
  });

  await handle({ jsonrpc: '2.0', method: 'event.received', params: {} });
  await handle({ jsonrpc: '2.0', method: 'failing.event', params: {} });

  assert.deepEqual(methods, ['event.received', 'failing.event']);
  assert.deepEqual(output, []);
});
