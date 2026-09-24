'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const fileStamp = (date = new Date()) => date.toISOString().replace(/[:.]/g, '-');

function safeName(value, fallback = 'backup') {
  return String(value || fallback)
    .replace(/[^A-Za-z0-9_.-]+/g, '-')
    .replace(/^-+|-+$/g, '') || fallback;
}

function ensurePrivateDirectory(dirPath, { onInvalid } = {}) {
  if (fs.existsSync(dirPath)) {
    const stat = fs.lstatSync(dirPath);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw onInvalid
        ? onInvalid(dirPath)
        : new Error(`运行数据路径不是私有目录: ${dirPath}`);
    }
  } else {
    fs.mkdirSync(dirPath, { recursive: true, mode: 0o700 });
  }
  fs.chmodSync(dirPath, 0o700);
}

function secureTree(entryPath, { onUnsupported } = {}) {
  if (!fs.existsSync(entryPath)) return;
  const stat = fs.lstatSync(entryPath);
  const reject = (kind) => {
    throw onUnsupported
      ? onUnsupported(entryPath, kind)
      : new Error(kind === 'symlink'
        ? `运行数据不允许符号链接: ${entryPath}`
        : `运行数据包含不支持的文件类型: ${entryPath}`);
  };
  if (stat.isSymbolicLink()) reject('symlink');
  if (stat.isFile()) { fs.chmodSync(entryPath, 0o600); return; }
  if (!stat.isDirectory()) reject('unsupported');
  fs.chmodSync(entryPath, 0o700);
  for (const name of fs.readdirSync(entryPath)) {
    secureTree(path.join(entryPath, name), { onUnsupported });
  }
}

function writePrivateFileAtomic(filePath, content) {
  ensurePrivateDirectory(path.dirname(filePath));
  const tmp = `${filePath}.tmp-${process.pid}-${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  try {
    fs.writeFileSync(tmp, content, { mode: 0o600, flag: 'wx' });
    fs.chmodSync(tmp, 0o600);
    fs.renameSync(tmp, filePath);
    fs.chmodSync(filePath, 0o600);
  } finally {
    try { fs.rmSync(tmp, { force: true }); } catch (_) {}
  }
}

function writePrivateJson(filePath, value) {
  writePrivateFileAtomic(filePath, JSON.stringify(value, null, 2));
}

function copyPrivateFile(src, dst) {
  fs.copyFileSync(src, dst);
  fs.chmodSync(dst, 0o600);
}

function hashFile(filePath) {
  const hash = crypto.createHash('sha256');
  const fd = fs.openSync(filePath, 'r');
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  try {
    let bytesRead;
    do {
      bytesRead = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (bytesRead) hash.update(buffer.subarray(0, bytesRead));
    } while (bytesRead);
  } finally {
    fs.closeSync(fd);
  }
  return hash.digest('hex');
}

module.exports = {
  fileStamp,
  safeName,
  ensurePrivateDirectory,
  secureTree,
  writePrivateFileAtomic,
  writePrivateJson,
  copyPrivateFile,
  hashFile,
};
