'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { makeRotationIssue } = require('../lib/rotation-issues');
const {
  DEFAULT_ROTATION_SETTINGS,
  validateRotationSettings,
  createAccountRotation,
} = require('../lib/account-rotation');
const {
  publicRotationSettings,
  publicRotationStatus,
  publicRotationIssue,
} = require('../lib/public-dto');

const settings = changes => ({ ...DEFAULT_ROTATION_SETTINGS, enabled: true, ...changes });

function harness({
  saved = null,
  usage = 0,
  accounts = [{ user_id: 'a', nickname: 'Account A' }, { user_id: 'b', nickname: 'Account B' }],
} = {}) {
  let timestamp = Date.UTC(2026, 8, 24);
  let timerId = 0;
  let persisted = structuredClone(saved);
  const timers = new Map();
  const calls = { usage: [], rotations: [], confirmations: [], notifications: [], guides: [], saves: [], cancels: 0 };
  const state = {
    accounts,
    currentId: 'a',
    usage,
    busy: false,
    saveError: null,
    readUsage: async () => ({ week_word_usage_value: state.usage, week_word_usage_limit: 5000 }),
    confirm: async () => 'switch',
    guide: async () => 'opened',
    notify: async () => {},
    rotate: async () => {
      state.currentId = 'b';
      return { switched: true, user_id: 'b', message: '已切换到 Account B' };
    },
  };
  const deps = {
    store: {
      load: () => structuredClone(persisted),
      save(value) {
        if (state.saveError) throw state.saveError;
        persisted = structuredClone(value);
        calls.saves.push(structuredClone(value));
      },
    },
    readAccounts: () => state.accounts,
    readCurrentAccountId: async () => state.currentId,
    readUsage: async account => {
      calls.usage.push(account.user_id);
      return state.readUsage(account);
    },
    isBusy: () => state.busy,
    rotate: async options => {
      calls.rotations.push(options);
      return state.rotate(options);
    },
    notifier: {
      confirm: async value => {
        calls.confirmations.push(value);
        return state.confirm(value);
      },
      notify: async value => {
        calls.notifications.push(value);
        return state.notify(value);
      },
      guide: async value => {
        calls.guides.push(value);
        return state.guide(value);
      },
      cancel: () => {
        calls.cancels++;
      },
    },
    now: () => timestamp,
    setTimer(callback, delay) {
      const id = ++timerId;
      timers.set(id, { callback, due: timestamp + delay, delay });
      return id;
    },
    clearTimer(id) {
      timers.delete(id);
    },
  };
  const rotation = createAccountRotation(deps);
  return {
    rotation,
    deps,
    state,
    calls,
    timers,
    get persisted() {
      return structuredClone(persisted);
    },
    async tick() {
      assert.equal(timers.size, 1, '每次等待期间只有一个轮询 timer');
      const [id, timer] = [...timers][0];
      timers.delete(id);
      timestamp = timer.due;
      timer.callback();
      await new Promise(resolve => setImmediate(resolve));
    },
  };
}

test('validateRotationSettings 接受合法的设置并拒绝非法数值', () => {
  const valid = validateRotationSettings({
    enabled: true,
    mode: 'auto',
    word_threshold: 2500,
    warning_words: 200,
    interval_minutes: 30,
  });
  assert.deepEqual(valid, {
    enabled: true,
    mode: 'auto',
    word_threshold: 2500,
    warning_words: 200,
    interval_minutes: 30,
  });

  assert.throws(() => validateRotationSettings({ enabled: true, mode: 'invalid' }));
  assert.throws(() => validateRotationSettings({ enabled: true, word_threshold: 0 }));
  assert.throws(() => validateRotationSettings({ enabled: true, warning_words: 3000, word_threshold: 2000 }));
  assert.throws(() => validateRotationSettings({ enabled: true, interval_minutes: 20 }));
});

test('未达到提醒线时不触发切号与弹窗', async () => {
  const h = harness({ usage: 1000 });
  h.rotation.start();
  h.rotation.configure(settings({ word_threshold: 2000, warning_words: 100 }));
  await h.tick();

  const view = h.rotation.view();
  assert.equal(view.status.phase, 'waiting');
  assert.equal(view.status.used_words, 1000);
  assert.equal(h.calls.confirmations.length, 0);
  assert.equal(h.calls.rotations.length, 0);
});

test('达到提醒线时在 notify 模式下确认并完成切号', async () => {
  const h = harness({ usage: 1950 });
  h.rotation.start();
  h.rotation.configure(settings({ mode: 'notify', word_threshold: 2000, warning_words: 100 }));
  await h.tick();

  assert.equal(h.calls.confirmations.length, 1);
  assert.equal(h.calls.confirmations[0].usedWords, 1950);
  assert.equal(h.calls.rotations.length, 1);
  assert.equal(h.calls.notifications.length, 1);
  assert.equal(h.rotation.view().status.current_user_id, 'b');
});

test('达到阈值时在 auto 模式下直接切号且不弹确认框', async () => {
  const h = harness({ usage: 2005 });
  h.rotation.start();
  h.rotation.configure(settings({ mode: 'auto', word_threshold: 2000, warning_words: 100 }));
  await h.tick();

  assert.equal(h.calls.confirmations.length, 0);
  assert.equal(h.calls.rotations.length, 1);
  assert.equal(h.calls.notifications.length, 1);
  assert.equal(h.rotation.view().status.current_user_id, 'b');
});

test('DTO 转换器安全过滤并结构化下发', () => {
  const settingsDto = publicRotationSettings({
    enabled: true,
    mode: 'auto',
    word_threshold: 3000,
    warning_words: 150,
    interval_minutes: 10,
    unknown_secret: 'leaked',
  });
  assert.deepEqual(settingsDto, {
    enabled: true,
    mode: 'auto',
    word_threshold: 3000,
    warning_words: 150,
    interval_minutes: 10,
  });

  const statusDto = publicRotationStatus({
    phase: 'waiting',
    message: '正常检查',
    used_words: 1500,
    issue: makeRotationIssue('NO_AVAILABLE_ACCOUNTS'),
    token: 'should_not_leak',
  });
  assert.equal(statusDto.phase, 'waiting');
  assert.equal(statusDto.used_words, 1500);
  assert.equal(statusDto.issue.code, 'NO_AVAILABLE_ACCOUNTS');
  assert.equal(statusDto.token, undefined);
});
