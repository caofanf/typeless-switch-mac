'use strict';

const { test, after } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { pathToFileURL } = require('url');

const DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'tt-connection-'));
const ORIGINAL_TYPELESS_APP = process.env.TYPELESS_APP;
process.env.TYPELESS_DATA_DIR = DATA_DIR;
process.env.TYPELESS_APP = process.execPath;

const {
  CDP_PORT,
  accountMetaFromUserInfo,
  buildTypelessLaunchSpec,
  cleanupCaptureInstrumentation,
  ensureApp,
  waitForCapturedBearer,
  launchTypeless,
  selectTypelessCdpTarget,
  typelessConnectionStatus,
} = require('../lib/common');

after(() => {
  fs.rmSync(DATA_DIR, { recursive: true, force: true });
  if (ORIGINAL_TYPELESS_APP === undefined) delete process.env.TYPELESS_APP;
  else process.env.TYPELESS_APP = ORIGINAL_TYPELESS_APP;
});

test('账号捕获会等待稍后出现的授权请求', async () => {
  const attempts = [];
  let reads = 0;
  const hit = await waitForCapturedBearer(async () => {
    attempts.push('read');
    reads += 1;
    return reads < 3 ? [] : [{
      url: 'https://api.typeless.com/user/get_user_info',
      auth: 'Bearer token',
    }];
  }, {
    attempts: 3,
    pollDelayMs: 0,
    sleep: async () => attempts.push('sleep'),
  });

  assert.equal(hit.auth, 'Bearer token');
  assert.deepStrictEqual(attempts, ['read', 'sleep', 'read', 'sleep', 'read']);
});

test('账号资料中的姓名对象会归一化为 Swift 可解码的字符串', () => {
  assert.deepStrictEqual(
    accountMetaFromUserInfo({
      name: { firstName: '治凡', lastName: '曹' },
      email: 'user@example.com',
      subscription_plan_name: 'free',
    }, 'u1'),
    { email: 'user@example.com', nickname: '曹治凡', role: 'free' },
  );
});

test('账号捕获超时返回安全的阶段标识', async () => {
  await assert.rejects(
    waitForCapturedBearer(async () => [], { attempts: 2, pollDelayMs: 0, sleep: async () => {} }),
    error => error.code === 'CAPTURE_TOKEN_TIMEOUT'
      && error.message === '未在 Typeless 页面中观察到登录授权请求',
  );
});

test('账号捕获轮询有总时限,不会被单次读取无限拖延', async () => {
  await assert.rejects(
    waitForCapturedBearer(
      () => new Promise(resolve => setTimeout(() => resolve([]), 50)),
      { timeoutMs: 5, attempts: 30, pollDelayMs: 0 },
    ),
    error => error.code === 'CAPTURE_TOKEN_TIMEOUT',
  );
});

test('账号捕获完成后清除当前页面拦截器并移除后续页面注入', async () => {
  const calls = [];
  await cleanupCaptureInstrumentation(
    async (method, params) => calls.push({ method, params }),
    async expression => calls.push({ expression }),
    'capture-script-id',
  );

  assert.equal(calls[0].expression.includes('__typelessCaptureCleanup'), true);
  assert.deepStrictEqual(calls[1], {
    method: 'Page.removeScriptToEvaluateOnNewDocument',
    params: { identifier: 'capture-script-id' },
  });
});

test('Typeless 通过 LaunchServices 启动完整 app bundle', () => {
  assert.deepStrictEqual(buildTypelessLaunchSpec({
    appPath: '/Applications/Typeless.app',
    port: 9333,
  }), {
    executable: '/usr/bin/open',
    args: [
      '-n',
      '/Applications/Typeless.app',
      '--args',
      '--remote-debugging-port=9333',
    ],
  });
});

test('LaunchServices 启动参数保持数组边界且不经过 shell', () => {
  const spec = buildTypelessLaunchSpec({
    appPath: '/Applications/Typeless Preview.app',
    port: 9222,
  });
  assert.equal(spec.executable, '/usr/bin/open');
  assert.equal(spec.args[1], '/Applications/Typeless Preview.app');
  assert.equal(spec.args.includes('shell'), false);
  assert.equal(spec.args.length, 4);
});

test('缺少 Typeless app 路径时拒绝启动', () => {
  assert.throws(
    () => buildTypelessLaunchSpec({ appPath: '', port: 9222 }),
    /Typeless\.app 路径未配置/,
  );
});

