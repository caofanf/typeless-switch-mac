'use strict';

const crypto = require('crypto');
const { CoreError } = require('./core-errors');

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map(key => [key, canonicalValue(value[key])]),
    );
  }
  return value;
}

function canonicalJson(value) {
  return JSON.stringify(canonicalValue(value));
}

function paramsHash(params) {
  return crypto.createHash('sha256').update(canonicalJson(params)).digest('hex');
}

function confirmationError(message) {
  return new CoreError('CONFIRMATION_REQUIRED', message, {
    recoverable: true,
    suggested_action: '请重新确认操作',
  });
}

class ConfirmationStore {
  constructor({ now = Date.now, ttlMs = 120000 } = {}) {
    this.now = now;
    this.ttlMs = ttlMs;
    this.entries = new Map();
  }

  prepare(method, params, summary) {
    this.prune();
    const token = crypto.randomBytes(24).toString('base64url');
    const expiresAt = this.now() + this.ttlMs;
    this.entries.set(token, {
      method,
      paramsHash: paramsHash(params),
      summary,
      expiresAt,
      consumed: false,
    });
    return {
      confirmation_token: token,
      expires_at: expiresAt,
      summary,
    };
  }

  consume(token, method, params) {
    const entry = this.entries.get(token);
    if (!entry || entry.consumed) throw confirmationError('确认已失效，请重新确认');
    if (entry.method !== method || entry.paramsHash !== paramsHash(params)) {
      throw confirmationError('操作参数已变化，请重新确认');
    }
    if (entry.expiresAt <= this.now()) {
      this.entries.delete(token);
      throw confirmationError('确认已过期，请重新确认');
    }
    entry.consumed = true;
    return entry.summary;
  }

  prune() {
    const now = this.now();
    for (const [token, entry] of this.entries) {
      if (entry.consumed || entry.expiresAt <= now) this.entries.delete(token);
    }
  }
}

module.exports = { ConfirmationStore, canonicalJson };
