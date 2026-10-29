import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync, mkdirSync, readdirSync} from 'node:fs';
import {join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {root, runMoon, version} from './moon.mjs';
import {nativeEnv, buildNative} from './build-native.mjs';

export function sourceFingerprint() {
  const files = [];
  function walk(path) {
    for (const entry of readdirSync(path, {withFileTypes: true})) {
      if (['_build', '.git', '.moon', '.venv', '.local-tools', 'dist', 'node_modules', '__pycache__', '.pytest_cache'].includes(entry.name)) continue;
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
  return {sha256: hash.digest('hex'), files: files.length, entries: files.map(file => ({file, sha256: createHash('sha256').update(readFileSync(join(root, file))).digest('hex')}))};
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
  const before = sourceFingerprint();
  const sdkVersion = runMoon(['version']);
  if (!readFileSync(join(root, 'moon.mod'), 'utf8').includes(`version = "${version}"`)) throw new Error('Manifest versions differ');
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
  record('All public Level 5 base classes in mixed files', command(python, ['scripts/compatibility.py']));
  record('Published API compatibility', command(python, ['scripts/api-contract.py']));
  record('Compatibility gap characterization', command(python, ['scripts/compatibility-gaps.py']));
  record('Explicit name codecs and independent mixed metadata checks', command(python, ['scripts/name-checks.py']));
  record('Independent producer length and class diagnostics', command(python, ['scripts/variant-analysis.py']));
  record('Performance evidence invalidation guards', command(python, ['scripts/test-evidence.py']));
  record('Strict selected reads and root metadata independent checks', command(python, ['scripts/selection-checks.py']));
  record('Large file sources and lifetime checks', command(python, ['scripts/source-checks.py']));
  record('Recursive mixed tree operations', command(python, ['scripts/tree-checks.py']));
  record('Symmetric mixed-tree tolerance and atomic reports', command(python, ['scripts/tree-close-checks.py']));
  const workflowOutput = command(python, ['scripts/scientific-workflows.py']);
  const workflowReceipt = join(root, `verification/reports/workflows-v${version}.json`);
  const firstWorkflows = JSON.parse(readFileSync(workflowReceipt, 'utf8'));
  command(python, ['scripts/scientific-workflows.py']);
  const secondWorkflows = JSON.parse(readFileSync(workflowReceipt, 'utf8'));
  const resultHashes = report => JSON.stringify(report.checks.map(row => [row.host, row.workflow, row.outputs]));
  if (resultHashes(firstWorkflows) !== resultHashes(secondWorkflows)) throw new Error('Scientific output bytes are not reproducible across fresh command processes');
  secondWorkflows.reproduction_repetitions = 2;
  writeFileSync(workflowReceipt, JSON.stringify(secondWorkflows, null, 2) + '\n');
  record('Three complete scientific workflows with independent oracles', workflowOutput + '; repeated outputs have identical hashes');
  const fingerprint = sourceFingerprint();
  const old = new Map(before.entries.map(entry => [entry.file, entry.sha256]));
  const current = new Map(fingerprint.entries.map(entry => [entry.file, entry.sha256]));
  const changed = [...new Set([...old.keys(), ...current.keys()])].filter(file => old.get(file) !== current.get(file));
  writeFileSync(join(root, `verification/reports/source-snapshot-v${version}.json`), JSON.stringify({status: changed.length ? 'failed' : 'passed', version, before, after: fingerprint, changed_files: changed}, null, 2) + '\n');
  if (changed.length) throw new Error('Source changed during verification: ' + changed.join(', '));
  const report = {
    status: 'passed', version, checked_at: new Date().toISOString(), source: fingerprint,
    environment: {moon: sdkVersion, node: process.version, platform: process.platform, arch: process.arch}, checks,
    native_sha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    scope: 'Local source/build/runtime and independent SciPy/NumPy verification. Actual Octave CI receipts are separate octave reports. Public package and download checks have separate receipts.',
  };
  mkdirSync(join(root, 'verification/reports'), {recursive: true});
  for (const [name, data] of [[`v${version}.json`, report], [ `interop-v${version}.json`, JSON.parse(readFileSync(join(root, 'verification/local/interop-report.json'), 'utf8'))], [ `js-v${version}.json`, JSON.parse(readFileSync(join(root, 'verification/local/js-report.json'), 'utf8'))]]) {
    writeFileSync(join(root, 'verification/reports', name), JSON.stringify(data, null, 2) + '\n');
  }
  console.log(JSON.stringify({status: 'passed', groups: checks.length, source: fingerprint}));
} catch (error) {
  console.error(error.message); process.exitCode = 1;
}
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) verify();
