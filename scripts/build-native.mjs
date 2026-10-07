import {mkdirSync, copyFileSync, existsSync} from 'node:fs';
import {join, dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {root, toolchain, runMoon} from './moon.mjs';

export function nativeEnv() {
  const config = toolchain().config;
  const compiler = process.env.MOONMAT_GCC || config.gcc || process.env.MOON_CC || (process.platform === 'win32' ? 'gcc.exe' : 'cc');
  const env = {...process.env, MOON_CC: compiler};
  if (process.platform === 'win32') {
    const directory = join(root, '.local-tools'); mkdirSync(directory, {recursive: true});
    const launcher = join(directory, 'cc.exe');
    const result = spawnSync(compiler, ['-municode', '-O2', join(root, 'scripts/native-cc.c'), '-o', launcher], {encoding: 'utf8'});
    if (result.status !== 0) throw new Error('C compiler launcher failed: ' + result.stderr);
    env.MOONMAT_GCC = compiler;
    env.MOON_CC = launcher;
    if (config.gcc || process.env.MOONMAT_GCC) env.MOON_AR = join(dirname(compiler), 'ar.exe');
  }
  return env;
}
export function buildNative() {
  const env = nativeEnv();
  console.log(runMoon(['build', 'src/cmd/moonmat', '--target', 'native', '--release', '--deny-warn'], env));
  const built = join(root, '_build/native/release/build/cmd/moonmat/moonmat.exe');
  if (!existsSync(built)) throw new Error('Native executable missing: ' + built);
  mkdirSync(join(root, 'dist'), {recursive: true});
  const result = join(root, 'dist', process.platform === 'win32' ? 'moonmat.exe' : 'moonmat');
  copyFileSync(built, result);
  return result;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(buildNative()); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
