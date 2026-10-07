import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {sourceFingerprint} from './verify.mjs';
import {root, toolchain} from './moon.mjs';

const report = JSON.parse(readFileSync(join(root, 'verification/reports/v0.0.1.json'), 'utf8'));
const fingerprint = sourceFingerprint();
if (report.status !== 'passed' || report.source.sha256 !== fingerprint.sha256) throw new Error('Source changed since verification. Run npm run verify before packaging.');
const python = process.env.MOONMAT_PYTHON || toolchain().config.python || join(root, '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');
const result = spawnSync(python, ['scripts/package_release.py'], {cwd: root, encoding: 'utf8', env: {...process.env, PYTHONUTF8: '1'}, maxBuffer: 4 * 1024 * 1024, timeout: 180000});
if (result.error || result.status !== 0) throw new Error(result.error?.message || result.stdout + result.stderr);
console.log(result.stdout.trim());
