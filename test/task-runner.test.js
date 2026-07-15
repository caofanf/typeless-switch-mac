const test = require('node:test');
const assert = require('node:assert/strict');
const { TaskRunner } = require('../lib/task-runner');

test('task runner emits progress and terminal result', async () => {
  const events = [];
  const runner = new TaskRunner({ emit: event => events.push(event) });
  const task = runner.start({ type: 'sync', resources: ['account:u1'], cancellable: true }, async ctx => {
    ctx.progress({ phase: 'syncing', completed: 1, total: 1, message: '完成' });
    return { changed: 2 };
  });
  const result = await runner.wait(task.task_id);
  assert.equal(result.state, 'succeeded');
  assert.deepEqual(result.result, { changed: 2 });
  assert.deepEqual(events.map(event => event.method), [
    'task.started', 'task.progress', 'task.succeeded',
  ]);
});

test('resource conflicts are rejected', async () => {
  let release;
  const runner = new TaskRunner();
  runner.start({ type: 'restore', resources: ['global-write'], cancellable: false },
    () => new Promise(resolve => { release = resolve; }));
  assert.throws(() => runner.start({ type: 'patch', resources: ['global-write'] }, async () => ({})),
    error => error.code === 'OPERATION_CONFLICT');
  release({});
});
