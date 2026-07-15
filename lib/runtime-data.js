'use strict';

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const DEFAULT_MASTER_CSV = 'Typeless词库主清单.csv';

class RuntimeDataError extends Error {
  constructor(message, code, details = {}) {
    super(message);
    this.name = 'RuntimeDataError';
    this.code = code;
    Object.assign(this, details);
  }
}

function expandHome(value, homeDir) {
  return String(value).replace(/^~(?=$|\/|\\)/, homeDir);
}

function ensurePrivateDirectory(dirPath) {
  if (fs.existsSync(dirPath)) {
    const stat = fs.lstatSync(dirPath);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      throw new RuntimeDataError(
        `Runtime data path is not a private directory: ${dirPath}`,
        'RUNTIME_DATA_PATH_INVALID',
        { path: dirPath },
      );
    }
  } else {
    fs.mkdirSync(dirPath, { recursive: true, mode: 0o700 });
  }
  fs.chmodSync(dirPath, 0o700);
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

function secureEntry(entryPath) {
  if (!fs.existsSync(entryPath)) return;
  const stat = fs.lstatSync(entryPath);
  if (stat.isSymbolicLink()) {
    throw new RuntimeDataError(
      `Runtime data contains a symbolic link: ${entryPath}`,
      'RUNTIME_DATA_ENTRY_UNSUPPORTED',
      { path: entryPath },
    );
  }
  if (stat.isFile()) {
    fs.chmodSync(entryPath, 0o600);
    return;
  }
  if (!stat.isDirectory()) {
    throw new RuntimeDataError(
      `Runtime data contains an unsupported entry: ${entryPath}`,
      'RUNTIME_DATA_ENTRY_UNSUPPORTED',
      { path: entryPath },
    );
  }
  fs.chmodSync(entryPath, 0o700);
  for (const name of fs.readdirSync(entryPath)) secureEntry(path.join(entryPath, name));
}

function secureKnownRuntimeEntries(dataDir, masterCsvName) {
  ensurePrivateDirectory(dataDir);
  const names = new Set([
    ...runtimeDataItems(masterCsvName),
    'patch-backups',
  ]);
  if (fs.existsSync(dataDir)) {
    for (const name of fs.readdirSync(dataDir)) {
      if (/^accounts\.json(?:\.corrupt-[A-Za-z0-9_.-]+)?\.bak$/.test(name)) names.add(name);
    }
  }
  for (const name of names) secureEntry(path.join(dataDir, name));
}

function runtimeDataItems(masterCsvName) {
  if (!masterCsvName || path.basename(masterCsvName) !== masterCsvName) {
    throw new RuntimeDataError(
      `Invalid master CSV filename: ${masterCsvName}`,
      'RUNTIME_DATA_MASTER_NAME_INVALID',
    );
  }
  return [
    'accounts.json',
    'profiles',
    'runtime-backups',
    masterCsvName,
    'config.local.json',
    'typeless-version.json',
  ];
}
/** Resolve and prepare the native app runtime data directory. */
function initializeRuntimeData(options = {}) {
  const codeDir = path.resolve(options.codeDir || path.join(__dirname, '..'));
  const homeDir = path.resolve(options.homeDir || os.homedir());
  const env = options.env || process.env;
  const masterCsvName = options.masterCsvName || DEFAULT_MASTER_CSV;
  const override = typeof env.TYPELESS_DATA_DIR === 'string' && env.TYPELESS_DATA_DIR.trim()
    ? env.TYPELESS_DATA_DIR.trim()
    : null;
  const dataDir = path.resolve(
    override
      ? expandHome(override, homeDir)
      : path.join(homeDir, 'Library', 'Application Support', 'Typeless Switch'),
  );

  secureKnownRuntimeEntries(dataDir, masterCsvName);
  return {
    dataDir,
    codeDir,
    overridden: Boolean(override),
    // Kept for the diagnostic DTO and protocol compatibility. This native-only
    // distribution deliberately has no project-directory migration path.
    migration: { status: 'none' },
  };
}


function inspectRegularFile(filePath, options = {}) {
  if (typeof filePath !== 'string' || !path.isAbsolute(filePath)) {
    throw new RuntimeDataError('Backup path must be absolute', 'BACKUP_INVALID');
  }
  const resolved = path.resolve(filePath);
  const entry = fs.lstatSync(resolved);
  if (entry.isSymbolicLink() || !entry.isFile()) {
    throw new RuntimeDataError('Backup path must be a regular file', 'BACKUP_INVALID');
  }
  const realpath = fs.realpathSync(resolved);
  const stat = fs.statSync(realpath);
  const maxBytes = options.maxBytes || 128 * 1024 * 1024;
  if (stat.size > maxBytes) throw new RuntimeDataError('Backup file is too large', 'BACKUP_INVALID');
  return {
    realpath,
    dev: stat.dev,
    ino: stat.ino,
    size: stat.size,
    sha256: hashFile(realpath),
  };
}

function verifyRegularFileInspection(inspection, options = {}) {
  let current;
  try {
    current = inspectRegularFile(inspection.realpath, options);
  } catch (error) {
    throw new RuntimeDataError('Backup file changed after inspection', 'BACKUP_CHANGED', { cause: error });
  }
  for (const field of ['realpath', 'dev', 'ino', 'size', 'sha256']) {
    if (current[field] !== inspection[field]) {
      throw new RuntimeDataError('Backup file changed after inspection', 'BACKUP_CHANGED', { field });
    }
  }
  return current;
}

function writeRegularFileAtomic(destination, content) {
  if (typeof destination !== 'string' || !path.isAbsolute(destination)) {
    throw new RuntimeDataError('Export path must be absolute', 'BACKUP_INVALID');
  }
  let resolved = path.resolve(destination);
  const parent = fs.realpathSync(path.dirname(resolved));
  resolved = path.join(parent, path.basename(resolved));
  if (fs.existsSync(resolved)) {
    const existing = fs.lstatSync(resolved);
    if (existing.isSymbolicLink() || !existing.isFile()) {
      throw new RuntimeDataError('Export destination must be a regular file', 'BACKUP_INVALID');
    }
  }
  const temporary = path.join(parent, `.${path.basename(resolved)}.${crypto.randomBytes(6).toString('hex')}.tmp`);
  let fd;
  try {
    fd = fs.openSync(temporary, 'wx', 0o600);
    fs.writeFileSync(fd, content);
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    fd = undefined;
    fs.renameSync(temporary, resolved);
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
    try { fs.rmSync(temporary, { force: true }); } catch (_) {}
  }
  return resolved;
}

module.exports = {
  RuntimeDataError,
  initializeRuntimeData,
  inspectRegularFile,
  verifyRegularFileInspection,
  writeRegularFileAtomic,
};
