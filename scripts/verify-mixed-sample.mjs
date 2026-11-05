import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const [bridge, sample] = process.argv.slice(2);
if (!bridge || !sample) throw new Error('Usage: node scripts/verify-mixed-sample.mjs BRIDGE.mjs SAMPLE.mat');
const api = await import(pathToFileURL(resolve(bridge)).href);
const result = JSON.parse(api.inspect_roots(new Uint8Array(readFileSync(sample))));
if (!Array.isArray(result.roots)) throw new Error(JSON.stringify(result));
const classes = [...new Set(result.roots.map(root => root.class_id))].sort((a, b) => a - b);
if (classes.length !== 15 || !classes.every((id, index) => id === index + 1)) {
  throw new Error('Mixed sample did not contain every public basic class: ' + classes.join(','));
}
console.log(JSON.stringify({status: 'passed', roots: result.roots.length, class_ids: classes}));
