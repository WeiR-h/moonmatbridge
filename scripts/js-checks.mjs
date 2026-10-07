import assert from 'node:assert/strict';
import {deflateSync, constants} from 'node:zlib';
import {createHash} from 'node:crypto';
import {mkdirSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {root, version} from './moon.mjs';

const api = await import(pathToFileURL(join(root, '_build/js/release/build/bridge/bridge.js')));
const checks = [];
function status(result) { return JSON.parse(api.result_status(result)); }
function checked(result) { assert.equal(status(result).status, 'ok'); return Buffer.from(api.result_bytes(result)); }
function record(name, detail) { checks.push({name, status: 'passed', detail}); }
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

let seed = 20261007;
function randomByte() { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return seed & 255; }
const strategies = [constants.Z_DEFAULT_STRATEGY, constants.Z_FIXED, constants.Z_HUFFMAN_ONLY, constants.Z_RLE];
const corpus = [Buffer.alloc(0), Buffer.from('hello hello hello'), Buffer.alloc(120000, 7), Buffer.from('科学数据\n'.repeat(2500))];
for (let i = 0; i < 40; i++) {
  const length = (i * 7919 + 13) % 20000;
  const buffer = Buffer.alloc(length);
  for (let j = 0; j < length; j++) buffer[j] = i % 3 === 0 ? randomByte() : randomByte() % (i % 3 === 1 ? 8 : 64);
  corpus.push(buffer);
}
let streams = 0;
let truncations = 0;
const blockTypes = new Set();
for (const input of corpus) {
  for (const level of [0, 1, 6, 9]) {
    for (const strategy of strategies) {
      const encoded = deflateSync(input, {level, strategy});
      blockTypes.add((encoded[2] >>> 1) & 3);
      assert.deepEqual(checked(api.inflate_zlib(encoded, input.length)), input);
      if (input.length > 0) assert.equal(status(api.inflate_zlib(encoded, input.length - 1)).code, 'expanded-limit');
      const broken = Buffer.from(encoded); broken[broken.length - 1] ^= 1;
      assert.equal(status(api.inflate_zlib(broken, 1024 * 1024)).code, 'invalid-zlib');
      if (streams % 16 === 0) {
        for (let size = 0; size < encoded.length; size++) {
          if (size > 32 && size < encoded.length - 16) continue;
          assert.equal(status(api.inflate_zlib(encoded.subarray(0, size), 1024 * 1024)).status, 'error');
          truncations++;
        }
      }
      streams++;
    }
  }
}
assert.deepEqual([...blockTypes].sort(), [0, 1, 2]);
record('RFC 1950/1951 differential corpus', {streams, strategies: 4, levels: 4, first_block_types: [...blockTypes].sort(), truncations, oracle: 'Node built-in zlib'});
const dictionary = Buffer.from('scientific dictionary');
assert.equal(status(api.inflate_zlib(deflateSync(Buffer.from('dictionary data'), {dictionary}), 1024)).code, 'unsupported-zlib');
record('preset dictionaries rejected explicitly');

const sample = checked(api.sample_mat());
const info = JSON.parse(api.inspect_mat(sample));
assert.equal(info.arrays.length, 4);
assert.equal(info.arrays[2].dtype, 'uint64');
assert.deepEqual(checked(api.roundtrip_mat(sample)), sample);
assert.deepEqual(checked(api.json_to_mat(api.mat_to_json(sample))), sample);
record('browser-compatible JS exports', {sample_sha256: hash(sample), deterministic_roundtrip: true, data_schema: 'moonmatbridge/1'});

const invalid = [];
function mutate(offset, data) { const out = Buffer.from(sample); Buffer.from(data).copy(out, offset); return out; }
invalid.push(['negative dimensions', mutate(160, [0, 0, 0, 128]), 'invalid-shape']);
invalid.push(['oversized dimensions', mutate(160, [255, 255, 255, 127, 255, 255, 255, 127]), 'element-limit']);
invalid.push(['oversized tag length', mutate(132, [255, 255, 255, 255]), 'truncated-data']);
invalid.push(['flags length', mutate(140, [7, 0, 0, 0]), 'invalid-flags']);
invalid.push(['MAT version', mutate(125, [2]), 'unsupported-version']);
invalid.push(['subsystem metadata', mutate(116, [1]), 'unsupported-subsystem']);
invalid.push(['unknown matrix class', mutate(144, [2]), 'unsupported-class']);
invalid.push(['missing imaginary data', mutate(145, [8]), 'truncated-tag']);
for (const [name, bytes, expected] of invalid) {
  const response = JSON.parse(api.inspect_mat(bytes));
  assert.equal(response.status, 'error', name);
  assert.equal(response.code, expected, name);
}
record('malformed MAT boundaries and resource limits', invalid.map(([name]) => name));

const malformed = [null, {}, {schema: 'moonmatbridge/1', order: 'row-major', arrays: []},
  {schema: 'moonmatbridge/1', order: 'column-major', arrays: [{name: 'x', dtype: 'uint64', shape: [1, 1], real: [9007199254740993]}]},
  {schema: 'moonmatbridge/1', order: 'column-major', arrays: [{name: 'x', dtype: 'int8', shape: [1, 1], real: [128]}]},
  {schema: 'moonmatbridge/1', order: 'column-major', arrays: [{name: 'x', dtype: 'float64', shape: [1, 1], real: [1], shpae: [1, 1]}]}];
for (const document of malformed) assert.equal(status(api.json_to_mat(JSON.stringify(document))).status, 'error');
assert.equal(status(api.mat_to_npy(sample, 'absent')).code, 'missing-variable');
record('strict JSON schema and absent variable diagnostics', {invalid_documents: malformed.length});

mkdirSync(join(root, 'verification/local'), {recursive: true});
const report = {status: 'passed', version, node: process.version, platform: process.platform, checks, passed: checks.length};
writeFileSync(join(root, 'verification/local/js-report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({status: 'passed', checks: checks.length, streams, truncations}));
