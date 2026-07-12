'use strict';

const KNOWN_CODES = new Set([
  'INVALID_REQUEST',
  'UNSUPPORTED_PROTOCOL',
  'CORE_PROCESS_EXITED',
  'MANAGEMENT_CONNECTION_REQUIRED',
  'CURRENT_ACCOUNT_UNAVAILABLE',
  'CAPTURE_EXPIRED',
  'ACCOUNT_NOT_FOUND',
  'TOKEN_EXPIRED',
  'SNAPSHOT_NOT_FOUND',
  'BACKUP_INVALID',
  'BACKUP_CHANGED',
  'RESTORE_RECOVERY_REQUIRED',
  'TYPELESS_NOT_INSTALLED',
  'TYPELESS_VERSION_DRIFTED',
  'PATCH_FAILED_ROLLED_BACK',
  'PATCH_RECOVERY_REQUIRED',
  'CONFIRMATION_REQUIRED',
  'OPERATION_CONFLICT',
  'PERMISSION_DENIED',
  'NETWORK_UNAVAILABLE',
  'INTERNAL_ERROR',
]);

class CoreError extends Error {
  constructor(code, message, details = {}, options = {}) {
    super(message, options);
    this.name = 'CoreError';
    this.code = KNOWN_CODES.has(code) ? code : 'INTERNAL_ERROR';
    this.details = {
      recoverable: details.recoverable === true,
      suggested_action: typeof details.suggested_action === 'string'
        ? details.suggested_action
        : null,
      context: details.context && typeof details.context === 'object' && !Array.isArray(details.context)
        ? details.context
        : {},
    };
  }

  toWire() {
    return {
      code: this.code,
      message: this.message,
      details: this.details,
    };
  }
}

function normalizeCoreError(error) {
  if (error instanceof CoreError) return error.toWire();
  return new CoreError('INTERNAL_ERROR', '内部错误', { recoverable: false }).toWire();
}

module.exports = {
  CoreError,
  KNOWN_CODES,
  normalizeCoreError,
};
