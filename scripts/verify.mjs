import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync, mkdirSync, readdirSync} from 'node:fs';
import {join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {root, runMoon} from './moon.mjs';
import {nativeEnv, buildNative} from './build-native.mjs';

export function sourceFingerprint() {
  const files = [];
  function walk(path) {
    for (const entry of readdirSync(path, {withFileTypes: true})) {
      if (['_build', '.git', '.moon', '.venv', '.local-tools', 'dist', 'node_modules'].includes(entry.name)) continue;
      const full = join(path, entry.name);
      const name = relative(root, full).replaceAll('\\', '/');
      if (name.startsWith('verification/local') || name.startsWith('verification/reports') || ['.local-toolchain.json', 'SOURCE_SHA256.txt'].includes(entry.name)) continue;
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile()) files.push(name);
    }
  }
  walk(root); files.sort();
  const hash = createHash('sha256');
  for (const name of files) { hash.update(name + '\0'); hash.update(readFileSync(join(root, name))); hash.update('\0'); }
  return {sha256: hash.digest('hex'), files: files.length};
}
export function verify() {
const checks = [];
function record(name, output) { checks.push({name, status: 'passed', output}); console.log(name + ': passed'); }
function command(executable, args) {
  const result = spawnSync(executable, args, {cwd: root, encoding: 'utf8', env: {...process.env, PYTHONUTF8: '1'}, maxBuffer: 16 * 1024 * 1024, timeout: 180000});
  if (result.error || result.status !== 0) throw new Error(result.error?.message || result.stdout + result.stderr);
  return (result.stdout + result.stderr).trim();
}
try {
  const version = runMoon(['version']);
  record('MoonBit JS checks', runMoon(['check', '--target', 'js', '--deny-warn']));
  record('MoonBit JS unit tests', runMoon(['test', '--target', 'js', '--deny-warn']));
  record('MoonBit wasm-gc unit tests', runMoon(['test', '--target', 'wasm-gc', '--deny-warn']));
  const env = nativeEnv();
  record('MoonBit native unit tests', runMoon(['test', '--target', 'native', '--deny-warn'], env));
  record('MoonBit direct JS example', runMoon(['run', 'src/examples/main', '--target', 'js']));
  record('MoonBit direct wasm-gc example', runMoon(['run', 'src/examples/main', '--target', 'wasm-gc']));
  record('MoonBit direct native example', runMoon(['run', 'src/examples/main', '--target', 'native'], env));
  record('MoonBit JS bridge build', runMoon(['build', 'src/bridge', '--target', 'js', '--release', '--deny-warn']));
  const executable = buildNative();
  record('Native release build', relative(root, executable));
  record('JS differential and malformed input tests', command(process.execPath, ['scripts/js-checks.mjs']));
  const python = process.env.MOONMAT_PYTHON || join(root, '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');
  record('Independent SciPy/NumPy cross-compatibility', command(python, ['scripts/interop.py']));
  const fingerprint = sourceFingerprint();
  const report = {
    status: 'passed', version: '0.0.1', checked_at: new Date().toISOString(), source: fingerprint,
    environment: {moon: version, node: process.version, platform: process.platform, arch: process.arch}, checks,
    native_sha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    scope: 'Local source/build/runtime and independent SciPy/NumPy verification. MATLAB/Octave execution, public publishing and organizer acceptance are unverified.',
  };
  mkdirSync(join(root, 'verification/reports'), {recursive: true});
  for (const [name, data] of [['v0.0.1.json', report], ['interop-v0.0.1.json', JSON.parse(readFileSync(join(root, 'verification/local/interop-report.json'), 'utf8'))], ['js-v0.0.1.json', JSON.parse(readFileSync(join(root, 'verification/local/js-report.json'), 'utf8'))]]) {
    writeFileSync(join(root, 'verification/reports', name), JSON.stringify(data, null, 2) + '\n');
  }
  console.log(JSON.stringify({status: 'passed', groups: checks.length, source: fingerprint}));
} catch (error) {
  console.error(error.message); process.exitCode = 1;
}
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) verify();
