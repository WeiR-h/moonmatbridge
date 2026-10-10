#!/usr/bin/env node
// Thin filesystem adapter for the MoonBit JS output. No binary format parsing in JavaScript.
import {readFileSync, writeFileSync, statSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {root, version} from './moon.mjs';

const api = await import(pathToFileURL(join(root, '_build/js/release/build/bridge/bridge.js')));
const limit = 64 * 1024 * 1024;
function read(path) {
  const stat = statSync(path);
  if (!stat.isFile() || stat.size > limit) throw new Error('Input must be a regular file within 64 MiB');
  const bytes = readFileSync(path);
  if (bytes.length > limit) throw new Error('Input grew beyond 64 MiB');
  return bytes;
}
function checkedJSON(text) {
  const value = JSON.parse(text);
  if (value.status === 'error') throw Object.assign(new Error(value.message), {diagnostic: value});
  return text;
}
function bytes(result) {
  checkedJSON(api.result_status(result));
  return api.result_bytes(result);
}
function save(path, data) {
  writeFileSync(path, data, {flag: 'wx'});
  console.log(JSON.stringify({status: 'ok', output: path, bytes: Buffer.byteLength(data), version}));
}
const [command = 'help', ...args] = process.argv.slice(2);
try {
  if (command === 'version' && args.length === 0) console.log(`MoonMatBridge v${version}`);
  else if (command === 'info' && args.length === 1) console.log(checkedJSON(api.inspect_mat(read(args[0]))));
  else if (command === 'dump' && args.length === 2) save(args[1], checkedJSON(api.mat_to_json(read(args[0]))) + '\n');
  else if (command === 'pack' && args.length === 2) save(args[1], bytes(api.json_to_mat(new TextDecoder('utf-8', {fatal: true}).decode(read(args[0])))));
  else if (command === 'snapshot' && args.length === 2) save(args[1], checkedJSON(api.mat_to_snapshot(read(args[0]))) + '\n');
  else if (command === 'restore' && args.length === 2) save(args[1], bytes(api.snapshot_to_mat(new TextDecoder('utf-8', {fatal: true}).decode(read(args[0])))));
  else if (command === 'diff' && (args.length === 2 || args.length === 3)) {
    const report = checkedJSON(api.compare_mat(read(args[0]), read(args[1])));
    if (args.length === 3) save(args[2], report + '\n'); else console.log(report);
    process.exitCode = JSON.parse(report).content_equal ? 0 : 2;
  }
  else if (command === 'roundtrip' && args.length === 2) save(args[1], bytes(api.roundtrip_mat(read(args[0]))));
  else if (command === 'compress' && args.length === 2) save(args[1], bytes(api.compress_mat(read(args[0]))));
  else if (['sparsify', 'densify'].includes(command) && args.length === 3) save(args[2], bytes(api.convert_storage(read(args[0]), args[1], command === 'sparsify')));
  else if (command === 'npy' && args.length === 3) save(args[2], bytes(api.mat_to_npy(read(args[0]), args[1])));
  else if (command === 'from-npy' && args.length === 3) save(args[2], bytes(api.npy_to_mat(read(args[0]), args[1])));
  else if (command === 'select' && args.length >= 3) save(args[1], bytes(api.select_mat(read(args[0]), args.slice(2))));
  else if (command === 'transform' && args.length === 3) save(args[2], bytes(api.transform_mat(read(args[0]), new TextDecoder('utf-8', {fatal: true}).decode(read(args[1])))));
  else if (command === 'sample' && args.length === 1) save(args[0], bytes(api.sample_mat()));
  else if (command === 'help' || command === '--help') console.log(`MoonMatBridge v${version}\ninfo INPUT.mat\ndump INPUT.mat OUTPUT.json\npack INPUT.json OUTPUT.mat\nroundtrip INPUT.mat OUTPUT.mat\ncompress INPUT.mat OUTPUT.mat\nnpy INPUT.mat VARIABLE OUTPUT.npy\nfrom-npy INPUT.npy VARIABLE OUTPUT.mat\nselect INPUT.mat OUTPUT.mat VARIABLE...\ntransform INPUT.mat PLAN.json OUTPUT.mat\nsparsify INPUT.mat VARIABLE OUTPUT.mat\ndensify INPUT.mat VARIABLE OUTPUT.mat\nsnapshot INPUT.mat OUTPUT.json\nrestore SNAPSHOT.json OUTPUT.mat\ndiff LEFT.mat RIGHT.mat [REPORT.json]\nsample OUTPUT.mat\nversion\nOutput files must be new. Diff exits: 0 equal, 2 changed, 1 error.`);
  else throw new Error('Invalid command or arguments. Run help.');
} catch (error) {
  console.error(JSON.stringify(error.diagnostic || {status: 'error', code: error.code === 'EEXIST' ? 'output-exists' : 'host-error', message: error.message}));
  process.exitCode = 1;
}
