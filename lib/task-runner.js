'use strict';

const crypto = require('crypto');
const { CoreError, normalizeCoreError } = require('./core-errors');

class TaskCancelledError extends Error {
  constructor() {
    super('任务已取消');
    this.name = 'TaskCancelledError';
  }
}

function snapshot(task) {
  return {
    task_id: task.task_id,
    type: task.type,
    state: task.state,
    cancellable: task.cancellable,
    ...(task.progress ? { progress: task.progress } : {}),
    ...(task.result !== undefined ? { result: task.result } : {}),
    ...(task.error ? { error: task.error } : {}),
  };
}

class TaskContext {
  constructor(runner, task) {
    this.runner = runner;
    this.task = task;
  }

  progress(progress) {
    this.task.progress = { ...progress };
    this.runner.emitEvent('task.progress', this.task, this.task.progress);
  }

  throwIfCancelled() {
    if (this.task.cancelRequested) throw new TaskCancelledError();
  }

  setCancellable(cancellable) {
    this.task.cancellable = cancellable === true;
  }
}

class TaskRunner {
  constructor({ emit = () => {}, idFactory = () => crypto.randomUUID() } = {}) {
    this.emit = emit;
    this.idFactory = idFactory;
    this.tasks = new Map();
    this.locks = new Map();
  }

  emitEvent(method, task, fields = {}) {
    this.emit({
      method,
      params: { task_id: task.task_id, type: task.type, ...fields },
    });
  }

  start(spec, handler) {
    const resources = [...new Set(spec.resources || [])];
    for (const resource of resources) {
      const owner = this.locks.get(resource);
      if (owner) {
        throw new CoreError('OPERATION_CONFLICT', '操作与正在运行的任务冲突', {
          recoverable: true,
          suggested_action: '请等待当前任务完成',
          context: { resource, task_id: owner.task_id, type: owner.type },
        });
      }
    }

    const task = {
      task_id: this.idFactory(),
      type: spec.type,
      state: 'running',
      cancellable: spec.cancellable === true,
      cancelRequested: false,
      resources,
    };
    this.tasks.set(task.task_id, task);
    for (const resource of resources) this.locks.set(resource, task);
    this.emitEvent('task.started', task, { state: task.state, cancellable: task.cancellable });

    let outcome;
    try {
      outcome = handler(new TaskContext(this, task));
    } catch (error) {
      outcome = Promise.reject(error);
    }
    task.completion = Promise.resolve(outcome)
      .then(result => {
        task.state = 'succeeded';
        task.result = result;
        this.emitEvent('task.succeeded', task, { result });
      })
      .catch(error => {
        if (error instanceof TaskCancelledError) {
          task.state = 'cancelled';
          this.emitEvent('task.cancelled', task);
          return;
        }
        task.state = 'failed';
        task.error = normalizeCoreError(error);
        this.emitEvent('task.failed', task, { error: task.error });
      })
      .finally(() => {
        for (const resource of resources) {
          if (this.locks.get(resource) === task) this.locks.delete(resource);
        }
      })
      .then(() => snapshot(task));

    return snapshot(task);
  }

  cancel(taskId) {
    const task = this.tasks.get(taskId);
    if (!task || task.state !== 'running') return false;
    if (!task.cancellable) {
      throw new CoreError('OPERATION_CONFLICT', '任务当前不可取消', {
        recoverable: true,
        suggested_action: '请等待当前阶段完成',
        context: { task_id: taskId },
      });
    }
    task.cancelRequested = true;
    return true;
  }

  listActive() {
    return [...this.tasks.values()]
      .filter(task => task.state === 'running' || task.state === 'queued')
      .map(snapshot);
  }

  wait(taskId) {
    const task = this.tasks.get(taskId);
    if (!task) return Promise.resolve(null);
    return task.completion;
  }
}

module.exports = { TaskRunner };
