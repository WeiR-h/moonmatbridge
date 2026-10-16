import {resolve, join} from 'node:path';
import {pathToFileURL} from 'node:url';
const root = resolve(process.argv[2] || '.');
const {runMoon} = await import(pathToFileURL(join(root, 'scripts/moon.mjs')));
const {nativeEnv} = await import(pathToFileURL(join(root, 'scripts/build-native.mjs')));
console.log(runMoon(['build', 'src/cmd/bench', '--target', 'native', '--release', '--deny-warn'], nativeEnv()));
console.log(runMoon(['build', 'src/bench_bridge', '--target', 'js', '--release', '--deny-warn']));
