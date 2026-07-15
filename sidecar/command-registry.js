'use strict';

const { createApplicationService } = require('../lib/application-service');
const { TaskRunner } = require('../lib/task-runner');

const PROTOCOL_NAME = 'typeless-switch-core';
const PROTOCOL_VERSION = '1.0';
const CORE_VERSION = '1.0.0';

function summarizeRecoveries(core) {
  const runtime = Array.isArray(core.INITIAL_RUNTIME_RESTORE_RECOVERY)
    ? core.INITIAL_RUNTIME_RESTORE_RECOVERY
    : [];
  const patch = Array.isArray(core.INITIAL_PATCH_RECOVERY)
    ? core.INITIAL_PATCH_RECOVERY
    : [];
  return {
    runtime_restore: {
      count: runtime.length,
      actions: [...new Set(runtime.map(item => item && item.action).filter(Boolean))],
    },
    patch: {
      count: patch.length,
      statuses: [...new Set(patch.map(item => item && item.status).filter(Boolean))],
    },
    migration: core.RUNTIME_DATA?.migration?.status || 'none',
  };
}

function createCommandRegistry(options = {}) {
  const core = options.core || require('../lib/common');
  const sendNotification = options.sendNotification || (() => {});
  const onShutdown = options.onShutdown || (() => {});
  const taskRunner = options.taskRunner || new TaskRunner({
    emit: event => sendNotification({ jsonrpc: '2.0', ...event }),
  });
  const applicationService = options.applicationService || createApplicationService({ core, taskRunner });

  async function execute(method, params) {
    if (method === 'core.hello') {
      return {
        protocol_name: PROTOCOL_NAME,
        protocol_version: PROTOCOL_VERSION,
        core_version: CORE_VERSION,
        node_version: process.versions.node,
        architecture: process.arch,
        capabilities: applicationService.capabilities(),
        runtime_data_path: core.ROOT,
        recovery_summary: summarizeRecoveries(core),
      };
    }
    if (method === 'core.shutdown') {
      setImmediate(onShutdown);
      return { shutting_down: true };
    }
    return applicationService.execute(method, params);
  }

  return {
    execute,
    capabilities: applicationService.capabilities,
    applicationService,
    taskRunner,
  };
}

module.exports = {
  CORE_VERSION,
  PROTOCOL_NAME,
  PROTOCOL_VERSION,
  createCommandRegistry,
  summarizeRecoveries,
};
