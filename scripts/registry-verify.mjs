// Verify a fixed Mooncakes version in an isolated consumer, without local overrides.
import {spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {dirname, join, relative} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {root, toolchain, version} from './moon.mjs';
import {nativeEnv} from './build-native.mjs';
import {sourceFingerprint} from './verify.mjs';

const moduleName = 'WeiR-h/moonmatbridge';
const directory = mkdtempSync(join(tmpdir(), 'moonmatbridge-registry-'));
const report = {status: 'running', version, module: moduleName,
  source: sourceFingerprint(), platform: process.platform,
  method: 'Exact Mooncakes dependency in a fresh project; no moon.work, no path override; all installed src bytes compared.',
  steps: [], installed_files: 0};
const t = toolchain();
function run(args, extraEnv = {}) {
  if (['check', 'test'].includes(args[0])) args = [...args, '--jobs', '1'];
  if (args[0] === 'test') args = [...args, '--no-parallelize'];
  const result = spawnSync(t.executable, args, {cwd: directory, env: {...t.env, ...extraEnv},
    encoding: 'utf8', timeout: 180000, maxBuffer: 4 * 1024 * 1024});
  const output = (result.stdout || '') + (result.stderr || '');
  report.steps.push({args, exit_code: result.status, output: output.trim()});
  if (result.error || result.status !== 0) throw new Error(result.error?.message || output);
  console.log(args.join(' ') + ': passed');
  return output;
}
try {
  for (let ancestor = directory; ; ancestor = dirname(ancestor)) {
    if (existsSync(join(ancestor, 'moon.work'))) throw new Error('Ancestor workspace would override registry resolution');
    if (dirname(ancestor) === ancestor) break;
  }
  for (const name of ['moon.mod', 'moon.pkg', 'consumer_wbtest.mbt']) {
    copyFileSync(join(root, 'examples/registry_consumer', name), join(directory, name));
  }
  // Ordinary source exercises both imports during non-test `moon check` too.
  writeFileSync(join(directory, 'consumer.mbt'),
    '///|\npub fn installed_version() -> String { @mat.version() }\n' +
    '///|\npub fn snapshot(bytes : Bytes) -> String raise @mat.MatError {\n' +
    '  @wire.to_snapshot(@mat.read_document(bytes).variables)\n}\n');
  run(['add', moduleName + '@' + version]);
  const consumerManifest = readFileSync(join(directory, 'moon.mod'), 'utf8');
  if (existsSync(join(directory, 'moon.work')) || /\bpath\s*=/.test(consumerManifest)) {
    throw new Error('Unexpected local dependency override');
  }
  const installed = join(directory, '.mooncakes', moduleName);
  const manifest = readFileSync(join(installed, 'moon.mod'), 'utf8');
  if (!manifest.includes(`name = "${moduleName}"`) || !manifest.includes(`version = "${version}"`)) {
    throw new Error('Registry module/version mismatch');
  }
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  report.downloaded_manifest_sha256 = hash(Buffer.from(manifest));
  function compareSources(path) {
    for (const item of readdirSync(path, {withFileTypes: true})) {
      const actualPath = join(path, item.name);
      if (item.isDirectory()) compareSources(actualPath);
      else if (item.isFile()) {
        const name = relative(root, actualPath);
        const downloaded = join(installed, name);
        if (!existsSync(downloaded) || hash(readFileSync(downloaded)) !== hash(readFileSync(actualPath))) {
          throw new Error('Installed source differs: ' + name);
        }
        report.installed_files++;
      }
    }
  }
  compareSources(join(root, 'src'));
  run(['check', '--target', 'js', '--deny-warn']);
  for (const target of ['js', 'wasm-gc', 'native']) {
    const extra = target === 'native' ? nativeEnv() : {};
    const output = run(['test', '--target', target, '--deny-warn'], extra);
    const expected = (readFileSync(join(root, 'examples/registry_consumer/consumer_wbtest.mbt'), 'utf8').match(/^test /gm) || []).length;
    if (!output.includes(`Total tests: ${expected}, passed: ${expected}, failed: 0`)) throw new Error('Consumer tests did not execute for ' + target);
  }
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.message; process.exitCode = 1;
}
mkdirSync(join(root, 'verification/reports'), {recursive: true});
writeFileSync(join(root, `verification/reports/registry-v${version}.json`), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({status: report.status, version, installed_files: report.installed_files, error: report.error}));
