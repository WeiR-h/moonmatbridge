#!/usr/bin/env node
// Thin filesystem adapter for the MoonBit JS output. No binary format parsing in JavaScript.
import {readFileSync, writeFileSync, statSync, openSync, closeSync, fstatSync, readSync, writeSync, linkSync, unlinkSync, lstatSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {randomUUID} from 'node:crypto';
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
function withSource(path, work) {
  const fd = openSync(path, 'r');
  try {
    const before = fstatSync(fd, {bigint: true});
    if (!before.isFile() || before.size > 1073741824n) throw Object.assign(new Error('Input must be a regular file within 1 GiB'), {diagnostic: {status:'error',code:'file-limit',offset:0,message:'Source exceeds input quota'}});
    const source = codecApi.make_source(Number(before.size), (offset, target, start, length) => {
      try { return readSync(fd, target, start, length, offset); } catch { return -1; }
    });
    const result = work(source);
    const after = fstatSync(fd, {bigint: true});
    if (before.size!==after.size || before.mtimeNs!==after.mtimeNs || before.ctimeNs!==after.ctimeNs) throw Object.assign(new Error('Source changed during reading'), {diagnostic:{status:'error',code:'source-changed',offset:0,message:'Source changed during reading'}});
    return result;
  } finally { closeSync(fd); }
}
function checkedJSON(text) {
  const value = JSON.parse(text);
  if (value.status === 'error') throw Object.assign(new Error(value.message), {diagnostic: value});
  return text;
}
function bytes(result) {
  checkedJSON(codecApi.result_status(result));
  return codecApi.result_bytes(result);
}
function save(path, data) {
  writeFileSync(path, data, {flag: 'wx'});
  console.log(JSON.stringify({status: 'ok', output: path, bytes: Buffer.byteLength(data), version}));
}
// Additional fs imports: writeSync, linkSync, unlinkSync, lstatSync.
// Additional path import: dirname; crypto import: randomUUID.
function withSink(path, work) {
  let fd = null;
  let created = false;
  const temporary = join(dirname(path), `.moonmat-${randomUUID()}.tmp`);
  function openOutput() {
    try {
      lstatSync(path);
      throw Object.assign(new Error('Output already exists'), {code: 'EEXIST'});
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    fd = openSync(temporary, 'wx+');
    created = true;
  }
  let ioFailure;
  try {
    const sink = codecApi.make_sink((offset, buffer, start, count) => {
      try {
        if (fd === null) openOutput();
        return writeSync(fd, buffer, start, count, offset);
      } catch (error) { ioFailure = error; return -1; }
    });
    const text = work(sink);
    if (ioFailure) throw ioFailure;
    const result = JSON.parse(checkedJSON(text));
    if (fd === null || !Number.isInteger(result.bytes) || result.bytes < 128 || result.bytes > 1073741824 || fstatSync(fd).size !== result.bytes) {
      throw new Error('Output size mismatch');
    }
    const closing = fd; fd = null;
    closeSync(closing);
    // link is atomic and fails if any file/symlink now occupies the final name.
    linkSync(temporary, path);
    console.log(JSON.stringify({status:'ok',output:path,bytes:result.bytes,version}));
  } finally {
    try {
      if (fd !== null) { const closing = fd; fd = null; closeSync(closing); }
    } finally {
      if (created) { try { unlinkSync(temporary); } catch {} }
    }
  }
}

const argv = process.argv.slice(2);
let nameEncoding = 'utf8';
if (argv[0]?.startsWith('--name-encoding=')) nameEncoding = argv.shift().slice('--name-encoding='.length);
const codecApi = new Proxy(api, {get(target, key) {
  const enhanced = target[`${String(key)}_with_options`];
  return enhanced ? (...values) => enhanced(...values, JSON.stringify({name_encoding:nameEncoding})) : target[key];
}});
const [command = 'help', ...args] = argv;
try {
  if (!['utf8','latin1'].includes(nameEncoding)) throw Object.assign(new Error('Expected --name-encoding=utf8|latin1'), {diagnostic:{status:'error',code:'usage',offset:0,message:'Expected --name-encoding=utf8|latin1'}});
  if (command === 'version' && args.length === 0) console.log(`MoonMatBridge v${version}`);
  else if (command === 'info' && args.length === 1) console.log(checkedJSON(codecApi.inspect_mat(read(args[0]))));
  else if (command === 'roots' && args.length === 1) console.log(checkedJSON(withSource(args[0], source => codecApi.inspect_roots_source(source))));
  else if (command === 'dump' && args.length === 2) save(args[1], checkedJSON(codecApi.mat_to_json(read(args[0]))) + '\n');
  else if (command === 'pack' && args.length === 2) save(args[1], bytes(codecApi.json_to_mat(new TextDecoder('utf-8', {fatal: true}).decode(read(args[0])))));
  else if (command === 'snapshot-tree' && args.length === 2) save(args[1], checkedJSON(codecApi.mat_to_tree_snapshot(read(args[0]))) + '\n');
  else if (command === 'restore-tree' && args.length === 2) withSink(args[1], sink => codecApi.tree_snapshot_to_sink(new TextDecoder('utf-8', {fatal: true}).decode(read(args[0])),sink));
  else if (command === 'snapshot' && args.length === 2) save(args[1], checkedJSON(codecApi.mat_to_snapshot(read(args[0]))) + '\n');
  else if (command === 'restore' && args.length === 2) save(args[1], bytes(codecApi.snapshot_to_mat(new TextDecoder('utf-8', {fatal: true}).decode(read(args[0])))));
  else if (command === 'diff-tree-close' && (args.length === 3 || args.length === 4)) {
    const options = args.length === 4 ? new TextDecoder('utf-8', {fatal: true}).decode(read(args[3])) : '{}';
    const report = checkedJSON(codecApi.compare_mat_trees_close(read(args[0]), read(args[1]), options));
    save(args[2], report + '\n');
    process.exitCode = JSON.parse(report).within_tolerance ? 0 : 2;
  }
  else if (command === 'diff-tree' && args.length === 3) {
    const report = checkedJSON(codecApi.compare_mat_trees(read(args[0]), read(args[1]), 16));
    save(args[2], report + '\n');
    process.exitCode = JSON.parse(report).content_equal ? 0 : 2;
  }
  else if (command === 'diff' && (args.length === 2 || args.length === 3)) {
    const report = checkedJSON(codecApi.compare_mat(read(args[0]), read(args[1])));
    if (args.length === 3) save(args[2], report + '\n'); else console.log(report);
    process.exitCode = JSON.parse(report).content_equal ? 0 : 2;
  }
  else if (command === 'roundtrip' && args.length === 2) withSink(args[1], sink => codecApi.roundtrip_mat_to(read(args[0]), sink));
  else if (command === 'compress' && args.length === 2) save(args[1], bytes(codecApi.compress_mat(read(args[0]))));
  else if (['sparsify', 'densify'].includes(command) && args.length === 3) save(args[2], bytes(codecApi.convert_storage(read(args[0]), args[1], command === 'sparsify')));
  else if (command === 'npy' && args.length === 3) save(args[2], bytes(codecApi.mat_to_npy(read(args[0]), args[1])));
  else if (command === 'from-npy' && args.length === 3) save(args[2], bytes(codecApi.npy_to_mat(read(args[0]), args[1])));
  else if (command === 'select' && args.length >= 3) withSink(args[1], sink => withSource(args[0], source => codecApi.select_source_mat_to(source, args.slice(2), sink)));
  else if (command === 'transform' && args.length === 3) save(args[2], bytes(codecApi.transform_mat(read(args[0]), new TextDecoder('utf-8', {fatal: true}).decode(read(args[1])))));
  else if (command === 'sample' && args.length === 1) save(args[0], bytes(codecApi.sample_mat()));
  else if (command === 'help' || command === '--help') console.log(`MoonMatBridge v${version}\ninfo INPUT.mat\nroots INPUT.mat\ndump INPUT.mat OUTPUT.json\npack INPUT.json OUTPUT.mat\nroundtrip INPUT.mat OUTPUT.mat\ncompress INPUT.mat OUTPUT.mat\nnpy INPUT.mat VARIABLE OUTPUT.npy\nfrom-npy INPUT.npy VARIABLE OUTPUT.mat\nselect INPUT.mat OUTPUT.mat VARIABLE...\ntransform INPUT.mat PLAN.json OUTPUT.mat\nsparsify INPUT.mat VARIABLE OUTPUT.mat\ndensify INPUT.mat VARIABLE OUTPUT.mat\nsnapshot-tree INPUT.mat OUTPUT.json\nrestore-tree SNAPSHOT.json OUTPUT.mat\nsnapshot INPUT.mat OUTPUT.json\nrestore SNAPSHOT.json OUTPUT.mat\ndiff-tree-close LEFT.mat RIGHT.mat REPORT.json [OPTIONS.json]\ndiff-tree LEFT.mat RIGHT.mat REPORT.json\ndiff LEFT.mat RIGHT.mat [REPORT.json]\nsample OUTPUT.mat\nversion\nOptional prefix: --name-encoding=utf8|latin1\nOutput files must be new. Diff exits: 0 equal, 2 changed, 1 error.`);
  else throw new Error('Invalid command or arguments. Run help.');
} catch (error) {
  console.error(JSON.stringify(error.diagnostic || {status: 'error', code: error.code === 'EEXIST' ? 'output-exists' : 'host-error', message: error.message}));
  process.exitCode = 1;
}
