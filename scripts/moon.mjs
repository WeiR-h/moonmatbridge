import {existsSync, readFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
export function toolchain() {
  const configPath = join(root, '.local-toolchain.json');
  const config = existsSync(configPath) ? JSON.parse(readFileSync(configPath, 'utf8')) : {};
  const moonHome = process.env.MOON_HOME || config.moonHome;
  const executable = process.env.MOONMAT_MOON || (moonHome ? join(moonHome, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon') : 'moon');
  const env = {...process.env, ...(moonHome ? {MOON_HOME: moonHome} : {}), MOONBIT_NEW_NATIVE: '0'};
  const pathKey = Object.keys(env).find(key => key.toLowerCase() === 'path');
  const inheritedPath = pathKey ? env[pathKey] : '';
  if (pathKey) delete env[pathKey];
  const separator = process.platform === 'win32' ? ';' : ':';
  env.PATH = [moonHome ? join(moonHome, 'bin') : '', dirname(process.execPath), inheritedPath].filter(Boolean).join(separator);
  if (process.platform === 'win32' && config.msvc) {
    const m = config.msvc;
    env.PATH = m.bin + separator + env.PATH;
    env.INCLUDE = [join(m.vcRoot,'include'), ...['ucrt','shared','um','winrt'].map(x=>join(m.sdkRoot,'Include',m.sdkVersion,x))].join(';');
    env.LIB = [join(m.vcRoot,'lib','x64'), ...['ucrt','um'].map(x=>join(m.sdkRoot,'Lib',m.sdkVersion,x,'x64'))].join(';');
    env.MOON_CC = join(m.bin,'cl.exe');
    env.MOON_AR = join(m.bin,'lib.exe');
  }
  return {executable, env, config};
}
export function runMoon(args, extraEnv = {}) {
  const t = toolchain();
  // Avoid parallel compiler/test processes exhausting memory on development machines.
  if (['check', 'test', 'build'].includes(args[0]) && !args.includes('--jobs') && !args.includes('-j')) {
    args = [...args, '--jobs', process.env.MOONMAT_JOBS || '1'];
  }
  if (args[0] === 'test' && !args.includes('--no-parallelize')) args = [...args, '--no-parallelize'];
  const result = spawnSync(t.executable, args, {cwd: root, env: {...t.env, ...extraEnv}, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${args.join(' ')} failed\n${result.stdout}\n${result.stderr}`);
  return (result.stdout + result.stderr).trim();
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(runMoon(process.argv.slice(2))); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