test('launchTypeless 调用 open 后立即解除子进程引用', () => {
  const calls = [];
  const child = { unref: () => calls.push({ type: 'unref' }) };
  const spawnFn = (executable, args, options) => {
    calls.push({ type: 'spawn', executable, args, options });
    return child;
  };

  launchTypeless({
    appPath: '/Applications/Typeless.app',
    port: 9222,
    spawnFn,
  });

  assert.deepStrictEqual(calls, [
    {
      type: 'spawn',
      executable: '/usr/bin/open',
      args: [
        '-n',
        '/Applications/Typeless.app',
        '--args',
        '--remote-debugging-port=9222',
      ],
      options: { detached: true, stdio: 'ignore' },
    },
    { type: 'unref' },
  ]);
});

test('CDP 只接受当前 Typeless app.asar 的主窗口,不回退到任意 page', () => {
  const asarPath = '/Applications/Typeless.app/Contents/Resources/app.asar';
  const typelessUrl = pathToFileURL(asarPath).href + '/dist/renderer/hub.html';
  const targets = [
    {
      type: 'page', title: 'Typeless', url: 'https://typeless.com/',
      webSocketDebuggerUrl: `ws://127.0.0.1:${CDP_PORT}/devtools/page/chrome-tab`,
    },
    {
      type: 'page', title: 'Status', url: typelessUrl,
      webSocketDebuggerUrl: `ws://127.0.0.1:${CDP_PORT}/devtools/page/floating-bar`,
    },
    {
      type: 'page', title: 'Typeless', url: typelessUrl,
      webSocketDebuggerUrl: 'ws://evil.example/devtools/page/remote',
    },
    {
      type: 'page', title: 'Typeless', url: typelessUrl,
      webSocketDebuggerUrl: `ws://127.0.0.1:${CDP_PORT}/devtools/page/typeless`,
    },
  ];

  assert.strictEqual(
    selectTypelessCdpTarget(targets, { port: CDP_PORT, asarPath }),
    targets[3],
  );
  assert.strictEqual(
    selectTypelessCdpTarget(targets.slice(0, 3), { port: CDP_PORT, asarPath }),
    null,
  );
});

test('连接状态只区分管理端口是否可达', async () => {
  assert.deepStrictEqual(await typelessConnectionStatus({ portUp: async () => false }), {
    state: 'disconnected',
    port: CDP_PORT,
    cdp_reachable: false,
  });
  assert.deepStrictEqual(await typelessConnectionStatus({ portUp: async () => true }), {
    state: 'connected',
    port: CDP_PORT,
    cdp_reachable: true,
  });
});

test('管理端口已连接时不重启 Typeless', async () => {
  const result = await ensureApp({
    portUp: async () => true,
    killTypeless: () => assert.fail('不应关闭 Typeless'),
    launchTypeless: () => assert.fail('不应启动 Typeless'),
  });
  assert.deepStrictEqual(result, {
    state: 'connected',
    port: CDP_PORT,
    cdp_reachable: true,
    restarted: false,
  });
});

test('管理端口未连接时重启并等待端口就绪', async () => {
  let probes = 0;
  let stops = 0;
  let starts = 0;
  const result = await ensureApp({
    portUp: async () => ++probes >= 3,
    killTypeless: () => { stops++; },
    launchTypeless: () => { starts++; },
    sleep: async () => {},
    attempts: 3,
    restartDelayMs: 0,
    pollDelayMs: 0,
  });
  assert.strictEqual(stops, 1);
  assert.strictEqual(starts, 1);
  assert.strictEqual(probes, 3);
  assert.strictEqual(result.restarted, true);
  assert.strictEqual(result.cdp_reachable, true);
});

test('管理端口等待超时必须失败，不能误报已就绪', async () => {
  let probes = 0;
  let stops = 0;
  let starts = 0;
  await assert.rejects(
    ensureApp({
      portUp: async () => { probes++; return false; },
      killTypeless: () => { stops++; },
      launchTypeless: () => { starts++; },
      sleep: async () => {},
      attempts: 2,
      restartDelayMs: 0,
      pollDelayMs: 0,
    }),
    (error) => error.code === 'CDP_START_TIMEOUT' && /管理端口/.test(error.message),
  );
  assert.strictEqual(probes, 3);
  assert.strictEqual(stops, 1);
  assert.strictEqual(starts, 1);
});
