import {spawnSync} from 'node:child_process';
import {readFileSync, readdirSync} from 'node:fs';
import {dirname, join, relative} from 'node:path';
import {createHash} from 'node:crypto';
import {toolchain, root} from './moon.mjs';

export function parseCompiler(actual) {
  const match = actual.match(/v?(\d+)\.(\d+)\.(\d+)(\+[^\s]+)?/);
  if (!match) throw new Error('Unrecognized moonc version: ' + actual);
  const parts = match.slice(1, 4).map(Number);
  if (parts[0] === 0 && (parts[1] < 10 || parts[1] === 10 && parts[2] < 16)) {
    throw new Error('moonc >= 0.10.16 is required; configured compiler: ' + actual);
  }
  return match[0].replace(/^v/, '');
}

export function compilerIdentity() {
  const t = toolchain();
  const compiler = join(dirname(t.executable), process.platform === 'win32' ? 'moonc.exe' : 'moonc');
  const result = spawnSync(compiler, ['-v'], {env: t.env, encoding: 'utf8'});
  if (result.error || result.status !== 0) throw new Error('Cannot query the configured moonc compiler');
  const actual = (result.stdout + result.stderr).trim();
  const lock = JSON.parse(readFileSync(join(root, 'toolchain.lock.json'), 'utf8'));
  const version = parseCompiler(actual);
  if (version !== lock.compiler) throw new Error('Compiler differs from toolchain.lock.json: ' + version);
  const files = [];
  const core = join(dirname(dirname(compiler)), 'lib', 'core');
  function walk(path) {
    for (const entry of readdirSync(path, {withFileTypes:true})) {
      if (entry.name.startsWith('.') || entry.name === '_build') continue;
      const file = join(path, entry.name);
      if (entry.isDirectory()) walk(file);
      else if (entry.name.endsWith('.mbt') || entry.name === 'moon.pkg' || entry.name === 'moon.mod') files.push(file);
    }
  }
  walk(core);
  const hash = createHash('sha256');
  for (const file of files.sort()) hash.update(relative(core,file).replaceAll('\\','/')+'\0').update(readFileSync(file)).update('\0');
  const msvc = process.platform==='win32' && (t.config.msvc || process.env.VCToolsInstallDir || process.env.INCLUDE && process.env.LIB);
  if (process.platform==='win32' && !msvc) throw new Error('Windows native verification requires MSVC and Windows SDK; run python scripts/setup-msvc.py --configure or use an MSVC developer prompt');
  const cc = spawnSync(msvc ? (t.config.msvc ? join(t.config.msvc.bin,'cl.exe') : 'cl.exe') : (t.config.gcc || process.env.MOONMAT_GCC || 'cc'), msvc ? [] : ['--version'], {encoding:'utf8',env:t.env});
  const ccOutput = (cc.stdout||'')+(cc.stderr||'');
  if (cc.error || (msvc ? !ccOutput.includes('Compiler Version') : cc.status!==0)) throw new Error('Cannot query native C compiler: '+ccOutput);
  return {compiler: actual, compiler_version: version, standard_library_archive_sha256: lock.core.sha256,
    standard_library_source_sha256: hash.digest('hex'), c_compiler:ccOutput.split(/\r?\n/).find(x=>msvc ? x.includes('Compiler Version') : x.trim()),
    native_backend: 'c', native_environment: {MOONBIT_NEW_NATIVE: '0'}, node: process.version,
    ...(msvc ? {windows_sdk_version:t.config.msvc?.sdkVersion || process.env.WindowsSDKVersion} : {}),
    platform: process.platform, architecture: process.arch};
}

if (process.argv[1]?.endsWith('toolchain.mjs')) {
  try { console.log(JSON.stringify(compilerIdentity(), null, 2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
