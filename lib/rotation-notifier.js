'use strict';

const { execFile: defaultExecFile } = require('child_process');

// AppleScript 保持静态；账号名及提醒文案只经 argv 传入，避免 shell 注入风险。
const CONFIRM_SCRIPT = `on run argv
  try
    set answer to display dialog (item 1 of argv) with title (item 2 of argv) buttons {"稍后", "切换账号"} default button "稍后" giving up after 90
    if gave up of answer then return "timeout"
    if button returned of answer is "切换账号" then return "switch"
    return "later"
  on error errorMessage number errorNumber
    if errorNumber is -128 then return "cancelled"
    error errorMessage number errorNumber
  end try
end run`;

const GUIDE_SCRIPT = `on run argv
  try
    set answer to display dialog (item 1 of argv) with title (item 2 of argv) buttons {"稍后", "打开应用"} default button "稍后" giving up after 90
    if gave up of answer then return "timeout"
    if button returned of answer is "打开应用" then return "open"
    return "later"
  on error errorMessage number errorNumber
    if errorNumber is -128 then return "cancelled"
    error errorMessage number errorNumber
  end try
end run`;

const NOTIFY_SCRIPT = `on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run`;

function createRotationNotifier({
  execFile = defaultExecFile,
  platform = process.platform,
  openAppTarget = 'Typeless Switch',
} = {}) {
  let pending = null;

  function assertSupported() {
    if (platform === 'darwin') return;
    const error = new Error('原生账号轮动提醒仅支持 macOS，当前系统无法显示提醒。');
    error.code = 'ROTATION_NOTIFICATION_UNSUPPORTED';
    throw error;
  }

  async function confirm({ accountName, usedWords, threshold, intervalMinutes }) {
    assertSupported();
    const thresholdState = usedWords < threshold ? '接近' : '已达到';
    const message = `账号「${accountName}」本周已使用 ${usedWords} 词，${thresholdState}你设置的 ${threshold} 词轮动阈值。\n\n` +
      `应用每 ${intervalMinutes} 分钟检查一次。切换账号会重启 Typeless，请先结束当前语音输入并等待文本输出完成。\n\n` +
      '选择「稍后」可留在当前账号；90 秒未操作将自动关闭，保持当前账号。';
    return dialog(CONFIRM_SCRIPT, message, 'Typeless 账号轮动', 'switch');
  }

  async function guide({ title, message }) {
    assertSupported();
    return dialog(GUIDE_SCRIPT, String(message), String(title), 'open');
  }

  function dialog(script, message, title, action) {
    if (pending) return Promise.resolve('cancelled');
    return new Promise((resolve, reject) => {
      const request = { child: null, settled: false, finish: null, execution: 0 };
      request.finish = (error, outcome) => {
        if (request.settled) return;
        request.settled = true;
        request.child = null;
        if (pending === request) pending = null;
        if (error?.killed) resolve('timeout');
        else if (error) reject(error);
        else resolve(outcome);
      };
      pending = request;

      function execute(file, args, timeout, done) {
        const execution = ++request.execution;
        try {
          const child = execFile(file, args, {
            encoding: 'utf8', timeout, killSignal: 'SIGKILL', maxBuffer: 16384,
          }, (error, stdout) => {
            if (request.settled || execution !== request.execution) return;
            request.child = null;
            if (error) request.finish(error);
            else done(String(stdout || '').trim());
          });
          if (!request.settled && execution === request.execution) request.child = child;
        } catch (error) { request.finish(error); }
      }

      execute('/usr/bin/osascript', ['-e', script, '--', message, title], 95000, outcome => {
        if (outcome === action && action === 'open') {
          execute('/usr/bin/open', ['-a', openAppTarget], 5000, () => request.finish(null, 'opened'));
        } else {
          request.finish(null, ['later', 'timeout', 'cancelled', action].includes(outcome) ? outcome : 'timeout');
        }
      });
    });
  }

  async function notify({ title, message }) {
    assertSupported();
    return new Promise((resolve, reject) => {
      execFile('/usr/bin/osascript', ['-e', NOTIFY_SCRIPT, '--', String(title), String(message)], {
        encoding: 'utf8', timeout: 5000, killSignal: 'SIGKILL', maxBuffer: 16384,
      }, error => error ? reject(error) : resolve());
    });
  }

  function cancel() {
    if (!pending) return;
    const request = pending;
    const child = request.child;
    request.finish(null, 'cancelled');
    try { child?.kill('SIGKILL'); } catch (_) {}
  }

  return { confirm, guide, notify, cancel };
}

module.exports = { createRotationNotifier };
