'use strict';

const { CoreError, normalizeCoreError } = require('../lib/core-errors');

const DEFAULT_MAX_FRAME_BYTES = 8 * 1024 * 1024;

function invalidRequest(message, context = {}) {
  return new CoreError('INVALID_REQUEST', message, {
    recoverable: true,
    context,
  });
}

class JsonLineDecoder {
  constructor({ onFrame, maxFrameBytes = DEFAULT_MAX_FRAME_BYTES } = {}) {
    if (typeof onFrame !== 'function') throw new TypeError('onFrame must be a function');
    if (!Number.isSafeInteger(maxFrameBytes) || maxFrameBytes < 1) {
      throw new TypeError('maxFrameBytes must be a positive safe integer');
    }
    this.onFrame = onFrame;
    this.maxFrameBytes = maxFrameBytes;
    this.buffer = Buffer.alloc(0);
  }

  push(chunk) {
    if (chunk == null) return;
    const incoming = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    if (incoming.length === 0) return;
    this.buffer = this.buffer.length === 0
      ? Buffer.from(incoming)
      : Buffer.concat([this.buffer, incoming]);

    while (true) {
      const newlineIndex = this.buffer.indexOf(0x0a);
      if (newlineIndex === -1) {
        if (this.buffer.length > this.maxFrameBytes) {
          this.buffer = Buffer.alloc(0);
          throw invalidRequest('协议帧超过大小限制', { max_frame_bytes: this.maxFrameBytes });
        }
        return;
      }

      if (newlineIndex > this.maxFrameBytes) {
        this.buffer = this.buffer.subarray(newlineIndex + 1);
        throw invalidRequest('协议帧超过大小限制', { max_frame_bytes: this.maxFrameBytes });
      }

      let frame = this.buffer.subarray(0, newlineIndex);
      this.buffer = this.buffer.subarray(newlineIndex + 1);
      if (frame.length > 0 && frame[frame.length - 1] === 0x0d) frame = frame.subarray(0, -1);
      if (frame.length === 0) continue;

      let value;
      try {
        value = JSON.parse(frame.toString('utf8'));
      } catch {
        throw invalidRequest('协议帧不是有效的 JSON');
      }
      this.onFrame(value);
    }
  }
}

function createJsonLineSender(write) {
  if (typeof write !== 'function') throw new TypeError('write must be a function');
  return message => write(`${JSON.stringify(message)}\n`);
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function validateRequest(request) {
  if (!isObject(request)) throw invalidRequest('请求必须是 JSON 对象');
  if (request.jsonrpc !== '2.0') throw invalidRequest('仅支持 JSON-RPC 2.0');
  if (typeof request.method !== 'string' || request.method.length === 0) {
    throw invalidRequest('请求缺少 method');
  }
  if (request.params !== undefined && !isObject(request.params) && !Array.isArray(request.params)) {
    throw invalidRequest('params 必须是对象或数组');
  }
}

function createRpcHandler({ execute, send } = {}) {
  if (typeof execute !== 'function') throw new TypeError('execute must be a function');
  if (typeof send !== 'function') throw new TypeError('send must be a function');

  return async request => {
    const hasId = isObject(request) && Object.prototype.hasOwnProperty.call(request, 'id');
    const id = hasId ? request.id : null;

    try {
      validateRequest(request);
      const result = await execute(request.method, request.params ?? {});
      if (hasId) send({ jsonrpc: '2.0', id, result });
    } catch (error) {
      if (hasId || !isObject(request) || request.jsonrpc !== '2.0' || typeof request.method !== 'string') {
        send({ jsonrpc: '2.0', id, error: normalizeCoreError(error) });
      }
    }
  };
}

module.exports = {
  DEFAULT_MAX_FRAME_BYTES,
  JsonLineDecoder,
  createJsonLineSender,
  createRpcHandler,
};
